import SwiftUI
import Observation

// Géneros en Descubrir (Inicio): filas como "Terror", "Superhéroes" o "Ciencia ficción" con los
// cómics que salieron en la última semana.
// Comic Vine no tiene géneros; Metron sí, en cada serie. Metron no deja pedir "los de terror de esta
// semana" de una vez, así que se pide la lista de la semana y después el género de cada serie, de a una
// y despacio (como mucho unas 17 por minuto; el límite de Metron es 20). El género de cada serie queda
// guardado en el iPhone (solo el nombre del género y la editorial), así que la primera vez tarda unos
// minutos y después casi no hace falta preguntar.

@MainActor
@Observable
final class GenreModel {
    enum Phase: Equatable {
        case idle
        case noAccount
        case loading
        case ready
        case failed(String)
    }

    struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let issues: [UpcomingIssue]
    }

    /// Un cómic de la semana y su serie en Metron.
    private struct WeekIssue: Codable {
        let issue: UpcomingIssue
        let seriesID: Int
    }

    /// Lo que se sabe de cada serie: sus géneros (como los escribe Metron) y su editorial.
    private struct SeriesInfo: Codable {
        var genres: [String]
        var publisher: String?
    }

    private struct SavedWeek: Codable {
        var date: Date
        var items: [WeekIssue]
    }

    private(set) var phase: Phase = .idle
    /// Series a las que todavía les falta saber el género.
    private(set) var pending = 0
    private var week: [WeekIssue] = []
    private var weekDate: Date?
    private var series: [Int: SeriesInfo] = [:]
    private var task: Task<Void, Never>?

    private static let weekCache = "inicio-generos-semana.json"
    private static let seriesFile: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("generos-series.json")
    }()
    /// Pausa entre consultas a Metron (unas 17 por minuto).
    private static let pause: Duration = .milliseconds(3500)
    /// Como mucho tantas series nuevas por vez que se abre la app.
    private static let maxPerLaunch = 90

    init() {
        if let saved: SavedWeek = HomeCache.read(Self.weekCache) {
            week = saved.items
            weekDate = saved.date
        }
        if let data = try? Data(contentsOf: Self.seriesFile),
           let saved = try? JSONDecoder().decode([Int: SeriesInfo].self, from: data) {
            series = saved
        }
        if !week.isEmpty { phase = .ready }
    }

    /// Empieza a cargar (una vez por vez que se abre la app). Sigue aunque cambies de pestaña.
    func start() {
        guard MetronAccount.isSet else {
            phase = .noAccount
            return
        }
        if phase == .noAccount { phase = week.isEmpty ? .idle : .ready }
        guard task == nil else { return }
        task = Task { await run() }
    }

    func retry() {
        task = nil
        weekDate = nil
        phase = .idle
        start()
    }

    private func run() async {
        let client = MetronClient(user: MetronAccount.user, password: MetronAccount.password)

        // 1. Los cómics de la semana (si lo guardado tiene más de 3 horas).
        if weekDate.map({ Date().timeIntervalSince($0) > 3 * 60 * 60 }) ?? true {
            if week.isEmpty { phase = .loading }
            do {
                week = try await fetchWeek(client)
                weekDate = Date()
                HomeCache.write(SavedWeek(date: Date(), items: week), Self.weekCache)
            } catch {
                if week.isEmpty {
                    phase = .failed((error as? LocalizedError)?.errorDescription ?? "No se pudo conectar con Metron.")
                    return
                }
            }
        }
        phase = .ready

        // 2. El género de cada serie que falta, de a una y despacio.
        var missing: [Int] = []
        for item in week where series[item.seriesID] == nil && !missing.contains(item.seriesID) {
            missing.append(item.seriesID)
        }
        missing = Array(missing.prefix(Self.maxPerLaunch))
        pending = missing.count
        var waitedForLimit = false
        for id in missing {
            try? await Task.sleep(for: Self.pause)
            do {
                let detail: MetronSeriesDetail = try await client.get(URL(string: "https://metron.cloud/api/series/\(id)/")!)
                series[id] = SeriesInfo(genres: (detail.genres ?? []).compactMap(\.name),
                                        publisher: detail.publisher?.name)
                saveSeries()
            } catch MetronError.tooManyRequests {
                // Nos pasamos del límite: esperamos un minuto una vez; si vuelve a pasar, seguimos otro día.
                if waitedForLimit { break }
                waitedForLimit = true
                try? await Task.sleep(for: .seconds(60))
            } catch {
                // Esa serie queda para la próxima vez.
            }
            pending -= 1
        }
        pending = 0
    }

    private func fetchWeek(_ client: MetronClient) async throws -> [WeekIssue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let day = ComicVineClient.dayFormatter
        var components = URLComponents(string: "https://metron.cloud/api/issue/")!
        components.queryItems = [
            URLQueryItem(name: "store_date_range_after", value: day.string(from: from)),
            URLQueryItem(name: "store_date_range_before", value: day.string(from: to)),
        ]
        var next = components.url
        var result: [WeekIssue] = []
        var seen = Set<Int>()
        var pages = 0
        while let url = next, pages < 4 {
            if pages > 0 { try? await Task.sleep(for: Self.pause) }
            let page: MetronPage = try await client.get(url)
            for issue in page.results {
                guard seen.insert(issue.id).inserted,
                      let seriesID = issue.series?.id,
                      let text = issue.storeDate, let date = day.date(from: text) else { continue }
                var name = issue.series?.name ?? "Sin título"
                if let volume = issue.series?.volume, volume > 1 { name += " (vol. \(volume))" }
                result.append(WeekIssue(issue: UpcomingIssue(
                    id: issue.id, series: name, number: issue.number ?? "", issueName: nil, date: date,
                    coverURL: issue.image.flatMap { URL(string: $0) }, link: nil, volumeID: nil,
                    publisher: nil, metronID: issue.id), seriesID: seriesID))
            }
            next = page.next.flatMap { URL(string: $0) }
            pages += 1
        }
        return result
    }

    private func saveSeries() {
        if let data = try? JSONEncoder().encode(series) {
            try? data.write(to: Self.seriesFile, options: .atomic)
        }
    }

    // MARK: Filas

    /// Géneros de Metron → nombre en español y orden en que se muestran. Los que no están acá no se muestran
    /// (por ejemplo manga o para adultos).
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
        ("military", "Bélicos"),
        ("war", "Bélicos"),
        ("western", "Western"),
        ("humor", "Humor"),
        ("romance", "Romance"),
        ("historical", "Históricos"),
        ("sport", "Deportes"),
        ("martial arts", "Artes marciales"),
        ("teen", "Juveniles"),
        ("anthology", "Antologías"),
    ]

    var rows: [Row] {
        var byGenre: [String: [UpcomingIssue]] = [:]
        for item in week {
            guard let info = series[item.seriesID] else { continue }
            // Solo editoriales de cómics (sin manga ni ediciones de otros países).
            if let publisher = info.publisher, !ComicPublishers.isComics(publisher) { continue }
            var added = Set<String>()
            for genre in info.genres {
                guard let spanish = Self.genreNames.first(where: { $0.metron == genre.lowercased() })?.spanish,
                      added.insert(spanish).inserted else { continue }
                var issue = item.issue
                issue.publisher = info.publisher.map(ComicPublishers.displayName)
                byGenre[spanish, default: []].append(issue)
            }
        }
        var order: [String] = []
        for name in Self.genreNames.map({ $0.spanish }) where !order.contains(name) { order.append(name) }
        return order.compactMap { name in
            guard let issues = byGenre[name], issues.count >= 3 else { return nil }
            return Row(id: "genero-\(name)", title: name,
                       subtitle: "\(issues.count) cómics de la semana · géneros de Metron",
                       issues: Array(DiscoverModel.sorted(issues).prefix(DiscoverModel.limit)))
        }
    }
}

/// Ficha de una serie en Metron (solo lo que usamos: editorial y géneros).
private struct MetronSeriesDetail: Decodable {
    struct Named: Decodable { let id: Int?; let name: String? }
    let id: Int
    let publisher: Named?
    let genres: [Named]?
}

// MARK: - Filas por género

struct GenreRows: View {
    let model: GenreModel

    var body: some View {
        let rows = model.rows
        VStack(alignment: .leading, spacing: 0) {
            switch model.phase {
            case .noAccount:
                hint("Para ver los cómics por género (terror, superhéroes, ciencia ficción…), cargá tu cuenta de Metron en la pestaña Próximos, abajo de todo.")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    hint("Géneros: \(message)")
                    Button("Probar de nuevo") { model.retry() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .padding(.bottom, 22)
            case .idle, .loading, .ready:
                if rows.isEmpty && (model.phase == .loading || model.pending > 0) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ordenando los cómics de la semana por género…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.bottom, 22)
                }
                ForEach(rows) { row in
                    DiscoverRowTitle(title: row.title, subtitle: row.subtitle)
                    IssueCardsRow(issues: row.issues)
                        .padding(.bottom, 22)
                }
                if !rows.isEmpty && model.pending > 0 {
                    Text("Faltan los géneros de \(model.pending) series: van apareciendo solas.")
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
