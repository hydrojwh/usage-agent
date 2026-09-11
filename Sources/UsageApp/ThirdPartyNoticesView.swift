import Foundation
import SwiftUI

enum ThirdPartyNoticesDocument {
#if USAGE_APP_STORE
    static let resourceName = "THIRD_PARTY_NOTICES_APP_STORE"
#else
    static let resourceName = "THIRD_PARTY_NOTICES"
#endif
    static let resourceExtension = "md"

    static func load(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(
            forResource: self.resourceName,
            withExtension: self.resourceExtension),
            let text = try? String(contentsOf: url, encoding: .utf8),
            !text.isEmpty
        else {
            return "Third-party notices are unavailable in this build."
        }
        return text
    }
}

struct ThirdPartyNoticesButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            self.isPresented = true
        } label: {
            Label("Third-Party Notices…", systemImage: "doc.text")
        }
        .buttonStyle(.plain)
        .help("View bundled third-party licenses and notices")
        .accessibilityLabel("View third-party licenses and notices")
        .popover(isPresented: self.$isPresented, arrowEdge: .trailing) {
            ThirdPartyNoticesView()
        }
    }
}

private struct ThirdPartyNoticesView: View {
    private let noticeText = ThirdPartyNoticesDocument.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Third-Party Notices")
                    .font(AppFont.headline)
                Spacer()
            }

            Text("These components and provider marks remain subject to their own terms.")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                Text(self.noticeText)
                    .font(AppFont.captionMonospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 440, height: 360)
    }
}
