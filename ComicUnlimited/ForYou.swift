import SwiftUI
import Observation

// "Para vos" en Inicio: sugerencias de series según tus puntajes y tus listas
// (Quiero leer, Leyendo, Leído). Se busca qué guionistas y personajes te gustan más
// y se le piden a Comic Vine otras series de ellos.
// Las últimas sugerencias quedan guardadas en el iPhone (solo datos y links, no imágenes):
// se muestran al abrir la app y se recalculan si cambiaron tus listas o pasó un día.

// MARK: - Sugerencias

struct Suggestion: Identifiable, Codable {
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
    /// Se están buscando sugerencias nuevas (mientras tanto se ven las guardadas).
    private(set) var refreshing = false
    /// Qué historial se usó la última vez; si cambia, se vuelve a calcular.
    private var lastSignature = ""
    private var updatedAt: Date?

    private static let maxSuggestions = 16
    private static let perSeed = 4
    /// Con el mismo historial, se recalcula una vez por día (cuida el límite de Comic Vine).
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private struct Saved: Codable {
        var date: Date
        var signature: String
        var items: [Suggestion]
    }
    private static let cacheName = "inicio-para-vos.json"

    init() {
        if let saved: Saved = HomeCache.read(Self.cacheName), !saved.items.isEmpty {
            lastSignature = saved.signature
            updatedAt = saved.date
            state = .loaded(saved.items)
        }
    }

    func loadIfNeeded() async {
        guard !ComicVineKey.current.isEmpty else {
            if case .loaded = state { return }
            state = .noKey
            return
        }
        let library = RealLibrary.shared
        let liked = library.entries.values.filter { $0.weight > 0 }
        guard !liked.isEmpty else {
            state = .noHistory
            return
        }
        let signature = library.signature
        if refreshing { return }
        if case .loading = state { return }
        if signature == lastSignature, case .loaded = state,
           let updatedAt, Date().timeIntervalSince(updatedAt) < Self.maxAge { return }
        lastSignature = signature
        await load(Array(library.entries.values), signature: signature)
    }

    private func load(_ entries: [RealLibrary.Entry], signature: String) async {
        // Si ya hay sugerencias guardadas, se siguen viendo hasta que estén las nuevas.
        let keepOld: Bool
        if case .loaded(let old) = state, !old.isEmpty { keepOld = true } else { keepOld = false }
        refreshing = true
        defer { refreshing = false }
        if !keepOld { state = .loading }
        let client = ComicVineKey.client
        // No sugerimos series que ya tenés en tus listas.
        let mine = Set(entries.compactMap { $0.series?.id })

        // Puntaje de cada guionista y personaje: suma lo que te gustó y resta lo que no.
        var writerScore: [RealLibrary.Ref: Double] = [:]
        var characterScore: [RealLibrary.Ref: Double] = [:]
        var because: [RealLibrary.Ref: (title: String, weight: Double)] = [:]
        // Personas que figuran como guionistas en algún número (en las series no se sabe el rol).
        let knownWriters = Set(entries.filter { !$0.isSeries }.flatMap(\.writers))
        for entry in entries {
            for ref in entry.writers + entry.characters {
                if entry.writers.contains(ref) { writerScore[ref, default: 0] += entry.weight }
                if entry.characters.contains(ref) { characterScore[ref, default: 0] += entry.weight }
                if entry.weight > (because[ref]?.weight ?? 0) { because[ref] = (entry.title, entry.weight) }
            }
        }
        func best(_ scores: [RealLibrary.Ref: Double]) -> [RealLibrary.Ref] {
            scores.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
        }
        let seeds: [(ref: RealLibrary.Ref, isWriter: Bool)] =
            best(writerScore).map { (ref: $0, isWriter: true) } + best(characterScore).map { (ref: $0, isWriter: false) }

        var results: [Suggestion] = []
        var used = mine
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
                let reason = !seed.isWriter ? "Con \(seed.ref.name)"
                    : knownWriters.contains(seed.ref) ? "Del guion de \(seed.ref.name)" : "De \(seed.ref.name)"
                let source = because[seed.ref].map { " · porque te gustó \($0.title)" } ?? ""
                for pick in picks {
                    used.insert(pick.id)
                    let detail = try? await client.series(id: pick.id)
                    results.append(Suggestion(
                        id: pick.id,
                        name: detail?.name ?? pick.name ?? "Serie",
                        coverURL: detail?.image?.small,
                        reason: reason + source
                    ))
                    // Si no había nada guardado, se muestran a medida que llegan.
                    if !keepOld { state = .loaded(results) }
                }
            } catch {
                lastError = error
            }
        }

        if results.isEmpty, let lastError {
            if !keepOld { state = .failed(CVText.message(for: lastError)) }
        } else if results.isEmpty && keepOld {
            // Nada nuevo: quedan las guardadas.
        } else {
            state = .loaded(results)
            updatedAt = Date()
            HomeCache.write(Saved(date: Date(), signature: signature, items: results), Self.cacheName)
        }
    }

    func retry() async {
        lastSignature = ""
        updatedAt = nil
        state = .idle
        await loadIfNeeded()
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
                notice("Para sugerirte cómics, cargá tu clave de Comic Vine en Perfil → Configuración → Cuentas de Metron y Comic Vine.")
            case .noHistory:
                notice("Puntuá cómics o sumalos a Leyendo o Quiero leer desde su ficha (tocá uno en Recién salidos o usá Buscar cómics), y acá te vamos a sugerir otros parecidos.")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    notice(message)
                    Button("Probar de nuevo") { Task { await model.retry() } }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
            case .loaded(let items):
                if items.isEmpty {
                    notice("No encontré series parecidas todavía. Puntuá o sumá a tus listas algunos cómics más.")
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
