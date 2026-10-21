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
    @State private var choosingOrder = false
    private var orders: ReadingOrderStore { ReadingOrderStore.shared }

    /// Lista de lectura elegida para este arco, si se está usando.
    private var readingOrder: SavedReadingOrder? {
        orders.byDate.contains(arcID) ? nil : orders.orders[arcID]
    }

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
        /// Número de la lista de lectura que no tenés y del que no hay más datos.
        case listed(Int, SavedReadingOrder.Item)
        /// Número que no tenés suelto pero sí dentro de un TPB tuyo.
        case collected(cvID: Int, title: String, subtitle: String?, cover: URL?, date: String?, tpb: LocalComic)

        var id: String {
            switch self {
            case .owned(let c): return "mio-\(c.id)"
            case .missing(let i): return "falta-\(i.id)"
            case .bare(let i): return "falta-\(i.id)"
            case .listed(let index, let item): return item.cvID.map { "falta-\($0)" } ?? "lista-\(index)"
            case .collected(let cvID, _, _, _, _, _): return "tpb-\(cvID)"
            }
        }

        /// Código de Comic Vine del número (si se sabe).
        var cvID: Int? {
            switch self {
            case .owned(let c): return c.cvIssueID
            case .missing(let i): return i.id
            case .bare(let i): return i.id
            case .listed(_, let item): return item.cvID
            case .collected(let cvID, _, _, _, _, _): return cvID
            }
        }

        /// Fecha para ordenar ("9999" = sin fecha, al final).
        var date: String {
            switch self {
            case .owned(let c): return c.publicationDate ?? "9999"
            case .missing(let i): return i.coverDate ?? i.storeDate ?? "9999"
            case .bare: return "9999"
            case .listed(_, let item): return item.coverDate ?? "9999"
            case .collected(_, _, _, _, let date, _): return date ?? "9999"
            }
        }
    }

    /// En orden de lectura: primero los números de la lista (tuyos a color, los que faltan en gris);
    /// después, los del arco que la lista no incluye.
    private func readingSlots(_ order: SavedReadingOrder, mine: [LocalComic]) -> (inList: [Slot], extra: [Slot]) {
        let byCV = Dictionary(library.items.compactMap { c in c.cvIssueID.map { ($0, c) } },
                              uniquingKeysWith: { first, _ in first })
        let collected = library.collectedIssues
        let detailed = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<Int>()
        var list: [Slot] = []
        for (index, item) in order.items.enumerated() {
            if let cv = item.cvID {
                guard used.insert(cv).inserted else { continue }
                if let comic = byCV[cv] {
                    list.append(.owned(comic))
                } else if let tpb = collected[cv] {
                    list.append(collectedSlot(cv, tpb: tpb,
                                              fallbackTitle: CVText.issueTitle(series: item.series, number: item.number),
                                              fallbackDate: item.coverDate))
                } else if showMissing {
                    list.append(detailed[cv].map(Slot.missing) ?? .listed(index, item))
                }
            } else if showMissing {
                list.append(.listed(index, item))
            }
        }
        let extra = slots(mine).filter { slot in slot.cvID.map { !used.contains($0) } ?? true }
        return (list, extra)
    }

    /// Un número que está dentro de un TPB tuyo, con los datos que haya (de Comic Vine o del TPB).
    private func collectedSlot(_ cvID: Int, tpb: LocalComic, fallbackTitle: String?, fallbackDate: String?) -> Slot {
        let full = others.first { $0.id == cvID }
        let saved = tpb.contents?.first { $0.cvID == cvID }
        return .collected(cvID: cvID,
                          title: full.map(Self.title) ?? saved?.title ?? fallbackTitle ?? "Número",
                          subtitle: full?.name,
                          cover: full?.image?.small ?? saved?.cover.flatMap { URL(string: $0) },
                          date: full?.coverDate ?? saved?.coverDate ?? fallbackDate,
                          tpb: tpb)
    }

    private func slots(_ mine: [LocalComic]) -> [Slot] {
        let owned = Set(mine.compactMap(\.cvIssueID))
        let collected = library.collectedIssues
        let arcIDs = Set(arc?.issues?.map(\.id) ?? [])
        // Un TPB que trae números de este arco se ve por esos números, no como tapa aparte.
        let shown = mine.filter { c in !(c.isCollection && (c.contents ?? []).contains { arcIDs.contains($0.cvID) }) }
        var list = shown.map(Slot.owned)
        if let arcIssues = arc?.issues {
            let detailed = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for issue in arcIssues where !owned.contains(issue.id) {
                if let tpb = collected[issue.id] {
                    list.append(collectedSlot(issue.id, tpb: tpb,
                                              fallbackTitle: issue.issueNumber.map { "#\($0)" }, fallbackDate: nil))
                } else if !showMissing {
                    continue
                } else if let full = detailed[issue.id] {
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
        let order = readingOrder
        let reading = order.map { readingSlots($0, mine: mine) }
        let listIDs = Set(order?.items.compactMap(\.cvID) ?? [])
        let total = order == nil ? arc?.issues?.count : listIDs.count
        // Los tuyos: sueltos o dentro de un TPB.
        let yours = Set(library.items.compactMap(\.cvIssueID)).union(library.collectedIssues.keys)
        let have = order == nil
            ? (arc?.issues.map { Set($0.map(\.id)).intersection(yours).count } ?? Set(mine.compactMap(\.cvIssueID)).count)
            : yours.intersection(listIDs).count
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

                readingOrderControls

                ComicVineSummary(deck: arc?.deck, description: arc?.description)
                    .padding(.top, 12)

                SectionTitle(order == nil ? "Números, por fecha de publicación" : "Números, en orden de lectura")
                if loading && arc == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if let errorText {
                    Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2).padding(.bottom, 12)
                }

                if let reading {
                    grid(reading.inList)
                    if !reading.extra.isEmpty {
                        SectionTitle("Del arco, pero no están en esta lista")
                        grid(reading.extra)
                    }
                } else {
                    grid(slots(mine))
                }

                Text(showMissing
                     ? "Los grises son los que no tenés: tocá uno para ver su ficha y marcarlo \"Quiero leer\". Podés ocultarlos en Perfil → Configuración."
                     : "Los números que no tenés están ocultos (Perfil → Configuración).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 12)

                if let order {
                    Text(order.origin == "cbl"
                         ? "Orden de lectura: lista \"\(order.name)\" (colección pública de listas .cbl, github.com/DieselTech/CBL-ReadingLists)."
                         : "Orden de lectura: lista \"\(order.name)\" de Metron. Datos: Metron y Comic Vine.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                }

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
        .task(id: order?.listID) { await loadListDetails() }
        .sheet(isPresented: $choosingOrder) {
            ReadingOrderPicker(arcID: arcID, arcName: arc?.name ?? name)
        }
    }

    private func grid(_ slots: [Slot]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                  alignment: .leading, spacing: 18) {
            ForEach(slots) { slot in
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
                case .collected(_, let title, let subtitle, let cover, _, let tpb):
                    CollectedIssueCard(title: title, subtitle: subtitle, cover: cover, tpb: tpb)
                case .listed(_, let item):
                    let title = CVText.issueTitle(series: item.series, number: item.number)
                    if let cv = item.cvID {
                        NavigationLink(value: CVRoute.issue(id: cv, title: title)) {
                            ArcMissingCard(title: title, subtitle: nil,
                                           date: CVText.monthYear(item.coverDate), cover: nil)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ArcMissingCard(title: title, subtitle: nil,
                                       date: CVText.monthYear(item.coverDate), cover: nil)
                    }
                }
            }
        }
    }

    /// Botón para elegir el orden de lectura (Metron) y cambiar entre "orden de lectura" y "por fecha".
    @ViewBuilder private var readingOrderControls: some View {
        if let saved = orders.orders[arcID] {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Orden", selection: Binding(get: { !orders.byDate.contains(arcID) },
                                                   set: { orders.useReadingOrder($0, arc: arcID) })) {
                    Text("Orden de lectura").tag(true)
                    Text("Por fecha").tag(false)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 6) {
                    Text(CVText.join([saved.name, ReadingSource.name(saved.source)]))
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Cambiar lista") { choosingOrder = true }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
            }
            .padding(.top, 14)
        } else {
            Button {
                choosingOrder = true
            } label: {
                Label("Orden de lectura (buscar listas)", systemImage: "list.number")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    /// Portadas y nombres (de Comic Vine) de los números de la lista que no tenés.
    private func loadListDetails() async {
        guard let order = readingOrder, !ComicVineKey.current.isEmpty else { return }
        let owned = Set(library.items.compactMap(\.cvIssueID))
        let known = Set(others.map(\.id))
        let wanted = order.items.compactMap(\.cvID).filter { !owned.contains($0) && !known.contains($0) }
        // Como mucho 300 (3 consultas), para cuidar el límite de Comic Vine.
        var seen = Set<Int>()
        let ids = Array(wanted.filter { seen.insert($0).inserted }.prefix(300))
        guard !ids.isEmpty, let found = try? await ComicVineKey.client.issues(ids: ids) else { return }
        others += found
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
            Label("Descargar", systemImage: "arrow.down.circle").font(.caption2.weight(.semibold)).foregroundStyle(Theme.magenta)
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
