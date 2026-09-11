import SwiftUI
import UsageCore

enum ProviderBrand {
    // Lobe Icons 1.90.0 brand tokens: Claude primary and OpenAI GPT-3 green.
    static let claude = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let gpt = Color(red: 25.0 / 255.0, green: 195.0 / 255.0, blue: 125.0 / 255.0)
    static let grokMeter = Color(red: 0.50, green: 0.50, blue: 0.52)

    static func assetName(for provider: UsageProviderKind) -> String {
        switch provider {
        case .claude: "ProviderClaude"
        case .codex: "ProviderOpenAI"
        case .grok: "ProviderX"
        }
    }

    static func color(for provider: UsageProviderKind, colorScheme: ColorScheme) -> Color {
        switch provider {
        case .claude: self.claude
        case .codex: self.gpt
        case .grok: colorScheme == .dark ? .white : .black
        }
    }

    static func meterColor(for provider: UsageProviderKind) -> Color {
        switch provider {
        case .claude: self.claude
        case .codex: self.gpt
        case .grok: self.grokMeter
        }
    }
}

struct ProviderBrandIcon: View {
    let provider: UsageProviderKind
    var size: CGFloat = 16

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(ProviderBrand.assetName(for: self.provider))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ProviderBrand.color(for: self.provider, colorScheme: self.colorScheme))
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(true)
    }
}
