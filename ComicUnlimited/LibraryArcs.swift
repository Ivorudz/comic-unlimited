import SwiftUI

// Carpetas por arco argumental y por editorial en la Biblioteca.
// En un arco se ven todos sus números (según Comic Vine) por fecha de publicación:
// los tuyos a color y los que te faltan en gris.

// MARK: - Carpeta de un arco

struct ArcFolderView: View {
    let arcID: Int
    let name: String
    private var library: LocalLibrary { LocalLibrary.shared }
    @AppStorage(AppSettings.showMissingKey) private var showMissing = true

    @State private var arc: CVArcDetail?
    @State private var others: [CVIssueWithSeries] = []
    @State private var loading = false
    @State private var errorText: String?

    /// Tus archivos de este arco, por fecha de publicación.
    private var mine: [LocalComic] {
        library.items.filter { ($0.cvArcs ?? []).contains { $0.id == arcID } }
            .sorted(by: LibraryGrouping.byDate)
    }

    private enum Slot: Identifiable {
        case owned(LocalComic)
        case missing(CVIssueWithSeries)
        /// Número del arco que Comic Vine no pudo detallar (solo sabemos número y nombre).
        case bare(CVArcIssue)

        var id: String {
            switch self {
            case .owned(let c): return "mio-\(c.id)"
            case .missing(let i): return "falta-\(i.id)"
            case .bare(let i): return "falta-\(i.id)"
            }
        }

        /// Fecha para ordenar ("9999" = sin fecha, al final).
        var date: String {
            switch self {
            case .owned(let c): return c.publicationDate ?? "9999"
            case .missing(let i): return i.coverDate ?? i.storeDate ?? "9999"
            case .bare: return "9999"
            }
        }
    }

    private func slots(_ mine: [LocalComic]) -> [Slot] {
        let owned = Set(mine.compactMap(\.cvIssueID))
        var list = mine.map(Slot.owned)
        if showMissing, let arcIssues = arc?.issues {
            let detailed = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for issue in arcIssues where !owned.contains(issue.id) {
                if let full = detailed[issue.id] {
                    list.append(.missing(full))
                } else {
                    list.append(.bare(issue))
                }
            }
        }
        return list.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }

    var body: some View {
        let mine = self.mine
        let total = arc?.issues?.count
        let have = Set(mine.compactMap(\.cvIssueID)).count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    if let image = arc?.image?.medium {
                        RemoteCover(url: image).frame(width: 110)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(arc?.name ?? name)
                            .font(.system(size: 24, weight: .black).width(.expanded))
                            .foregroundStyle(Theme.ink)
                        Text(CVText.join(["Arco argumental", arc?.publisher?.name]))
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.top, 8)

                if let total, total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tenés \(min(have, total)) de \(total)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        ProgressBar(value: Double(min(have, total)) / Double(total))
                    }
                    .padding(.top, 10)
                }

                if let text = CVText.plain(arc?.description) ?? CVText.plain(arc?.deck) {
                    ComicVineText(text: text)
                        .padding(.top, 12)
                }

                SectionTitle("Números, por fecha de publicación")
                if loading && arc == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if let errorText {
                    Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2).padding(.bottom, 12)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                          alignment: .leading, spacing: 18) {
                    ForEach(slots(mine)) { slot in
                        switch slot {
                        case .owned(let comic):
                            LocalComicTile(comic: comic)
                        case .missing(let issue):
                            NavigationLink(value: CVRoute.issue(id: issue.id, title: Self.title(issue))) {
                                ArcMissingCard(title: Self.title(issue), subtitle: issue.name,
                                               date: CVText.monthYear(issue.coverDate), cover: issue.image?.small)
                            }
                            .buttonStyle(.plain)
                        case .bare(let issue):
                            NavigationLink(value: CVRoute.issue(id: issue.id,
                                                                title: issue.issueNumber.map { "#\($0)" } ?? "Número")) {
                                ArcMissingCard(title: issue.issueNumber.map { "#\($0)" } ?? "Número",
                                               subtitle: issue.name, date: nil, cover: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(showMissing
                     ? "Los grises son los que no tenés: tocá uno para ver su ficha y marcarlo \"Quiero leer\". Podés ocultarlos en Perfil → Configuración."
                     : "Los números que no tenés están ocultos (Perfil → Configuración).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 12)

                if let link = arc?.siteDetailUrl.flatMap({ URL(string: $0) }) {
                    Link("Ver este arco en Comic Vine", destination: link)
                        .font(.footnote)
                        .foregroundStyle(Theme.magenta)
                        .padding(.top, 16)
                }
                Text("Los arcos están tan completos como los tenga cargados Comic Vine.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(arc?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if arc == nil { await load() } }
    }

    private static func title(_ issue: CVIssueWithSeries) -> String {
        CVText.issueTitle(series: issue.volume?.name ?? "Número", number: issue.issueNumber)
    }

    private func load() async {
        guard !ComicVineKey.current.isEmpty else {
            errorText = "Cargá tu clave de Comic Vine en Próximos para ver todos los números del arco."
            return
        }
        loading = true
        do {
            let detail = try await ComicVineKey.client.storyArc(id: arcID)
            arc = detail
            // Detalles (serie, portada, fecha) de los números que no tenés.
            let owned = Set(mine.compactMap(\.cvIssueID))
            let missingIDs = (detail.issues ?? []).map(\.id).filter { !owned.contains($0) }
            if !missingIDs.isEmpty {
                others = (try? await ComicVineKey.client.issues(ids: missingIDs)) ?? []
            }
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }
}

/// Un número del arco que no tenés: en gris.
private struct ArcMissingCard: View {
    let title: String
    let subtitle: String?
    let date: String?
    let cover: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            RemoteCover(url: cover)
                .grayscale(1)
                .opacity(0.45)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            if let subtitle = subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            if let date {
                Text(date).font(.caption2).foregroundStyle(Theme.ink2)
            }
            Text("No lo tenés").font(.caption2).foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: - Carpeta de una editorial

/// Tus cómics de una editorial, en carpetas por serie.
struct PublisherFolderView: View {
    let name: String
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let comics = library.items.filter { LibraryGrouping.publisherName($0) == name }
        let groups = LibraryGrouping.series(comics)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 26, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text("\(countText(comics.count)) en \(groups.count) \(groups.count == 1 ? "serie" : "series")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.bottom, 18)

                FolderGrid {
                    ForEach(groups) { group in
                        NavigationLink(value: LibraryRoute.series(group.seriesID)) {
                            FolderCard(title: group.name, subtitle: countText(group.comics.count),
                                       cover: group.comics.first, icon: "questionmark.folder")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
