import SwiftUI
import Observation

// "Recién salidos" en Inicio: cómics de los últimos 7 días, desde Comic Vine, y las categorías
// de abajo de "Para vos" (salen de la misma lista, sin consultas de más).
// Lo último que se cargó queda guardado en el iPhone (solo los datos y el link de cada portada,
// nunca las imágenes): al abrir la app se muestra enseguida y después se actualiza.

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
    /// Todos los cómics de la semana (solo editoriales de cómics), para las categorías.
    private(set) var all: [UpcomingIssue] = []
    /// Cuándo se trajo la lista que se ve.
    private(set) var updatedAt: Date?
    /// Se está actualizando por detrás (mientras tanto se ve lo guardado).
    private(set) var refreshing = false
    /// Ya se actualizó desde que se abrió la app.
    private var refreshedThisLaunch = false

    /// Cuántos cómics mostrar en cada fila.
    static let limit = 20
    /// No se vuelve a preguntar a Comic Vine si lo guardado tiene menos de esto (cuida el límite de consultas).
    private static let minAge: TimeInterval = 30 * 60

    private struct Saved: Codable {
        var date: Date
        var issues: [UpcomingIssue]
    }
    private static let cacheName = "inicio-recien-salidos.json"

    init() {
        if let saved: Saved = HomeCache.read(Self.cacheName) {
            all = saved.issues
            updatedAt = saved.date
            state = .loaded(Self.pick(saved.issues))
        }
    }

    /// Al abrir la app: muestra lo guardado y lo actualiza una vez.
    func load() async {
        guard !ComicVineKey.current.isEmpty else {
            if case .loaded = state { return }
            state = .noKey
            return
        }
        if refreshing { return }
        if case .loaded = state, refreshedThisLaunch { return }
        await refresh()
    }

    /// Al volver a la app después de un rato: actualiza si lo guardado es viejo.
    func refreshIfStale() async {
        guard !ComicVineKey.current.isEmpty, !refreshing else { return }
        if let updatedAt, Date().timeIntervalSince(updatedAt) < 3 * 60 * 60 { return }
        await refresh()
    }

    private func refresh() async {
        refreshedThisLaunch = true
        let hasData: Bool
        if case .loaded = state { hasData = true } else { hasData = false }
        if hasData, let updatedAt, Date().timeIntervalSince(updatedAt) < Self.minAge { return }
        refreshing = true
        defer { refreshing = false }
        if !hasData { state = .loading }
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
            let comics = ComicPublishers.onlyComics(issues)
            all = comics
            updatedAt = Date()
            state = .loaded(Self.pick(comics))
            HomeCache.write(Saved(date: Date(), issues: comics), Self.cacheName)
        } catch {
            // Si ya había algo guardado, se sigue mostrando.
            if !hasData { state = .failed(CVText.message(for: error)) }
        }
    }

    func retry() async {
        refreshedThisLaunch = false
        updatedAt = nil
        await load()
    }

    /// Ordena para mostrar: primero los que tienen portada y los más nuevos.
    static func sorted(_ issues: [UpcomingIssue]) -> [UpcomingIssue] {
        func rank(_ issue: UpcomingIssue) -> Int { issue.coverURL != nil ? 2 : 0 }
        return issues.sorted {
            let a = rank($0), b = rank($1)
            return a != b ? a > b : $0.date > $1.date
        }
    }

    private static func pick(_ issues: [UpcomingIssue]) -> [UpcomingIssue] {
        Array(sorted(issues).prefix(limit))
    }

    // MARK: Categorías

    struct Category: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let issues: [UpcomingIssue]
    }

    private func category(_ id: String, _ title: String, _ subtitle: String, _ issues: [UpcomingIssue]) -> Category? {
        issues.isEmpty ? nil : Category(id: id, title: title, subtitle: subtitle,
                                        issues: Array(Self.sorted(issues).prefix(Self.limit)))
    }

    /// Filas de abajo de "Para vos" (antes de los géneros): de tus series y series nuevas (#1).
    var topCategories: [Category] {
        guard !all.isEmpty else { return [] }
        var result: [Category] = []
        func add(_ id: String, _ title: String, _ subtitle: String, _ issues: [UpcomingIssue]) {
            if let c = category(id, title, subtitle, issues) { result.append(c) }
        }

        let mySeries = Set(RealLibrary.shared.entries.values.compactMap { $0.series?.id })
        add("mias", "De tus series", "Números nuevos de series de tus listas",
            all.filter { issue in issue.volumeID.map { mySeries.contains($0) } ?? false })

        let firsts = all.filter { ["1", "1.0", "01", "001"].contains($0.number.trimmingCharacters(in: .whitespaces)) }
        if firsts.count >= 2 {
            add("nuevas", "Series nuevas", "Números #1 de la última semana", firsts)
        }
        return result
    }

    /// Filas por editorial (las que más sacaron esta semana, como mucho 4) y el resto junto.
    var publisherCategories: [Category] {
        guard !all.isEmpty else { return [] }
        var result: [Category] = []
        let byPublisher = Dictionary(grouping: all) { $0.publisher ?? "" }
        let top = byPublisher.filter { !$0.key.isEmpty && $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
        for (publisher, issues) in top {
            if let c = category("ed-\(publisher)", ComicPublishers.displayName(publisher),
                                "Editorial · \(issues.count) cómics de la semana", issues) { result.append(c) }
        }
        let shown = Set(top.map { $0.key })
        let others = all.filter { !shown.contains($0.publisher ?? "") }
        if others.count >= 3, let c = category("otras", "Otras editoriales",
                                                "Independientes y editoriales más chicas", others) {
            result.append(c)
        }
        return result
    }
}

/// Lo último que se cargó en Inicio, guardado en el iPhone (en la carpeta de archivos temporales
/// que el sistema puede limpiar). Solo texto y links: las portadas se siguen cargando de internet.
enum HomeCache {
    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
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
                notice("Para ver cómics, cargá tu clave de Comic Vine en Perfil → Configuración → Cuentas de Metron y Comic Vine.")
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
                    IssueCardsRow(issues: issues)
                }
            }
        }
        .task { await model.load() }
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

/// Fila deslizable de cómics (portada, título y editorial). Tocar uno abre su ficha
/// (la de Comic Vine; si viene de Metron, la de Metron, que pasa sola a Comic Vine si la tiene).
struct IssueCardsRow: View {
    let issues: [UpcomingIssue]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(issues) { issue in
                    Group {
                        if let metronID = issue.metronID {
                            NavigationLink(value: LibraryRoute.metronIssue(metronID)) { ReleaseCard(issue: issue) }
                        } else {
                            NavigationLink(value: CVRoute.issue(id: issue.id, title: issue.title)) { ReleaseCard(issue: issue) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }
}

/// Más filas de Descubrir, abajo de "Para vos": de tus series, series nuevas, géneros (terror,
/// superhéroes…) y editoriales. Todo es parte de Descubrir (sin otro título).
struct DiscoverMoreRows: View {
    let model: DiscoverModel
    let genres: GenreModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.topCategories) { row($0) }
            GenreRows(model: genres)
            ForEach(model.publisherCategories) { row($0) }
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func row(_ category: DiscoverModel.Category) -> some View {
        DiscoverRowTitle(title: category.title, subtitle: category.subtitle)
        IssueCardsRow(issues: category.issues)
            .padding(.bottom, 22)
    }
}

/// Título y subtítulo de una fila de Descubrir.
struct DiscoverRowTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(.bottom, 10)
    }
}

/// Portada y título de un cómic.
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

/// Editoriales de cómics (no manga ni ediciones de otros países). Se usa en Inicio y en Próximos.
enum ComicPublishers {
    static let known = ["marvel", "dc comics", "image", "dark horse", "idw", "boom",
                                "dynamite", "oni", "titan", "valiant", "mad cave", "ahoy", "vault", "archie",
                                "aftershock", "awa", "artists writers", "skybound", "top cow", "zenescope",
                                "black mask", "scout", "abstract studio", "humanoids", "fantagraphics",
                                "drawn & quarterly", "dstlry", "tko", "massive", "rebellion", "2000 ad",
                                "behemoth", "heavy metal", "source point", "bad idea", "magnetic", "first second"]

    /// Nombre completo para mostrar ("Image" → "Image Comics").
    static func displayName(_ publisher: String) -> String {
        switch publisher.lowercased() {
        case "image": return "Image Comics"
        case "marvel": return "Marvel Comics"
        case "boom", "boom!": return "BOOM! Studios"
        case "idw": return "IDW Publishing"
        case "dark horse": return "Dark Horse Comics"
        default: return publisher
        }
    }

    static func isComics(_ publisher: String?) -> Bool {
        guard let p = publisher?.lowercased() else { return false }
        return known.contains { p.hasPrefix($0) }
    }

    /// Deja solo los de editoriales de cómics. Si Comic Vine no dijo ninguna editorial
    /// (falló esa consulta), no filtra, para no dejar la lista vacía.
    static func onlyComics(_ issues: [UpcomingIssue]) -> [UpcomingIssue] {
        issues.contains { $0.publisher != nil } ? issues.filter { isComics($0.publisher) } : issues
    }
}
