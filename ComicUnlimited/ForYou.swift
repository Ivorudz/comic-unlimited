import SwiftUI
import Observation

// "Para vos" en Inicio: sugerencias de cómics reales parecidos a los que venís mirando.
// Cada vez que abrís la ficha de un cómic real, se anota la serie, los guionistas y los personajes.
// Con eso se le piden a Comic Vine otras series del mismo guionista o con los mismos personajes.

// MARK: - Historial de cómics reales

/// Un cómic real cuya ficha abriste. Se guardan solo datos de texto (nada de imágenes).
struct ViewedIssue: Codable {
    struct Ref: Codable, Hashable {
        let id: Int
        let name: String
    }

    let id: Int
    let title: String
    let series: Ref?
    let writers: [Ref]
    let characters: [Ref]
}

enum RealHistory {
    private static let storageKey = "real.history"
    private static let maxItems = 30

    /// Lo último que miraste primero.
    static var items: [ViewedIssue] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([ViewedIssue].self, from: data) else { return [] }
        return list
    }

    static func record(_ d: CVIssueDetail) {
        let writers = (d.personCredits ?? [])
            .filter { ($0.role ?? "").lowercased().contains("writer") }
            .compactMap { c in c.name.map { ViewedIssue.Ref(id: c.id, name: $0) } }
        let characters = (d.characterCredits ?? []).prefix(3)
            .compactMap { c in c.name.map { ViewedIssue.Ref(id: c.id, name: $0) } }
        let series = d.volume.flatMap { v in v.name.map { ViewedIssue.Ref(id: v.id, name: $0) } }
        let item = ViewedIssue(
            id: d.id,
            title: CVText.issueTitle(series: d.volume?.name ?? "Cómic", number: d.issueNumber),
            series: series,
            writers: Array(writers.prefix(3)),
            characters: Array(characters)
        )
        var list = items.filter { $0.id != d.id }
        list.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(maxItems))) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Sugerencias

struct Suggestion: Identifiable {
    let id: Int
    let name: String
    let coverURL: URL?
    let reason: String
}

@MainActor
@Observable
final class ForYouModel {
    enum Phase {
        case idle
        case noKey
        case noHistory
        case loading
        case loaded([Suggestion])
        case failed(String)
    }

    private(set) var state: Phase = .idle
    /// Qué historial se usó la última vez; si cambia, se vuelve a calcular.
    private var lastSignature = ""

    private static let maxSuggestions = 16
    private static let perSeed = 4

    func loadIfNeeded() async {
        guard !ComicVineKey.current.isEmpty else {
            state = .noKey
            return
        }
        let history = RealHistory.items
        guard !history.isEmpty else {
            state = .noHistory
            return
        }
        let signature = history.prefix(10).map { String($0.id) }.joined(separator: ",")
        if case .loading = state { return }
        if signature == lastSignature, case .loaded = state { return }
        lastSignature = signature
        await load(history)
    }

    private func load(_ history: [ViewedIssue]) async {
        state = .loading
        let client = ComicVineKey.client
        let seen = Set(history.compactMap { $0.series?.id })

        // Guionistas y personajes que más se repiten (los más recientes ganan en empate).
        let writers = Self.top(history.map(\.writers), count: 2)
        let characters = Self.top(history.map(\.characters), count: 2)
        let seeds: [(ref: ViewedIssue.Ref, isWriter: Bool)] =
            writers.map { (ref: $0, isWriter: true) } + characters.map { (ref: $0, isWriter: false) }

        var results: [Suggestion] = []
        var used = seen
        var lastError: Error?

        for seed in seeds {
            if results.count >= Self.maxSuggestions { break }
            do {
                let series = seed.isWriter
                    ? try await client.personSeries(id: seed.ref.id)
                    : try await client.characterSeries(id: seed.ref.id)
                // Las series con número más alto en Comic Vine suelen ser las más nuevas.
                let picks = series.filter { !used.contains($0.id) }
                    .sorted { $0.id > $1.id }
                    .prefix(Self.perSeed)
                for pick in picks {
                    used.insert(pick.id)
                    let detail = try? await client.series(id: pick.id)
                    results.append(Suggestion(
                        id: pick.id,
                        name: detail?.name ?? pick.name ?? "Serie",
                        coverURL: detail?.image?.small,
                        reason: seed.isWriter ? "Del guion de \(seed.ref.name)" : "Con \(seed.ref.name)"
                    ))
                    // Se muestran a medida que llegan.
                    state = .loaded(results)
                }
            } catch {
                lastError = error
            }
        }

        if results.isEmpty, let lastError {
            state = .failed(CVText.message(for: lastError))
        } else {
            state = .loaded(results)
        }
    }

    func retry() async {
        lastSignature = ""
        state = .idle
        await loadIfNeeded()
    }

    /// Los que más se repiten en el historial.
    private static func top(_ lists: [[ViewedIssue.Ref]], count: Int) -> [ViewedIssue.Ref] {
        var score: [ViewedIssue.Ref: Double] = [:]
        for (index, list) in lists.enumerated() {
            // Lo más reciente pesa un poquito más.
            let weight = 1 + 1 / Double(index + 1)
            for ref in list { score[ref, default: 0] += weight }
        }
        return score.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }
}

// MARK: - Fila de "Para vos"

struct ForYouRow: View {
    let model: ForYouModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Buscando cómics parecidos…").font(.subheadline).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .noKey:
                notice("Para sugerirte cómics reales, cargá tu clave de Comic Vine en la pestaña Próximos (abajo de todo, en \"Cuentas de Metron y Comic Vine\").")
            case .noHistory:
                notice("Abrí la ficha de algunos cómics reales (tocá uno en Recién salidos o usá Buscar cómics reales) y acá te vamos a sugerir otros parecidos.")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    notice(message)
                    Button("Probar de nuevo") { Task { await model.retry() } }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
            case .loaded(let items):
                if items.isEmpty {
                    notice("No encontré series parecidas todavía. Abrí la ficha de algunos cómics reales más.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: CVRoute.series(id: item.id, name: item.name)) {
                                    SuggestionCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                }
            }
        }
        .task { await model.loadIfNeeded() }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

private struct SuggestionCard: View {
    let item: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: item.coverURL)
            Text(item.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            Text(item.reason)
                .font(.caption)
                .foregroundStyle(Theme.magenta)
                .lineLimit(2)
        }
        .frame(width: 110)
    }
}
