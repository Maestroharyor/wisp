import SwiftUI

extension View {
    /// Fades the bottom of a scrolling list into the shelf, so rows that run past the edge read
    /// as more to scroll to rather than cut off. `room` is space after the last row, so it can
    /// scroll clear of the fade.
    func scrollFade(room: CGFloat = 14) -> some View {
        contentMargins(.bottom, room, for: .scrollContent)
            .mask(
                LinearGradient(
                    stops: [.init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
    }
}
