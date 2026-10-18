import SwiftUI
import Observation

// "Recién salidos" en Inicio: cómics reales de los últimos 7 días, desde Comic Vine.
// Se carga una sola vez mientras la app está abierta, para cuidar el límite de consultas.

@MainActor
@Observable
final class DiscoverModel {
    enum Phase {
        case idle
        case noKey
        case loading
        case loaded([UpcomingIssue])
        case failed(String)
    }

    private(set) var state: Phase = .idle
    /// Cuántos cómics mostrar en la fila.
    private static let limit = 20

    /// Editoriales de cómics (no manga ni ediciones de otros países): solo se muestran estas.
    private static let known = ["marvel", "dc comics", "image", "dark horse", "idw", "boom",
                                "dynamite", "oni", "titan", "valiant", "mad cave", "ahoy", "vault", "archie",
                                "aftershock", "awa", "artists writers", "skybound", "top cow", "zenescope",
                                "black mask", "scout", "abstract studio", "humanoids", "fantagraphics",
                                "drawn & quarterly", "dstlry", "tko", "massive", "rebellion", "2000 ad",
                                "behemoth", "heavy metal", "source point", "bad idea", "magnetic", "first second"]

    func load() async {
        switch state {
        case .loading, .loaded: return
        default: break
        }
        guard !ComicVineKey.current.isEmpty else {
            state = .noKey
            return
        }
        state = .loading
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let to = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let client = ComicVineKey.client
        do {
            // No mostramos nada hasta saber la editorial de cada uno: así no se cuelan mangas.
            var issues = try await client.issues(from: from, to: to)
            let publishers = await client.publishers(volumeIDs: issues.compactMap(\.volumeID))
            for i in issues.indices {
                if let volume = issues[i].volumeID { issues[i].publisher = publishers[volume] }
            }
            state = .loaded(Self.pick(issues))
        } catch {
            state = .failed(CVText.message(for: error))
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    /// Elige qué mostrar: solo editoriales de cómics, primero los que tienen portada y los más nuevos.
    private static func pick(_ issues: [UpcomingIssue]) -> [UpcomingIssue] {
        func isComics(_ issue: UpcomingIssue) -> Bool {
            guard let p = issue.publisher?.lowercased() else { return false }
            return known.contains { p.hasPrefix($0) }
        }
        // Si Comic Vine no dijo ninguna editorial (falló esa consulta), mostramos todo.
        let candidates = issues.contains { $0.publisher != nil } ? issues.filter(isComics) : issues
        func rank(_ issue: UpcomingIssue) -> Int { issue.coverURL != nil ? 2 : 0 }
        let sorted = candidates.sorted {
            let a = rank($0), b = rank($1)
            return a != b ? a > b : $0.date > $1.date
        }
        return Array(sorted.prefix(limit))
    }
}

/// La fila deslizable de "Recién salidos".
struct RecentReleasesRow: View {
    let model: DiscoverModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Buscando en Comic Vine…").font(.subheadline).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .noKey:
                notice("Para ver cómics reales, cargá tu clave de Comic Vine en la pestaña Próximos (abajo de todo, en \"Cuentas de Metron y Comic Vine\").")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    notice(message)
                    Button("Probar de nuevo") { Task { await model.retry() } }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
            case .loaded(let issues):
                if issues.isEmpty {
                    notice("Comic Vine no tiene cómics cargados de la última semana.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(issues) { issue in
                                NavigationLink(value: CVRoute.issue(id: issue.id, title: issue.title)) {
                                    ReleaseCard(issue: issue)
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
        .task {
            if case .loaded = model.state { return }
            await model.load()
        }
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

/// Portada y título de un cómic real.
private struct ReleaseCard: View {
    let issue: UpcomingIssue

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d 'de' MMMM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: issue.coverURL)
            Text(issue.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            Text(issue.publisher ?? Self.day.string(from: issue.date))
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
        }
        .frame(width: 110)
    }
}
