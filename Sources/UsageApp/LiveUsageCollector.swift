import CodexBarCore
import Foundation
import UsageCore

protocol ProviderUsageCollecting: Sendable {
    func fetch(_ provider: UsageProviderKind) async throws -> ProviderUsage
}

struct LiveUsageCollector: ProviderUsageCollecting {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func fetch(_ provider: UsageProviderKind) async throws -> ProviderUsage {
        switch provider {
        case .claude:
            try await self.fetchClaude()
        case .codex:
            try await self.fetchCodex()
        case .grok:
            try await self.fetchGrok()
        }
    }

    private func fetchClaude() async throws -> ProviderUsage {
        let snapshot = try await ClaudeUsageFetcher(
            browserDetection: BrowserDetection(),
            environment: self.environment,
            dataSource: .cli,
            useWebExtras: false,
            includePrepaidBalance: false,
            keepCLISessionsAlive: false,
            // The `/status` identity round trip only yields the account email,
            // and on Claude CLI 2.1.2xx it yields nothing at all while waiting
            // out a 12 s timeout. Usage never needs it.
            includesCLIIdentityProbe: false)
            .loadLatestUsage(model: "sonnet")
        var metrics = [Self.metric(id: "session", label: "5-hour", window: snapshot.primary)]
        if let secondary = snapshot.secondary {
            metrics.append(Self.metric(id: "weekly", label: "Weekly", window: secondary))
        }
        if let opus = snapshot.opus {
            metrics.append(Self.metric(id: "opus", label: "Opus weekly", window: opus))
        }
        metrics.append(contentsOf: Self.claudeScopedMetrics(from: snapshot))

        guard !metrics.isEmpty else { throw UsageCollectorError.noUsage(provider: .claude) }
        return ProviderUsage(
            provider: .claude,
            metrics: metrics,
            accountLabel: snapshot.accountEmail,
            // The subscription plan is deliberately not shown. The only
            // working local source is
            // `~/.claude.json`, which also carries every project path the CLI
            // has seen, and that is too much to read for a decorative label.
            sourceLabel: "Claude CLI")
    }

    private func fetchCodex() async throws -> ProviderUsage {
        let snapshot = try await UsageFetcher(environment: self.environment).loadLatestUsage()
        let metrics = Self.metrics(
            from: snapshot,
            primaryLabel: "5-hour",
            secondaryLabel: "Weekly",
            tertiaryLabel: "Additional")
        guard !metrics.isEmpty else { throw UsageCollectorError.noUsage(provider: .codex) }

        return ProviderUsage(
            provider: .codex,
            metrics: metrics,
            accountLabel: snapshot.accountEmail(for: .codex),
            sourceLabel: "Codex CLI")
    }

    private func fetchGrok() async throws -> ProviderUsage {
        do {
            return try await self.fetchGrokRPC()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            return try await self.fetchGrokBillingProxy()
        }
    }

    private func fetchGrokRPC() async throws -> ProviderUsage {
        let grokSnapshot = try await GrokStatusProbe().fetch(env: self.environment)
        let snapshot = grokSnapshot.toUsageSnapshot()
        let metrics = Self.metrics(
            from: snapshot,
            primaryLabel: "Monthly",
            secondaryLabel: "Secondary",
            tertiaryLabel: "Additional")
        guard !metrics.isEmpty else { throw UsageCollectorError.noUsage(provider: .grok) }

        return ProviderUsage(
            provider: .grok,
            metrics: metrics,
            accountLabel: snapshot.accountEmail(for: .grok),
            sourceLabel: "Grok CLI")
    }

    private func fetchGrokBillingProxy() async throws -> ProviderUsage {
        let credentials: GrokCredentials
        let billing: GrokBillingProxySnapshot
        do {
            credentials = try GrokCredentialsStore.load(env: self.environment)
            guard !credentials.isExpired else {
                throw UsageCollectorError.grokAuthenticationRequired
            }
            billing = try await Self.fetchGrokBillingProxy(credentials: credentials)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as UsageCollectorError {
            throw error
        } catch {
            // Do not persist provider response bodies from lower-level errors
            // into the popover or widget snapshot.
            throw UsageCollectorError.grokBillingUnavailable
        }
        guard let usage = ProviderUsage.grokCredits(
            usedPercent: billing.usedPercent,
            resetsAt: billing.resetsAt,
            accountLabel: credentials.email)
        else {
            throw UsageCollectorError.grokUsageUnavailable
        }
        return usage
    }

    private static func fetchGrokBillingProxy(
        credentials: GrokCredentials) async throws -> GrokBillingProxySnapshot
    {
        guard !credentials.isExpired else {
            throw UsageCollectorError.grokAuthenticationRequired
        }
        guard let endpoint = URL(
            string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        else {
            throw UsageCollectorError.grokBillingUnavailable
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Usage Agents", forHTTPHeaderField: "User-Agent")

        let response: ProviderHTTPResponse
        do {
            response = try await ProviderHTTPClient.shared.response(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw UsageCollectorError.grokBillingUnavailable
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw UsageCollectorError.grokAuthenticationRequired
        }
        guard response.statusCode == 200 else {
            throw UsageCollectorError.grokBillingUnavailable
        }

        do {
            return try GrokBillingProxyResponse.parse(response.data)
        } catch GrokBillingProxyResponseError.usageUnavailable {
            throw UsageCollectorError.grokUsageUnavailable
        } catch {
            throw UsageCollectorError.grokBillingUnavailable
        }
    }

    private static func metrics(
        from snapshot: UsageSnapshot,
        primaryLabel: String,
        secondaryLabel: String,
        tertiaryLabel: String) -> [UsageMetric]
    {
        var result: [UsageMetric] = []
        if let primary = snapshot.primary, !primary.isSyntheticPlaceholder {
            result.append(Self.metric(id: "primary", label: primaryLabel, window: primary))
        }
        if let secondary = snapshot.secondary, !secondary.isSyntheticPlaceholder {
            result.append(Self.metric(id: "secondary", label: secondaryLabel, window: secondary))
        }
        if let tertiary = snapshot.tertiary, !tertiary.isSyntheticPlaceholder {
            result.append(Self.metric(id: "tertiary", label: tertiaryLabel, window: tertiary))
        }
        if let extra = snapshot.extraRateWindows {
            result.append(contentsOf: extra.filter(\.usageKnown).map {
                Self.metric(id: $0.id, label: $0.title, window: $0.window)
            })
        }
        return result
    }

    /// Model-scoped weekly windows Claude reports alongside the shared limits —
    /// currently the promotional Fable window, and whatever else appears later.
    ///
    /// Upstream already maps these into `extraRateWindows` as
    /// `claude-weekly-scoped-<model>` with a `"<Model> only"` title; Usage simply
    /// never read the field. Two guards apply:
    ///
    /// - `usageKnown == false` means the window carries reset metadata but no
    ///   real usage. No Claude path produces such a window today — only the Zed
    ///   and Antigravity probes do — so this is forward defence, kept because
    ///   the Codex and Grok mappings below filter on the same flag and because
    ///   rendering an unknown percent is the failure the Grok zero-usage policy
    ///   exists to prevent.
    /// - A scoped window for the model that already occupies the dedicated
    ///   `snapshot.opus` row is dropped rather than shown twice. The CLI parser
    ///   discards those before they reach here, so this too is forward defence
    ///   path, where the mapper keeps them.
    private static func claudeScopedMetrics(from snapshot: ClaudeUsageSnapshot) -> [UsageMetric] {
        snapshot.extraRateWindows.compactMap { named in
            guard named.usageKnown else { return nil }
            guard !ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
                title: named.title,
                hasPrimaryModelWindow: snapshot.opus != nil)
            else { return nil }
            return Self.metric(
                id: named.id,
                label: ClaudeScopedWindowLabel.displayLabel(title: named.title),
                window: named.window)
        }
    }

    private static func metric(id: String, label: String, window: RateWindow) -> UsageMetric {
        UsageMetric(
            id: id,
            label: label,
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt,
            resetDescription: window.resetDescription)
    }
}

enum UsageCollectorError: LocalizedError {
    case noUsage(provider: UsageProviderKind)
    case grokAuthenticationRequired
    case grokBillingUnavailable
    case grokUsageUnavailable

    var errorDescription: String? {
        switch self {
        case let .noUsage(provider):
            "No \(provider.displayName) quota data was returned."
        case .grokAuthenticationRequired:
            "Grok CLI authentication is unavailable or expired."
        case .grokBillingUnavailable:
            "Grok CLI billing did not return quota data."
        case .grokUsageUnavailable:
            "Grok did not publish a usage percentage for the current billing period."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .grokAuthenticationRequired:
            "Run `grok login`, then refresh."
        case .grokBillingUnavailable:
            "Refresh again later."
        case .grokUsageUnavailable:
            nil
        case .noUsage:
            nil
        }
    }
}
