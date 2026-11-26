import SwiftUI

/// A part that more than one of the notch's forms shows: the album art in the music pill and on
/// the shelf, an agent's icon in its pill and on its approval card.
enum MorphPart: Hashable {
    case artwork
    case agent(session: String)
}

extension EnvironmentValues {
    /// Set by the notch only, and not under Reduce Motion. Windows and Settings leave it nil,
    /// so the same views there stay where they are.
    @Entry var morphSpace: Namespace.ID?
}

/// Tags a part with its key, so when the notch changes form it travels from its place in the
/// old form to its place in the new one on the shell's spring, rather than fading out of one
/// and into the other. Only one view per key may show in any one form.
private struct MorphMatch: ViewModifier {
    let part: MorphPart
    @Environment(\.morphSpace) private var space

    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: part, in: space)
        } else {
            content
        }
    }
}

extension View {
    func morphMatch(_ part: MorphPart) -> some View { modifier(MorphMatch(part: part)) }
}
