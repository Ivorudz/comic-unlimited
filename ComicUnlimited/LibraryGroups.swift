import SwiftUI
import UIKit
import Observation

// Grupos de la Biblioteca: carpetas por serie y por estado de lectura,
// más las piezas que comparten (la tarjeta de cada cómic y su menú).

/// A qué carpeta ir dentro de la Biblioteca.
enum LibraryRoute: Hashable {
    /// Una serie de Comic Vine. nil = los archivos sin ficha de Comic Vine.
    case series(Int?)
    case status(ReadState)
}

/// Acciones del menú de cada cómic. Las pantallas de abajo (carpetas) las comparten.
@MainActor
@Observable
final class LibraryActions {
    let onRead: (LocalComic) -> Void
    var linking: LocalComic?
    var toDelete: LocalComic?
    var renaming: LocalComic?

    init(onRead: @escaping (LocalComic) -> Void) { self.onRead = onRead }
}

// MARK: - Agrupar

struct SeriesGroup: Identifiable {
    let seriesID: Int?
    let name: String
    let comics: [LocalComic]
    var id: String { seriesID.map(String.init) ?? "sin-ficha" }
}

enum LibraryGrouping {
    static func byNumber(_ a: LocalComic, _ b: LocalComic) -> Bool {
        if a.numberForSorting != b.numberForSorting { return a.numberForSorting < b.numberForSorting }
        return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
    }

    static func seriesTitle(_ comic: LocalComic) -> String {
        let name = comic.seriesName ?? comic.displayTitle
        if let year = comic.cvSeriesYear, !year.isEmpty { return "\(name) (\(year))" }
        return name
    }

    /// Una carpeta por serie (A–Z) y, al final, la de los que no tienen ficha.
    static func series(_ items: [LocalComic]) -> [SeriesGroup] {
        let linked = Dictionary(grouping: items.filter { $0.cvSeriesID != nil }, by: { $0.cvSeriesID! })
        var groups = linked.map { entry -> SeriesGroup in
            let sorted = entry.value.sorted(by: byNumber)
            return SeriesGroup(seriesID: entry.key, name: seriesTitle(sorted[0]), comics: sorted)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let unlinked = items.filter { $0.cvSeriesID == nil }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        if !unlinked.isEmpty {
            groups.append(SeriesGroup(seriesID: nil, name: "Sin ficha de Comic Vine", comics: unlinked))
        }
        return groups
    }

    static func comics(in state: ReadState, _ items: [LocalComic]) -> [LocalComic] {
        items.filter { $0.readState == state }
            .sorted { ($0.lastOpened ?? $0.added) > ($1.lastOpened ?? $1.added) }
    }
}

// MARK: - Piezas compartidas

/// Grilla de cómics de 3 columnas.
struct ComicGrid: View {
    let comics: [LocalComic]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                  alignment: .leading, spacing: 18) {
            ForEach(comics) { comic in
                LocalComicTile(comic: comic)
            }
        }
    }
}

/// Un cómic: tocarlo lo abre; mantenerlo apretado muestra el menú.
struct LocalComicTile: View {
    let comic: LocalComic
    @Environment(LibraryActions.self) private var actions
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        Button { actions.onRead(comic) } label: {
            LocalComicCard(comic: comic, matching: library.matching.contains(comic.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { actions.onRead(comic) } label: {
                Label("Leer", systemImage: "book")
            }
            if let issueID = comic.cvIssueID {
                NavigationLink(value: CVRoute.issue(id: issueID, title: comic.displayTitle)) {
                    Label("Ver ficha en Comic Vine", systemImage: "info.circle")
                }
            } else {
                Button {
                    Task {
                        let found = await library.autoLink(comic.id)
                        if !found { actions.linking = comic }
                    }
                } label: {
                    Label("Buscar su ficha en Comic Vine", systemImage: "sparkle.magnifyingglass")
                }
            }
            Button { actions.linking = comic } label: {
                Label("Elegir ficha de Comic Vine", systemImage: "list.bullet.rectangle")
            }
            Button { actions.renaming = comic } label: {
                Label("Cambiar nombre", systemImage: "pencil")
            }
            Button(role: .destructive) {
                actions.toDelete = comic
            } label: {
                Label("Borrar de la Biblioteca", systemImage: "trash")
            }
        }
    }
}

/// Portada (primera página) y datos de un cómic importado.
struct LocalComicCard: View {
    let comic: LocalComic
    let matching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LocalCover(comic: comic)

            Text(comic.displayTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            if let name = comic.cvIssueName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Group {
                if comic.isFinished {
                    Text("Leído ✓")
                } else if let page = comic.lastPage {
                    Text("Página \(page + 1) de \(comic.pageCount)")
                } else {
                    Text("\(comic.pageCount) \(comic.pageCount == 1 ? "página" : "páginas")")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.ink2)
            if matching {
                Text("Buscando ficha…").font(.caption2).foregroundStyle(Theme.magenta)
            } else if comic.cvIssueID != nil {
                Label("Comic Vine", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.magenta)
            }
        }
    }
}

/// La portada guardada de un archivo (su primera página).
struct LocalCover: View {
    let comic: LocalComic
    @State private var cover: UIImage?

    var body: some View {
        ZStack {
            Theme.chip
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                Image(systemName: "doc.richtext").foregroundStyle(Theme.ink2)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .task(id: comic.id) {
            cover = UIImage(contentsOfFile: LocalLibrary.shared.coverURL(comic).path)
        }
    }
}

/// Tarjeta de carpeta: portada con "pila" de hojas atrás, nombre y cantidad.
struct FolderCard: View {
    let title: String
    let subtitle: String
    let cover: LocalComic?
    var icon: String = "folder"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Theme.line).offset(x: 6, y: -6)
                RoundedRectangle(cornerRadius: 4).fill(Theme.chip).offset(x: 3, y: -3)
                if let cover {
                    LocalCover(comic: cover)
                } else {
                    ZStack {
                        Theme.card
                        Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.magenta)
                    }
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
        }
    }
}

/// Grilla de carpetas de 3 columnas.
struct FolderGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                  alignment: .leading, spacing: 20, content: content)
    }
}

func countText(_ n: Int) -> String { "\(n) \(n == 1 ? "número" : "números")" }

// MARK: - Carpeta de una serie

struct SeriesFolderView: View {
    let seriesID: Int?
    private var library: LocalLibrary { LocalLibrary.shared }

    @State private var detail: CVVolumeDetail?

    private var comics: [LocalComic] {
        let list = library.items.filter { $0.cvSeriesID == seriesID }
        if seriesID == nil {
            return list.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
        return list.sorted(by: LibraryGrouping.byNumber)
    }

    var body: some View {
        let mine = comics
        let title = seriesID == nil ? "Sin ficha de Comic Vine"
            : (mine.first.map(LibraryGrouping.seriesTitle) ?? detail?.name ?? "Serie")
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 26, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)

                if let seriesID {
                    if let total = detail?.countOfIssues, total > 0 {
                        let have = Set(mine.compactMap(\.cvIssueID)).count
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tenés \(have) de \(total)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            ProgressBar(value: Double(have) / Double(total))
                        }
                        .padding(.top, 10)
                    }
                    if let publisher = detail?.publisher?.name {
                        Text(publisher).font(.subheadline).foregroundStyle(Theme.ink2).padding(.top, 6)
                    }
                    NavigationLink(value: CVRoute.series(id: seriesID, name: title)) {
                        Label("Ver la serie en Comic Vine", systemImage: "info.circle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.magenta)
                    }
                    .padding(.top, 10)
                } else {
                    Text("Mantené apretado un cómic y elegí \"Buscar su ficha en Comic Vine\" para ordenarlo en su serie.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                }

                SectionTitle("Los que tenés")
                if mine.isEmpty {
                    Text("No tenés archivos de esta serie.").font(.subheadline).foregroundStyle(Theme.ink2)
                } else {
                    ComicGrid(comics: mine)
                }

                if let seriesID {
                    MissingIssuesSection(seriesID: seriesID, owned: Set(mine.compactMap(\.cvIssueID)),
                                         total: detail?.countOfIssues)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if let seriesID, detail == nil, !ComicVineKey.current.isEmpty {
                detail = try? await ComicVineKey.client.series(id: seriesID)
            }
        }
    }
}

/// "Te faltan": los números de la serie (según Comic Vine) que no están en tu Biblioteca.
private struct MissingIssuesSection: View {
    let seriesID: Int
    let owned: Set<Int>
    let total: Int?

    @State private var loaded: [CVIssueSummary] = []
    @State private var available = 0
    @State private var loading = false
    @State private var errorText: String?

    private var missing: [CVIssueSummary] { loaded.filter { !owned.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let total {
                SectionTitle("Te faltan (\(max(total - owned.count, 0)))")
            } else {
                SectionTitle("Te faltan")
            }

            if ComicVineKey.current.isEmpty {
                Text("Cargá tu clave de Comic Vine en Próximos para ver qué números te faltan.")
                    .font(.subheadline).foregroundStyle(Theme.ink2)
            } else if let errorText {
                Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2)
            } else if loaded.isEmpty && loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if missing.isEmpty && loaded.count >= available {
                Text("¡Tenés la serie completa! 🎉").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
            } else {
                ForEach(missing) { issue in
                    NavigationLink(value: CVRoute.issue(id: issue.id,
                                                        title: issue.issueNumber.map { "#\($0)" } ?? "Número")) {
                        HStack(spacing: 12) {
                            RemoteCover(url: issue.image?.small)
                                .frame(width: 40)
                                .opacity(0.55)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.issueNumber.map { "#\($0)" } ?? "Sin número")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                if let name = issue.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                                    Text(name).font(.footnote).foregroundStyle(Theme.ink2).lineLimit(1)
                                }
                                if let date = CVText.monthYear(issue.coverDate) {
                                    Text(date).font(.caption).foregroundStyle(Theme.ink2)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if loaded.count < available {
                    Button {
                        Task { await load() }
                    } label: {
                        Text(loading ? "Cargando…" : "Ver más números de la serie")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                    .padding(.top, 12)
                }
                Text("Tocá uno para ver su ficha y marcarlo \"Quiero leer\".")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 8)
            }
        }
        .task {
            if loaded.isEmpty && !ComicVineKey.current.isEmpty { await load() }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        do {
            let page = try await ComicVineKey.client.issues(ofSeries: seriesID, offset: loaded.count, ascending: true)
            let known = Set(loaded.map(\.id))
            loaded += page.items.filter { !known.contains($0.id) }
            available = page.items.isEmpty ? loaded.count : page.total
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }
}

// MARK: - Carpeta de un estado de lectura

struct StatusFolderView: View {
    let state: ReadState
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let comics = LibraryGrouping.comics(in: state, library.items)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.label)
                    .font(.system(size: 26, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                if comics.isEmpty {
                    Text("No hay cómics acá.").font(.subheadline).foregroundStyle(Theme.ink2)
                } else {
                    ComicGrid(comics: comics)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(state.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
