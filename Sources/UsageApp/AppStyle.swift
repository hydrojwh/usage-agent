import SwiftUI

/// Usage에 고정된 명시적 SF Pro 시스템 폰트 계층.
/// SwiftUI의 semantic 기본값 변화와 무관하게 메뉴바 제품군의 밀도를 일정하게 유지한다.
enum AppFont {
    static let title3 = Font.system(size: 16)
    static let title3Semibold = Font.system(size: 16, weight: .semibold)
    static let headline = Font.system(size: 14, weight: .semibold)
    static let subheadlineSemibold = Font.system(size: 12, weight: .semibold)
    static let callout = Font.system(size: 13)
    static let calloutMedium = Font.system(size: 13, weight: .medium)
    static let calloutMonospaced = Font.system(size: 13, design: .monospaced)
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let captionSemibold = Font.system(size: 11, weight: .semibold)
    static let captionMonospaced = Font.system(size: 11, design: .monospaced)
    static let captionMonospacedMedium = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// Usage macOS의 패딩 밀도를 유지하면서 실제 카드 높이에 맞춰
/// 팝오버를 줄인다. 예외적으로 긴 내용만 제한 높이 안에서 스크롤한다.
enum AppLayout {
    static let popoverWidth: CGFloat = 440
    static let maximumCardContentHeight: CGFloat = 390
    /// Grouped anchor panels live inside the card viewport, so each visible
    /// one raises the cap; without this, provider cards below two anchors fall
    /// under the fold and look missing.
    static let anchorPanelHeightAllowance: CGFloat = 110

    static func maximumContentHeight(anchorPanelCount: Int) -> CGFloat {
        self.maximumCardContentHeight
            + self.anchorPanelHeightAllowance * CGFloat(max(0, anchorPanelCount))
    }
    static let headerHorizontalPadding: CGFloat = 14
    static let headerVerticalPadding: CGFloat = 8
    static let contentHorizontalPadding: CGFloat = 12
    static let contentVerticalPadding: CGFloat = 10
    static let contentSpacing: CGFloat = 10
    static let footerHorizontalPadding: CGFloat = 14
    static let footerVerticalPadding: CGFloat = 8
    static let cardPadding: CGFloat = 8
    static let cardCornerRadius: CGFloat = 6

    static func estimatedContentHeight(providerCount: Int) -> CGFloat {
        switch providerCount {
        case ...1: 130
        case 2: 230
        default: 330
        }
    }
}
