import Foundation

/// Parses the bounded, display-safe portion of Grok CLI proxy billing responses.
/// It deliberately does not decode account identifiers, tokens, or raw errors.
/// The versioned mapping contract is documented in docs/GROK_ZERO_USAGE_POLICY.md.
public enum GrokBillingProxyResponse {
    public static let policyVersion = 1
    public static let maximumResponseBytes = 512 * 1024

    public static func parse(_ data: Data) throws -> GrokBillingProxySnapshot {
        guard !data.isEmpty, data.count <= self.maximumResponseBytes else {
            throw GrokBillingProxyResponseError.invalidResponse
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GrokBillingProxyResponseError.invalidResponse
        }
        guard let config = response.config else {
            throw GrokBillingProxyResponseError.invalidResponse
        }

        let resetsAt = try self.resetDate(config: config)
        if let percent = config.creditUsagePercent {
            guard percent.isFinite else {
                throw GrokBillingProxyResponseError.invalidUsage
            }
            return GrokBillingProxySnapshot(
                usedPercent: min(100, max(0, percent)),
                resetsAt: resetsAt,
                source: .reportedPercent)
        }

        if let cap = config.onDemandCap?.val,
           cap.isFinite,
           cap > 0,
           let used = config.onDemandUsed?.val,
           used.isFinite
        {
            return GrokBillingProxySnapshot(
                usedPercent: min(100, max(0, used / cap * 100)),
                resetsAt: resetsAt,
                source: .onDemandRatio)
        }

        if try self.isVerifiedEmptyUnifiedPeriod(config) {
            return GrokBillingProxySnapshot(
                usedPercent: 0,
                resetsAt: resetsAt,
                source: .verifiedEmptyUnifiedPeriod)
        }

        throw GrokBillingProxyResponseError.usageUnavailable
    }

    private static func isVerifiedEmptyUnifiedPeriod(_ config: Config) throws -> Bool {
        guard config.isUnifiedBillingUser == true,
              try self.validatedPeriod(config.currentPeriod) != nil,
              try self.isExplicitZero(config.onDemandCap),
              try self.isExplicitZero(config.onDemandUsed),
              try self.isExplicitZero(config.prepaidBalance),
              config.productUsage?.isEmpty ?? true
        else {
            return false
        }
        return true
    }

    private static func isExplicitZero(_ amount: Amount?) throws -> Bool {
        guard let value = amount?.val else { return false }
        guard value.isFinite else {
            throw GrokBillingProxyResponseError.invalidUsage
        }
        return value == 0
    }

    private static func resetDate(config: Config) throws -> Date? {
        if let period = try self.validatedPeriod(config.currentPeriod) {
            return period.end
        }
        guard let raw = config.billingPeriodEnd else { return nil }
        guard let date = self.parseISO8601(raw) else {
            throw GrokBillingProxyResponseError.invalidResponse
        }
        return date
    }

    private static func validatedPeriod(_ period: CurrentPeriod?) throws -> (
        start: Date,
        end: Date)?
    {
        guard let period else { return nil }
        guard let startRaw = period.start,
              let endRaw = period.end,
              let start = self.parseISO8601(startRaw),
              let end = self.parseISO8601(endRaw),
              end > start
        else {
            throw GrokBillingProxyResponseError.invalidResponse
        }
        return (start, end)
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

public struct GrokBillingProxySnapshot: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let source: GrokBillingUsageSource

    public init(usedPercent: Double, resetsAt: Date?, source: GrokBillingUsageSource) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.source = source
    }
}

public enum GrokBillingUsageSource: String, Equatable, Sendable {
    case reportedPercent
    case onDemandRatio
    case verifiedEmptyUnifiedPeriod
}

public enum GrokBillingProxyResponseError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidUsage
    case usageUnavailable
}

private struct Response: Decodable {
    let config: Config?
}

private struct Config: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: CurrentPeriod?
    let billingPeriodEnd: String?
    let onDemandCap: Amount?
    let onDemandUsed: Amount?
    let prepaidBalance: Amount?
    let isUnifiedBillingUser: Bool?
    let productUsage: [ProductUsage]?
}

private struct CurrentPeriod: Decodable {
    let start: String?
    let end: String?
}

private struct Amount: Decodable {
    let val: Double?
}

private struct ProductUsage: Decodable {}
