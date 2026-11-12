import SwiftUI

/// A small colour sample with a hairline so white and transparent colours stay visible.
public struct SwatchDot: View {
    let color: Color
    var size: CGFloat = 18
    public init(color: Color, size: CGFloat = 18) {
        self.color = color
        self.size = size
    }
    public var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .background(CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.15)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
