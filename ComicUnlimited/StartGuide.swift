import SwiftUI

// "¿No sabés por dónde empezar a leer?" (botón grande abajo de todo en Comunidad).
// - Tu nivel, puntos y medallas.
// - Rutas de lectura (Avengers, X-Men, Spider-Man, Batman, Liga de la Justicia) con el orden de CBRO:
//   GuideData.swift (datos y puntos) y GuideRouteViews.swift (pantallas de cada ruta).
// - "Si no sabés qué te gusta": recomendaciones sueltas.
// Todo es información (títulos, números, años, editoriales) con textos propios. Las tapas y fichas salen de
// Comic Vine al verlas (se guarda solo el código y el link de la tapa).

// MARK: - Pantalla principal de la guía

struct StartGuideView: View {
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let read = progress.readSet()
        let routes = RouteInfo.all.compactMap { info in GuideRoutesStore.route(info.id).map { RoutePair(info: info, route: $0) } }
        let total = routes.map { progress.score($0.route, read) }.reduce(GuideProgress.Score(), +)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Por dónde empezar")
                    .font(.system(size: 28, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.6)
                    .padding(.top, 8)
                Text("Elegí una ruta, un camino (esencial, con extras o con todo) y un punto de partida. Cada número que leas suma puntos.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                LevelCard(score: total)
                    .padding(.top, 16)

                SectionTitle("Rutas de lectura")
                VStack(spacing: 12) {
                    ForEach(routes) { pair in
                        NavigationLink(value: CommunityRoute.guideRoute(pair.info.id)) {
                            RouteCard(info: pair.info, route: pair.route, score: progress.score(pair.route, read),
                                      fraction: essentialFraction(pair.route, read),
                                      next: progress.next(pair.route, path: progress.path(pair.info.id), read: read))
                        }
                        .buttonStyle(.plain)
                    }
                }

                basics

                SectionTitle("Si no sabés qué te gusta")
                ForEach(StartGuide.picks) { group in
                    Text(group.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                        .padding(.bottom, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(group.picks) { pick in
                                NavigationLink(value: CommunityRoute.guideSeries(pick.query, pick.year, pick.title)) {
                                    PickCard(pick: pick)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                    .padding(.bottom, 18)
                }

                Text("Orden de lectura: Comic Book Reading Orders (CBRO), de la colección pública CBL-ReadingLists. Eras: Marvel Guides. Datos y tapas: Comic Vine; las tapas pertenecen a sus editoriales.")
                    .font(.caption2)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle("Empezar a leer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Cuánto de lo esencial de la ruta leíste (para la barrita).
    private func essentialFraction(_ route: RouteData, _ read: Set<Int>) -> Double {
        let essential = route.items.filter { !$0.isExtra }
        guard !essential.isEmpty else { return 0 }
        return Double(essential.filter { read.contains($0.cvID) }.count) / Double(essential.count)
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lo básico").font(.headline).foregroundStyle(Theme.ink)
            term("Número (#)", "Cada revista que sale, por ejemplo Batman #1 (unas 20 a 30 páginas).")
            term("Serie", "Todos los números de un título. Cuando vuelve a empezar desde el #1 es un \"volumen\" nuevo: por eso ves el año al lado del nombre.")
            term("Evento", "Una historia grande que cruza muchas series. En el camino \"Esencial\" está solo su centro; los cruces con otras series son extras.")
            term("Era", "Una época de la editorial (por ejemplo Marvel Disassembled o Los Nuevos 52). Completar lo esencial de una era da una medalla.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .padding(.top, 24)
    }

    private func term(_ name: String, _ text: String) -> some View {
        (Text(name + ": ").bold().foregroundColor(Theme.ink) + Text(text).foregroundColor(Theme.ink2))
            .font(.subheadline)
    }
}

private struct RoutePair: Identifiable {
    let info: RouteInfo
    let route: RouteData
    var id: String { info.id }
}

/// Tu nivel, tus puntos y tus medallas.
struct LevelCard: View {
    let score: GuideProgress.Score

    var body: some View {
        let level = GuideProgress.level(for: score.points)
        let fraction: Double = level.next.map { Double(score.points - level.from) / Double(max($0 - level.from, 1)) } ?? 1
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NIVEL \(level.index + 1)")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(level.name)
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(score.points)")
                        .font(.system(size: 30, weight: .black).monospacedDigit())
                        .foregroundStyle(Theme.yellow)
                    Text("puntos").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(Theme.yellow).frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 10)
            Text(level.next.map { "Te faltan \($0 - score.points) puntos para \(GuideProgress.levels[level.index + 1].name)" }
                 ?? "¡Llegaste al nivel más alto!")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 14) {
                stat("\(score.issues)", "números leídos", "book.fill")
                stat("\(score.medals)", "medallas", "medal.fill")
                stat("\(score.routesDone)", "rutas completas", "trophy.fill")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color(hex: 0xD1006C), Color(hex: 0x6B2FD6)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.ink, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.cyan).offset(x: 4, y: 4))
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.weight(.black).monospacedDigit()).foregroundStyle(.white)
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct RouteCard: View {
    let info: RouteInfo
    let route: RouteData
    let score: GuideProgress.Score
    let fraction: Double
    let next: RouteBlock?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: info.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(info.color, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(route.title).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(score.points) pts").font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.magenta)
                }
                Text("\(info.subtitle) · \(route.items.filter { !$0.isExtra }.count) esenciales").font(.caption).foregroundStyle(Theme.ink2).lineLimit(1)
                ProgressBar(value: fraction)
                Text(score.issues == 0
                     ? "Elegí por dónde empezar"
                     : next.map { "Seguí por: \($0.series.label) \($0.numbersText)" } ?? "¡Ruta completa!")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.ink2)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

private struct PickCard: View {
    let pick: GuidePick
    @State private var found: GuideLookup.Found?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: found?.cover.flatMap { URL(string: $0) })
            Text(pick.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            Text("\(String(pick.year)) · \(pick.publisher)").font(.caption).foregroundStyle(Theme.ink2).lineLimit(1)
            Text(pick.why).font(.caption).foregroundStyle(Theme.ink).lineLimit(4).multilineTextAlignment(.leading)
            if pick.adults {
                Text("Para adultos").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.magenta)
            }
        }
        .frame(width: 130)
        .task(id: pick.id) { found = await GuideResolver.shared.resolve(pick.query, pick.year) }
    }
}

// MARK: - Ficha de Comic Vine de cada serie (se busca una vez y se guarda el código)

enum GuideLookup {
    struct Found: Codable {
        let cvID: Int
        let name: String
        let cover: String?
    }

    private static let storeKey = "startGuide.found"

    static func key(_ query: String, _ year: Int) -> String { "\(query)|\(year)" }

    static func normalized(_ name: String) -> String {
        var text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if text.hasPrefix("the ") { text.removeFirst(4) }
        return text.replacingOccurrences(of: "&", with: "and").filter { $0.isLetter || $0.isNumber }
    }

    static func found(_ query: String, _ year: Int) -> Found? {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let all = try? JSONDecoder().decode([String: Found].self, from: data) else { return nil }
        return all[key(query, year)]
    }

    private static func remember(_ found: Found, _ query: String, _ year: Int) {
        var all: [String: Found] = [:]
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([String: Found].self, from: data) { all = saved }
        all[key(query, year)] = found
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: storeKey) }
    }

    /// Busca la serie en Comic Vine por nombre y año (1 consulta) y guarda su código y portada.
    static func resolve(_ query: String, _ year: Int) async throws -> Found? {
        if let found = found(query, year) { return found }
        guard !ComicVineKey.current.isEmpty else { return nil }
        let results = try await ComicVineKey.client.searchSeries(query)
        guard let best = best(results, query: query, year: year) else { return nil }
        let found = Found(cvID: best.id, name: best.name ?? query, cover: best.image?.small?.absoluteString)
        remember(found, query, year)
        return found
    }

    /// El resultado que mejor coincide: mismo nombre y año parecido.
    private static func best(_ results: [CVVolumeSummary], query: String, year: Int) -> CVVolumeSummary? {
        let target = GuideLookup.normalized(query)
        var bestScore = 0
        var best: CVVolumeSummary?
        for result in results {
            let name = GuideLookup.normalized(result.name ?? "")
            var score = 0
            if name == target { score += 10 } else if !name.isEmpty && (name.contains(target) || target.contains(name)) { score += 4 }
            if let start = Int(result.startYear ?? "") {
                let gap = abs(start - year)
                score += gap <= 1 ? 6 : (gap <= 3 ? 2 : 0)
            }
            score += min(result.countOfIssues ?? 0, 50) / 25
            if score > bestScore { bestScore = score; best = result }
        }
        return bestScore >= 8 ? best : nil
    }
}

/// Pide a Comic Vine las fichas de a una (sin apurar el límite de consultas).
actor GuideResolver {
    static let shared = GuideResolver()

    func resolve(_ query: String, _ year: Int) async -> GuideLookup.Found? {
        if let found = GuideLookup.found(query, year) { return found }
        try? await Task.sleep(for: .milliseconds(400))
        return try? await GuideLookup.resolve(query, year)
    }
}

// MARK: - Recomendaciones sueltas ("Si no sabés qué te gusta")

struct GuidePick: Identifiable, Hashable {
    let query: String
    let title: String
    let year: Int
    let publisher: String
    let why: String
    var adults = false
    var id: String { GuideLookup.key(query, year) }
}

struct PickGroup: Identifiable {
    let title: String
    let picks: [GuidePick]
    var id: String { title }
}

enum StartGuide {
    static let picks: [PickGroup] = [
        PickGroup(title: "Historias cerradas para tu primer cómic", picks: [
            GuidePick(query: "Batman: Year One", title: "Batman: Año Uno", year: 1987, publisher: "DC",
                      why: "El primer año de Batman. Corto, policial y perfecto para arrancar."),
            GuidePick(query: "All Star Superman", title: "All-Star Superman", year: 2006, publisher: "DC",
                      why: "Doce números que cuentan todo lo que hace grande a Superman."),
            GuidePick(query: "Ms. Marvel", title: "Ms. Marvel", year: 2014, publisher: "Marvel",
                      why: "Kamala Khan descubre sus poderes. Divertido y fácil de seguir."),
            GuidePick(query: "Hawkeye", title: "Hawkeye (Ojo de Halcón)", year: 2012, publisher: "Marvel",
                      why: "Lo que hace un Vengador en sus días libres. Humor y un dibujo original."),
        ]),
        PickGroup(title: "Terror", picks: [
            GuidePick(query: "Locke & Key: Welcome to Lovecraft", title: "Locke & Key", year: 2008, publisher: "IDW",
                      why: "Una casa llena de llaves mágicas. Terror y aventura."),
            GuidePick(query: "Something is Killing the Children", title: "Something is Killing the Children", year: 2019,
                      publisher: "BOOM! Studios", why: "Una cazadora de monstruos llega a un pueblo aterrado."),
            GuidePick(query: "Gideon Falls", title: "Gideon Falls", year: 2018, publisher: "Image",
                      why: "Un granero negro que aparece donde no debería."),
        ]),
        PickGroup(title: "Ciencia ficción y fantasía", picks: [
            GuidePick(query: "Saga", title: "Saga", year: 2012, publisher: "Image",
                      why: "Una familia escapando de una guerra entre planetas.", adults: true),
            GuidePick(query: "Paper Girls", title: "Paper Girls", year: 2015, publisher: "Image",
                      why: "Cuatro chicas de 1988 terminan viajando en el tiempo."),
            GuidePick(query: "Bone", title: "Bone", year: 1991, publisher: "Cartoon Books",
                      why: "Tres primos perdidos en un valle con dragones. Para todas las edades."),
            GuidePick(query: "The Sandman", title: "The Sandman", year: 1989, publisher: "DC (Vertigo)",
                      why: "El señor de los sueños y sus historias.", adults: true),
        ]),
        PickGroup(title: "Clásicos que todos nombran", picks: [
            GuidePick(query: "Watchmen", title: "Watchmen", year: 1986, publisher: "DC",
                      why: "Superhéroes en un mundo real y oscuro. Una historia cerrada.", adults: true),
            GuidePick(query: "El Eternauta", title: "El Eternauta", year: 1957, publisher: "Hora Cero",
                      why: "Una nevada mortal sobre Buenos Aires. El gran clásico argentino."),
            GuidePick(query: "Maus", title: "Maus", year: 1986, publisher: "Pantheon",
                      why: "La historia real del padre del autor en el Holocausto."),
        ]),
    ]
}


// MARK: - Ficha de una serie de la guía

/// Busca la serie en Comic Vine (una vez) y muestra su ficha.
struct GuideSeriesView: View {
    let query: String
    let year: Int
    let title: String
    @State private var found: GuideLookup.Found?
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if let found {
                SeriesView(id: found.cvID, name: found.name)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.title2.weight(.black)).foregroundStyle(Theme.ink)
                    Text("\(query) (\(String(year)))").font(.subheadline).foregroundStyle(Theme.ink2)
                    Text(errorText ?? "No encontré su ficha en Comic Vine. Probá buscarla con el buscador de Inicio.")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                    Spacer()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paper)
            }
        }
        .task {
            if ComicVineKey.current.isEmpty && GuideLookup.found(query, year) == nil {
                errorText = "Para ver la ficha, cargá tu clave de Comic Vine en Perfil → Configuración → Cuentas de Metron y Comic Vine."
            } else {
                do { found = try await GuideLookup.resolve(query, year) } catch {
                    errorText = CVText.message(for: error)
                }
            }
            loading = false
        }
    }
}
