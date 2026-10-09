import RhythmCore
@preconcurrency import SwiftData
import SwiftUI

/// A small row of favourite Quicklinks on Today. Hidden when there are no favourites.
struct FavoriteQuicklinksView: View {
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Quicklink> { $0.isFavorite }, sort: \Quicklink.sortOrder)
    private var favorites: [Quicklink]
    @State private var failure: QuicklinkOpenFailure?
    @State private var editing: Quicklink?

    var body: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: RhythmSpacing.sm) {
                Text("Quicklinks")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(spacing: RhythmSpacing.md) {
                        ForEach(favorites) { link in
                            Button {
                                QuicklinkOpener.open(link, with: openURL) { failure = $0 }
                            } label: {
                                Label(link.title, systemImage: link.resolvedSymbolName)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, RhythmSpacing.md)
                                    .frame(minHeight: RhythmLayout.minimumTouchTarget)
                                    .background(RhythmSurface.content, in: RoundedRectangle(cornerRadius: RhythmRadius.row, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens \(link.kind.displayName.lowercased())")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .quicklinkFailureAlert($failure) { id in
                editing = favorites.first { $0.id == id }
            }
            .sheet(item: $editing) { link in
                QuicklinkEditorView(link: link)
            }
        }
    }
}
