import RhythmCore
import SwiftUI

/// A failure to open a Quicklink, shown as an actionable alert.
struct QuicklinkOpenFailure: Identifiable {
    let id = UUID()
    let linkID: UUID
    let title: String
    let message: String
}

/// Opens Quicklinks through the public SwiftUI `openURL` action. Rhythm never assumes a private
/// app scheme exists; if iOS can't open a destination the user gets an error and the link stays
/// editable.
enum QuicklinkOpener {
    @MainActor
    static func open(_ link: Quicklink, with openURL: OpenURLAction, onFailure: @escaping @MainActor (QuicklinkOpenFailure) -> Void) {
        switch QuicklinkURLValidator.validate(link.urlString) {
        case .failure(let error):
            onFailure(QuicklinkOpenFailure(linkID: link.id, title: link.title, message: error.message))
        case .success(let validated):
            let linkID = link.id
            let title = link.title
            let kind = validated.kind
            openURL(validated.url) { accepted in
                guard !accepted else { return }
                let message = switch kind {
                case .website: "iOS couldn’t open this website. Check the address and try again."
                case .app: "No app on this iPhone can open this link. The app may not be installed, or it may not support this link."
                case .shortcut: "The Shortcuts app couldn’t open this shortcut. Check that it exists and that its name matches."
                }
                Task { @MainActor in
                    onFailure(QuicklinkOpenFailure(linkID: linkID, title: title, message: message))
                }
            }
        }
    }
}

extension View {
    /// Presents an open-failure alert with an option to edit the link.
    func quicklinkFailureAlert(_ failure: Binding<QuicklinkOpenFailure?>, onEdit: @escaping (UUID) -> Void) -> some View {
        alert(
            "Couldn’t Open “\(failure.wrappedValue?.title ?? "Link")”",
            isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } }),
            presenting: failure.wrappedValue
        ) { value in
            Button("Edit Link") { onEdit(value.linkID) }
            Button("OK", role: .cancel) {}
        } message: { value in
            Text(value.message)
        }
    }
}
