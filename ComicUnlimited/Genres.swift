import SwiftUI
import Observation

// Géneros en Descubrir (Inicio): filas como "Terror", "Superhéroes" o "Ciencia ficción" con series
// de cualquier época.
// Comic Vine no tiene géneros (sus "temas" no sirven para esto); Metron sí, en la ficha de cada serie,
// pero no deja pedir "todas las de terror". Por eso la app arma de a poco su propia lista:
//   1. Junta series para clasificar: las de tus listas y tu Biblioteca, y páginas al azar de las
//      editoriales grandes (todas las épocas), 100 series por consulta.
//   2. Le pregunta a Metron el género de cada una, de a una y despacio (3,5 s entre consultas; como mucho
//      90 consultas por vez que se abre la app; el límite de Metron es 20 por minuto y 5.000 por día).
//   3. Pide a Comic Vine las portadas de 100 series juntas (cada serie de Metron trae su código de Comic Vine).
// Todo queda guardado en el iPhone (nombre, año, editorial, géneros y el link de la portada; nunca la imagen),
// así que las filas se llenan con los días y no se vuelve a preguntar lo mismo.

@MainActor
@Observable
final class GenreModel {
    enum Phase: Equatable {
        case idle
        case noAccount
        case working
        case done
    }

    struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let series: [SeriesItem]
    }

    struct SeriesItem: Identifiable {
        let id: Int          // código de Comic Vine (para abrir la ficha)
        let name: String
        let detail: String   // "1963 · Marvel"
        let cover: URL?
    }

    /// Una serie ya clasificada.
    private struct SeriesInfo: Codable {
        var name: String
        var yearBegan: Int?
        var publisher: String?
        var cvID: Int?
        var genres: [String]
        var cover: String?
    }

    /// Una serie esperando que Metron diga su género.
    private struct Candidate: Codable {
        var id: Int
        var cvID: Int?
    }

    private struct Store: Codable {
        /// Series clasificadas, por su número en Metron.
        var series: [Int: SeriesInfo] = [:]
        var queue: [Candidate] = []
        /// Códigos de Comic Vine de tus series que ya se buscaron en Metron.
        var checkedOwn: Set<Int> = []
        /// Cuántas páginas de series tiene cada editorial, y cuáles ya se pidieron.
        var pageCounts: [String: Int] = [:]
        var seenPages: [String: [Int]] = [:]
        var nextPublisher = 0
    }

    private(set) var phase: Phase = .idle
    /// Series clasificadas desde que se abrió la app.
    private(set) var classifiedNow = 0
    private var store = Store()
    private var task: Task<Void, Never>?
    /// Para mezclar las series distinto cada vez que se abre la app.
    private let salt = UInt64.random(in: 1...UInt64.max)

    // Límites para cuidar Metron.
    private var budget = 0
    private var waitedForLimit = false
    private var stopped = false

    private static let pause: Duration = .milliseconds(3500)
    private static let maxPerLaunch = 90
    private static let maxOwnPerLaunch = 15
    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("generos.json")
    }()

    /// Editoriales de donde se sacan series para clasificar (nombre como lo busca Metron).
    private static let publishers = ["marvel", "dc comics", "image", "dark horse", "idw", "boom", "dynamite",
                                     "titan", "archie", "oni", "valiant", "rebellion", "vault", "mad cave",
                                     "ahoy", "aftershock", "awa"]

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode(Store.self, from: data) {
            store = saved
        }
    }

    /// Empieza a clasificar (una vez por vez que se abre la app). Sigue aunque cambies de pestaña.
    func start() {
        guard MetronAccount.isSet else {
            phase = .noAccount
            return
        }
        if phase == .noAccount { phase = .idle }
        guard task == nil else { return }
        task = Task { await run() }
    }

    // MARK: Clasificar

    private func run() async {
        phase = .working
        budget = Self.maxPerLaunch
        let client = MetronClient(user: MetronAccount.user, password: MetronAccount.password)

        await fetchCovers()
        await addOwnSeries(client)
        if store.queue.count < 60 {
            for _ in 0..<2 where !stopped { await addPublisherPage(client) }
        }

        while budget > 0, !stopped, !store.queue.isEmpty {
            let candidate = store.queue.removeFirst()
            guard store.series[candidate.id] == nil else { continue }
            guard let detail: MetronSeriesDetail = await get(client, "series/\(candidate.id)/") else {
                save()
                continue
            }
            store.series[candidate.id] = SeriesInfo(
                name: detail.name ?? "Serie",
                yearBegan: detail.yearBegan,
                publisher: detail.publisher?.name,
                cvID: detail.cvId ?? candidate.cvID,
                genres: (detail.genres ?? []).compactMap(\.name)
            )
            classifiedNow += 1
            save()
            if classifiedNow % 30 == 0 { await fetchCovers() }
        }
        await fetchCovers()
        save()
        phase = .done
    }

    /// Tus series (listas de Perfil y Biblioteca): se buscan en Metron por su código de Comic Vine.
    private func addOwnSeries(_ client: MetronClient) async {
        var own: [Int] = []
        for entry in RealLibrary.shared.entries.values {
            if entry.isSeries { own.append(entry.id) } else if let id = entry.series?.id { own.append(id) }
        }
        own += LocalLibrary.shared.items.compactMap(\.cvSeriesID)
        let known = Set(store.series.values.compactMap(\.cvID)).union(store.queue.compactMap(\.cvID))
        var todo: [Int] = []
        for id in own where id > 0 && !store.checkedOwn.contains(id) && !known.contains(id) && !todo.contains(id) {
            todo.append(id)
        }
        for cvID in todo.prefix(Self.maxOwnPerLaunch) {
            guard !stopped else { break }
            guard let page: MetronSeriesPage = await get(client, "series/", ["cv_id": "\(cvID)"]) else { continue }
            store.checkedOwn.insert(cvID)
            if let first = page.results.first, store.series[first.id] == nil {
                store.queue.insert(Candidate(id: first.id, cvID: first.cvId ?? cvID), at: 0)
            }
        }
        save()
    }

    /// Una página al azar de series de una editorial (100 series de todas las épocas).
    private func addPublisherPage(_ client: MetronClient) async {
        let publisher = Self.publishers[store.nextPublisher % Self.publishers.count]
        store.nextPublisher += 1
        var page = 1
        if let count = store.pageCounts[publisher], count > 1 {
            let seen = Set(store.seenPages[publisher] ?? [])
            let fresh = (1...count).filter { !seen.contains($0) }
            page = fresh.randomElement() ?? Int.random(in: 1...count)
        }
        guard let result: MetronSeriesPage = await get(client, "series/",
                                                      ["publisher_name": publisher, "page": "\(page)"]) else { return }
        store.seenPages[publisher, default: []].append(page)
        if page == 1, let total = result.count, !result.results.isEmpty {
            store.pageCounts[publisher] = max(1, Int((Double(total) / Double(result.results.count)).rounded(.up)))
        }
        let queued = Set(store.queue.map(\.id))
        let picks = result.results.filter { item in
            guard item.cvId != nil, (item.issueCount ?? 0) >= 3,
                  store.series[item.id] == nil, !queued.contains(item.id) else { return false }
            // Sin tomos recopilatorios ni ediciones digitales (sus números ya están en las series).
            let type = (item.seriesType?.name ?? "").lowercased()
            return !["trade", "hardcover", "omnibus", "digital"].contains { type.contains($0) }
        }
        store.queue += picks.shuffled().map { Candidate(id: $0.id, cvID: $0.cvId) }
        save()
    }

    /// Portadas de Comic Vine para las series clasificadas que todavía no tienen (de a 100 por consulta).
    private func fetchCovers() async {
        guard !ComicVineKey.current.isEmpty else { return }
        let missing = store.series.values.filter { $0.cover == nil && Self.isShown($0) }.compactMap(\.cvID)
        guard !missing.isEmpty else { return }
        let covers = await ComicVineKey.client.volumeCovers(ids: Array(missing.prefix(300)))
        guard !covers.isEmpty else { return }
        for (id, info) in store.series {
            if let cv = info.cvID, info.cover == nil, let url = covers[cv] {
                store.series[id]?.cover = url.absoluteString
            }
        }
        save()
    }

    /// Consulta a Metron con pausa entre pedidos, tope por vez y espera si Metron dice "demasiadas consultas".
    private func get<T: Decodable>(_ client: MetronClient, _ path: String, _ params: [String: String] = [:]) async -> T? {
        guard budget > 0, !stopped else { return nil }
        var components = URLComponents(string: "https://metron.cloud/api/\(path)")!
        if !params.isEmpty {
            components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { return nil }
        for _ in 0..<2 {
            try? await Task.sleep(for: Self.pause)
            budget -= 1
            do {
                return try await client.get(url)
            } catch MetronError.tooManyRequests {
                // Una vez esperamos un minuto; si vuelve a pasar, seguimos la próxima vez que se abra la app.
                if waitedForLimit { stopped = true; return nil }
                waitedForLimit = true
                try? await Task.sleep(for: .seconds(60))
            } catch MetronError.badLogin {
                stopped = true
                return nil
            } catch {
                return nil
            }
        }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    // MARK: Filas

    /// Géneros de Metron → nombre en español y orden en que se muestran.
    /// Los que no están acá (manga, para adultos) no se muestran.
    private static let genreNames: [(metron: String, spanish: String)] = [
        ("super-hero", "Superhéroes"),
        ("horror", "Terror"),
        ("science fiction", "Ciencia ficción"),
        ("fantasy", "Fantasía"),
        ("crime", "Policiales"),
        ("mystery", "Misterio"),
        ("action", "Acción"),
        ("adventure", "Aventura"),
        ("espionage", "Espionaje"),
        ("war", "Bélicos"),
        ("military", "Bélicos"),
        ("western", "Western"),
        ("humor", "Humor"),
        ("historical", "Históricos"),
        ("romance", "Romance"),
        ("sport", "Deportes"),
        ("martial arts", "Artes marciales"),
        ("teen", "Juveniles"),
    ]

    /// Se muestra si tiene ficha de Comic Vine, no es manga ni para adultos y es de una editorial de cómics.
    private static func isShown(_ info: SeriesInfo) -> Bool {
        guard info.cvID != nil else { return false }
        let lower = info.genres.map { $0.lowercased() }
        if lower.contains("manga") || lower.contains("adult") { return false }
        if let publisher = info.publisher, !ComicPublishers.isComics(publisher) { return false }
        return true
    }

    var rows: [Row] {
        var byGenre: [String: [(order: UInt64, item: SeriesItem)]] = [:]
        for (metronID, info) in store.series where Self.isShown(info) {
            guard let cvID = info.cvID else { continue }
            let detail = [info.yearBegan.map { String($0) }, info.publisher.map(ComicPublishers.displayName)]
                .compactMap { $0 }.joined(separator: " · ")
            let item = SeriesItem(id: cvID, name: info.name, detail: detail, cover: info.cover.flatMap { URL(string: $0) })
            // Orden mezclado, distinto cada vez que se abre la app.
            let order = UInt64(truncatingIfNeeded: metronID) &* 0x9E37_79B9_7F4A_7C15 ^ salt
            var added = Set<String>()
            for genre in info.genres {
                guard let spanish = Self.genreNames.first(where: { $0.metron == genre.lowercased() })?.spanish,
                      added.insert(spanish).inserted else { continue }
                byGenre[spanish, default: []].append((order: order, item: item))
            }
        }
        var names: [String] = []
        for pair in Self.genreNames where !names.contains(pair.spanish) { names.append(pair.spanish) }
        return names.compactMap { name in
            guard let list = byGenre[name], list.count >= 3 else { return nil }
            let picked = list.sorted { $0.order < $1.order }.prefix(20).map { $0.item }
            return Row(id: "genero-\(name)", title: name,
                       subtitle: "\(list.count) series de todas las épocas · géneros de Metron",
                       series: Array(picked))
        }
    }
}

// MARK: - Cómo vienen las series de Metron

private struct MetronRef: Decodable {
    let id: Int?
    let name: String?
}

private struct MetronSeriesPage: Decodable {
    let count: Int?
    let next: String?
    let results: [MetronSeriesItem]
}

private struct MetronSeriesItem: Decodable {
    let id: Int
    let series: String?
    let yearBegan: Int?
    let issueCount: Int?
    let seriesType: MetronRef?
    let cvId: Int?
}

private struct MetronSeriesDetail: Decodable {
    let id: Int
    let name: String?
    let yearBegan: Int?
    let publisher: MetronRef?
    let genres: [MetronRef]?
    let cvId: Int?
}

// MARK: - Filas por género

struct GenreRows: View {
    let model: GenreModel

    var body: some View {
        let rows = model.rows
        VStack(alignment: .leading, spacing: 0) {
            if model.phase == .noAccount {
                hint("Para ver series por género (terror, superhéroes, ciencia ficción…), cargá tu cuenta de Metron en Perfil → Configuración → Cuentas de Metron y Comic Vine.")
            } else {
                if rows.isEmpty && model.phase == .working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ordenando series por género… las primeras filas aparecen en unos minutos.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.bottom, 22)
                }
                ForEach(rows) { row in
                    DiscoverRowTitle(title: row.title, subtitle: row.subtitle)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.series) { series in
                                NavigationLink(value: CVRoute.series(id: series.id, name: series.name)) {
                                    GenreSeriesCard(series: series)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                    .padding(.bottom, 22)
                }
                if !rows.isEmpty && model.phase == .working {
                    Text("Sumando series a los géneros (\(model.classifiedNow) nuevas desde que abriste la app)…")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.bottom, 22)
                }
            }
        }
        .onAppear { model.start() }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .padding(.bottom, 22)
    }
}

private struct GenreSeriesCard: View {
    let series: GenreModel.SeriesItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: series.cover)
            Text(series.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            Text(series.detail)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
        }
        .frame(width: 110)
    }
}
