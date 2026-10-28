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
    case arc(id: Int, name: String)
    case publisher(String)
    /// Biblioteca → Fuentes, y una fuente en particular (por su link).
    case sources
    case source(String)
    /// "Descargar" desde una ficha: buscar ese cómic en tus fuentes.
    case findInSources(series: String, number: String?)
    /// Revisar las fichas de Comic Vine que eligió la app sola.
    case reviewLinks
    /// Ficha de un archivo tuyo que no tiene ficha de Comic Vine.
    case localComic(String)
    /// Ficha de un número de Metron (Próximos).
    case metronIssue(Int)
    /// Perfil → Historial de lectura y Ajustes por serie.
    case history
    case readingProfiles
    /// Perfil → Configuración: cuentas de Metron y Comic Vine, y Revisar conexión.
    case accounts
    case diagnostics
    /// "Ver en la compu": leer tus cómics en el navegador de la compu por Wi-Fi.
    case webShare
    /// Una de tus listas (Biblioteca → Listas).
    case customList(Int)
}

/// Acciones del menú de cada cómic. Las pantallas de abajo (carpetas) las comparten.
@MainActor
@Observable
final class LibraryActions {
    var onRead: (LocalComic) -> Void
    var linking: LocalComic?
    var toDelete: LocalComic?
    var renaming: LocalComic?
    /// TPB al que le estás eligiendo qué números trae.
    var editingContents: LocalComic?
    /// Cómic que estás agregando a una de tus listas.
    var addingToList: ListItem?

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

    /// Fecha para ordenar por publicación (sin fecha, al final).
    static func byDate(_ a: LocalComic, _ b: LocalComic) -> Bool {
        switch (a.publicationDate, b.publicationDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return byNumber(a, b)
        }
    }

    struct ArcGroup: Identifiable {
        let arc: ArcRef
        let comics: [LocalComic]
        var id: Int { arc.id }
    }

    /// Una carpeta por arco (A–Z), con tus cómics ordenados por fecha de publicación.
    static func arcs(_ items: [LocalComic]) -> [ArcGroup] {
        var byArc: [ArcRef: [LocalComic]] = [:]
        for comic in items {
            for arc in comic.cvArcs ?? [] { byArc[arc, default: []].append(comic) }
        }
        return byArc.map { ArcGroup(arc: $0.key, comics: $0.value.sorted(by: byDate)) }
            .sorted { $0.arc.name.localizedStandardCompare($1.arc.name) == .orderedAscending }
    }

    static let noPublisher = "Sin editorial"

    static func publisherName(_ comic: LocalComic) -> String {
        guard let p = comic.cvPublisher, !p.isEmpty else { return noPublisher }
        return p
    }

    /// Una carpeta por editorial (A–Z; "Sin editorial" al final).
    static func publishers(_ items: [LocalComic]) -> [(name: String, comics: [LocalComic])] {
        Dictionary(grouping: items, by: publisherName)
            .map { (name: $0.key, comics: $0.value.sorted(by: byDate)) }
            .sorted { a, b in
                if a.name == noPublisher { return false }
                if b.name == noPublisher { return true }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
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

/// Un cómic: tocarlo abre su ficha (ahí está "Leer"); mantenerlo apretado muestra el menú.
struct LocalComicTile: View {
    let comic: LocalComic
    @Environment(LibraryActions.self) private var actions
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        Group {
            if let issueID = comic.cvIssueID {
                NavigationLink(value: CVRoute.issue(id: issueID, title: comic.displayTitle)) {
                    LocalComicCard(comic: comic, matching: library.matching.contains(comic.id))
                }
            } else {
                NavigationLink(value: LibraryRoute.localComic(comic.id)) {
                    LocalComicCard(comic: comic, matching: library.matching.contains(comic.id))
                }
            }
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
            Button { actions.addingToList = ListItem.from(comic) } label: {
                Label("Agregar a una lista", systemImage: "text.badge.plus")
            }
            Button { actions.editingContents = comic } label: {
                Label(comic.isCollection ? "Números del TPB" : "¿Es un TPB? Qué números trae", systemImage: "books.vertical")
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
    @AppStorage(AppSettings.showMissingKey) private var showMissing = true

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

                if let seriesID, showMissing {
                    SeriesIssuesGrid(seriesID: seriesID, mine: mine)
                } else {
                    SectionTitle("Los que tenés")
                    if mine.isEmpty {
                        Text("No tenés archivos de esta serie.").font(.subheadline).foregroundStyle(Theme.ink2)
                    } else {
                        ComicGrid(comics: mine)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(title)
        // Si leés un cómic desde acá, "Siguiente número" sigue esta serie.
        .onAppear {
            if let seriesID { BrowsingContext.current = ReadContext(kind: .series, id: seriesID, name: title) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if let seriesID, detail == nil, !ComicVineKey.current.isEmpty {
                detail = try? await ComicVineKey.client.series(id: seriesID)
            }
        }
    }
}

/// Ajustes de la app (se cambian en Perfil → Configuración).
enum AppSettings {
    static let autoLinkKey = "settings.autoLink"
    /// Buscar sola la ficha de Comic Vine de cada archivo que importás o descargás. Prendido salvo que lo apagues.
    static var autoLink: Bool {
        UserDefaults.standard.object(forKey: autoLinkKey) as? Bool ?? true
    }

    static let showMissingKey = "settings.showMissing"
    /// Mostrar en gris los números que no tenés (en series y arcos). Prendido salvo que lo apagues.
    static var showMissing: Bool {
        UserDefaults.standard.object(forKey: showMissingKey) as? Bool ?? true
    }
}

/// Todos los números de la serie en una grilla, en orden: los tuyos a color y los que te faltan en gris.
private struct SeriesIssuesGrid: View {
    let seriesID: Int
    let mine: [LocalComic]

    @State private var loaded: [CVIssueSummary] = []
    @State private var available = 0
    @State private var loading = false
    @State private var errorText: String?

    private enum Slot: Identifiable {
        case owned(LocalComic)
        case missing(CVIssueSummary)
        /// No lo tenés suelto, pero sí dentro de un TPB.
        case collected(CVIssueSummary, LocalComic)

        var id: String {
            switch self {
            case .owned(let c): return "mio-\(c.id)"
            case .missing(let i): return "falta-\(i.id)"
            case .collected(let i, _): return "tpb-\(i.id)"
            }
        }

        var sortKey: Double {
            switch self {
            case .owned(let c): return c.numberForSorting
            case .missing(let i), .collected(let i, _): return Double(i.issueNumber ?? "") ?? .greatestFiniteMagnitude
            }
        }
    }

    private var slots: [Slot] {
        let owned = Set(mine.compactMap(\.cvIssueID))
        let collected = LocalLibrary.shared.collectedIssues
        let missing = loaded.filter { !owned.contains($0.id) }.map { issue in
            collected[issue.id].map { Slot.collected(issue, $0) } ?? Slot.missing(issue)
        }
        return (mine.map(Slot.owned) + missing).sorted { $0.sortKey < $1.sortKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Números")
            if ComicVineKey.current.isEmpty {
                Text("Cargá tu clave de Comic Vine en Próximos para ver también los números que te faltan.")
                    .font(.subheadline).foregroundStyle(Theme.ink2).padding(.bottom, 12)
            } else if let errorText {
                Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2).padding(.bottom, 12)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                      alignment: .leading, spacing: 18) {
                ForEach(slots) { slot in
                    switch slot {
                    case .owned(let comic):
                        LocalComicTile(comic: comic)
                    case .missing(let issue):
                        NavigationLink(value: CVRoute.issue(id: issue.id,
                                                            title: issue.issueNumber.map { "#\($0)" } ?? "Número")) {
                            MissingIssueCard(issue: issue)
                        }
                        .buttonStyle(.plain)
                    case .collected(let issue, let tpb):
                        CollectedIssueCard(title: issue.issueNumber.map { "#\($0)" } ?? "Número",
                                           subtitle: issue.name, cover: issue.image?.small, tpb: tpb)
                    }
                }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if loaded.count < available {
                Button {
                    Task { await load() }
                } label: {
                    Text("Ver más números de la serie")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }

            Text("Los grises son los que no tenés: tocá uno para ver su ficha y marcarlo \"Quiero leer\". Podés ocultarlos en Perfil → Configuración.")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 12)
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

/// Un número que no tenés: portada en gris.
private struct MissingIssueCard: View {
    let issue: CVIssueSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RemoteCover(url: issue.image?.small)
                .grayscale(1)
                .opacity(0.45)
            Text(issue.issueNumber.map { "#\($0)" } ?? "Sin número")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)
            if let name = issue.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                Text(name).font(.caption).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            Label("Descargar", systemImage: "arrow.down.circle").font(.caption2.weight(.semibold)).foregroundStyle(Theme.magenta)
        }
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
