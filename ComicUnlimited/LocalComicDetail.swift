import SwiftUI

// Ficha de un archivo tuyo que todavía no tiene ficha de Comic Vine.
// (Los que sí tienen, abren directamente su ficha de Comic Vine, que también tiene "Leer".)

struct LocalComicDetailView: View {
    let comicID: String
    @Environment(LibraryActions.self) private var actions: LibraryActions?
    @Environment(\.dismiss) private var dismiss
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        ScrollView {
            if let comic = library.item(comicID) {
                content(comic)
            } else {
                Text("Este cómic ya no está en tu Biblioteca.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.paper)
        .navigationTitle(library.item(comicID)?.displayTitle ?? "Cómic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: library.item(comicID)?.cvIssueID) { _, issueID in
            // Si le elegiste la ficha, volvemos atrás: tocarlo de nuevo abre la ficha de Comic Vine.
            if issueID != nil { dismiss() }
        }
    }

    @ViewBuilder private func content(_ comic: LocalComic) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                LocalCover(comic: comic).frame(width: 130)
                VStack(alignment: .leading, spacing: 6) {
                    Text(comic.displayTitle)
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                    Text("\(comic.pageCount) \(comic.pageCount == 1 ? "página" : "páginas")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                    Group {
                        if comic.isFinished {
                            Text("Leído ✓")
                        } else if let page = comic.lastPage {
                            Text("Vas por la página \(page + 1)")
                        } else {
                            Text("Sin empezar")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                }
            }
            .padding(.top, 10)

            Button {
                actions?.onRead(comic)
            } label: {
                Label(comic.isFinished ? "Volver a leer" : comic.hasStarted ? "Seguir leyendo" : "Leer", systemImage: "book.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .foregroundStyle(Theme.paper)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            TPBContentsButton(comic: comic)
                .padding(.top, 14)

            VStack(spacing: 0) {
                actionRow("Buscar su ficha en Comic Vine", icon: "sparkle.magnifyingglass") {
                    Task {
                        let found = await library.autoLink(comic.id)
                        if !found { actions?.linking = comic }
                    }
                }
                actionRow("Elegir ficha de Comic Vine", icon: "list.bullet.rectangle") { actions?.linking = comic }
                actionRow("Cambiar nombre", icon: "pencil") { actions?.renaming = comic }
                actionRow("Borrar de la Biblioteca", icon: "trash", destructive: true) { actions?.toDelete = comic }
            }
            .padding(.top, 14)

            Text("Archivo: \(comic.title)")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 16)
            Text("Sin ficha de Comic Vine: con la ficha vas a ver de qué se trata, sus autores y en qué arcos está.")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
    }

    private func actionRow(_ title: String, icon: String, destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Theme.magenta : Theme.ink)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(actions == nil)
    }
}
