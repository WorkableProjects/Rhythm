import RhythmCore
import SwiftData
import SwiftUI

/// A launchpad for existing apps, websites, and Shortcuts. Rhythm only asks iOS to open the
/// destination; it never replaces the destination app.
struct QuicklinksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Quicklink.sortOrder), SortDescriptor(\Quicklink.createdAt)])
    private var links: [Quicklink]

    @State private var editing: Quicklink?
    @State private var isAdding = false
    @State private var failure: QuicklinkOpenFailure?

    var body: some View {
        NavigationStack {
            Group {
                if links.isEmpty {
                    ContentUnavailableView {
                        Label("No Quicklinks", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Add websites, app links, or Shortcuts you open during the school day.")
                    } actions: {
                        Button("Add Quicklink") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("emptyAddQuicklinkButton")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Quicklinks")
            .toolbar {
                if !links.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Quicklink", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addQuicklinkButton")
                }
            }
            .sheet(isPresented: $isAdding) {
                QuicklinkEditorView(link: nil)
            }
            .sheet(item: $editing) { link in
                QuicklinkEditorView(link: link)
            }
            .quicklinkFailureAlert($failure) { id in
                editing = links.first { $0.id == id }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(links) { link in
                    Button {
                        QuicklinkOpener.open(link, with: openURL) { failure = $0 }
                    } label: {
                        QuicklinkRow(link: link)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quicklinkRow-\(link.title)")
                    .accessibilityHint("Opens \(link.kind.displayName.lowercased())")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(link) } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = link } label: { Label("Edit", systemImage: "pencil") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { toggleFavorite(link) } label: {
                            Label(link.isFavorite ? "Unfavorite" : "Favorite", systemImage: link.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button { editing = link } label: { Label("Edit", systemImage: "pencil") }
                        Button { toggleFavorite(link) } label: {
                            Label(link.isFavorite ? "Remove from Today" : "Show on Today", systemImage: link.isFavorite ? "star.slash" : "star")
                        }
                        Button { model.commit { model.repository.duplicateQuicklink(link) } } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) { delete(link) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .accessibilityActions {
                        Button("Edit") { editing = link }
                        Button(link.isFavorite ? "Remove from Today" : "Show on Today") { toggleFavorite(link) }
                        Button("Duplicate") { model.commit { model.repository.duplicateQuicklink(link) } }
                        Button("Delete") { delete(link) }
                    }
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    let targets = offsets.map { links[$0] }
                    model.commit { targets.forEach { model.repository.context.delete($0) } }
                }
            } footer: {
                Text("Starred links also appear on Today. Opening an app link or Shortcut depends on what’s installed on this iPhone.")
            }
        }
    }

    private func toggleFavorite(_ link: Quicklink) {
        model.commit { link.isFavorite.toggle() }
    }

    private func delete(_ link: Quicklink) {
        model.commit { model.repository.context.delete(link) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = links
        reordered.move(fromOffsets: source, toOffset: destination)
        model.commit { model.repository.reorderQuicklinks(reordered) }
    }
}

private struct QuicklinkRow: View {
    let link: Quicklink

    var body: some View {
        HStack(spacing: RhythmSpacing.md) {
            PeriodSymbol(symbolName: link.resolvedSymbolName, tint: .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                Text(link.note?.isEmpty == false ? link.note! : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if link.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
            Image(systemName: "arrow.up.forward")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: RhythmLayout.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        [link.kind.displayName, link.category?.displayName].compactMap { $0 }.joined(separator: " · ")
    }
}
