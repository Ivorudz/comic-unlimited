import SwiftUI
import Observation

// "¿No sabés por dónde empezar a leer?" (botón grande abajo de todo en Comunidad).
// - Rutas de lectura (GuideRoutes.swift): Avengers, X-Men, Spider-Man, Batman y Liga de la Justicia,
//   con etapas en orden, los tomos de cada una y "Empezá por acá".
// - Juego de puntos: cada número que leés de una ruta suma 10 puntos (se cuentan solos los cómics de tu
//   Biblioteca que terminaste, o marcás un tomo como leído). Completar una etapa da una medalla y 50 puntos;
//   completar una ruta, 300. Con los puntos subís de nivel.
// - "Si no sabés qué te gusta": recomendaciones sueltas por tema.
// Todo es información (títulos, años, autores, editoriales) con textos propios. Las portadas y fichas salen
// de Comic Vine: cada serie se busca una vez por nombre y año y se guarda solo su código y el link de la portada.

// MARK: - Progreso y puntos

@MainActor
@Observable
final class GuideProgress {
    static let shared = GuideProgress()
    private static let manualKey = "guide.manualBooks"

    /// Tomos marcados a mano como leídos.
    private(set) var manual: Set<String>

    static let pointsPerIssue = 10
    static let pointsPerStage = 50
    static let pointsPerRoute = 300

    /// Niveles: desde cuántos puntos.
    static let levels: [(points: Int, name: String)] = [
        (0, "Lector curioso"),
        (100, "Aprendiz de comiquería"),
        (300, "Lector de grapas"),
        (600, "Coleccionista"),
        (1000, "Experto en continuidad"),
        (1600, "Maestro de los crossovers"),
        (2500, "Guardián del multiverso"),
        (4000, "Leyenda de los cómics"),
    ]

    private init() {
        manual = Set(UserDefaults.standard.stringArray(forKey: Self.manualKey) ?? [])
    }

    func isMarked(_ book: GuideBook) -> Bool { manual.contains(book.id) }

    func toggle(_ book: GuideBook) {
        if manual.contains(book.id) { manual.remove(book.id) } else { manual.insert(book.id) }
        UserDefaults.standard.set(Array(manual), forKey: Self.manualKey)
    }

    // MARK: Lo que leíste (tus archivos terminados)

    /// Números terminados de tu Biblioteca, por serie (nombre normalizado) → (año de la serie, número).
    struct Finished {
        var bySeries: [String: [(year: Int?, number: Double)]] = [:]
    }

    static func normalized(_ name: String) -> String {
        var text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if text.hasPrefix("the ") { text.removeFirst(4) }
        return text.replacingOccurrences(of: "&", with: "and").filter { $0.isLetter || $0.isNumber }
    }

    func finished() -> Finished {
        var result = Finished()
        for comic in LocalLibrary.shared.items where comic.isFinished {
            guard let series = comic.cvSeriesName, let number = comic.cvIssueNumber.flatMap(Double.init) else { continue }
            result.bySeries[Self.normalized(series), default: []]
                .append((year: comic.cvSeriesYear.flatMap { Int($0) }, number: number))
        }
        return result
    }

    /// Cuántos números de ese tomo leíste.
    func read(_ book: GuideBook, _ finished: Finished) -> Int {
        if let count = book.issueCount, manual.contains(book.id) { return count }
        let list = finished.bySeries[Self.normalized(book.series)] ?? []
        let numbers = Set(list.filter { item in
            guard let year = item.year, abs(year - book.year) <= 1 else { return false }
            return item.number >= book.first && item.number <= (book.last ?? .greatestFiniteMagnitude)
        }.map { $0.number })
        return book.issueCount.map { min(numbers.count, $0) } ?? numbers.count
    }

    func isDone(_ book: GuideBook, _ finished: Finished) -> Bool {
        guard let count = book.issueCount else { return false }   // las series en curso no terminan
        return read(book, finished) >= count
    }

    func stageDone(_ stage: GuideStage, _ finished: Finished) -> Bool {
        let closed = stage.books.filter { $0.issueCount != nil }
        return !closed.isEmpty && closed.allSatisfy { isDone($0, finished) }
    }

    struct Score {
        var points = 0
        var issues = 0
        var stagesDone = 0
        var stages = 0
        var routesDone = 0

        static func + (a: Score, b: Score) -> Score {
            Score(points: a.points + b.points, issues: a.issues + b.issues, stagesDone: a.stagesDone + b.stagesDone,
                  stages: a.stages + b.stages, routesDone: a.routesDone + b.routesDone)
        }
    }

    func score(_ route: GuideRoute, _ finished: Finished) -> Score {
        var score = Score()
        for stage in route.stages {
            score.stages += 1
            for book in stage.books { score.issues += read(book, finished) }
            if stageDone(stage, finished) { score.stagesDone += 1 }
        }
        let done = score.stagesDone == route.stages.count
        if done { score.routesDone = 1 }
        score.points = score.issues * Self.pointsPerIssue + score.stagesDone * Self.pointsPerStage
            + (done ? Self.pointsPerRoute : 0)
        return score
    }

    func total(_ finished: Finished) -> Score {
        GuideRoutes.all.map { score($0, finished) }.reduce(Score(), +)
    }

    static func level(for points: Int) -> (index: Int, name: String, from: Int, next: Int?) {
        let index = levels.lastIndex { points >= $0.points } ?? 0
        let next = index + 1 < levels.count ? levels[index + 1].points : nil
        return (index, levels[index].name, levels[index].points, next)
    }

    /// Qué sigue en la ruta: si no empezaste, el primer "Empezá por acá"; si no, el primer tomo sin terminar
    /// después del último que tocaste.
    func next(in route: GuideRoute, _ finished: Finished) -> (stage: GuideStage, book: GuideBook)? {
        let all = route.stages.flatMap { stage in stage.books.map { (stage: stage, book: $0) } }
        guard let lastTouched = all.lastIndex(where: { read($0.book, finished) > 0 }) else {
            let start = route.stages.first { $0.start } ?? route.stages.first
            return start.flatMap { stage in stage.books.first.map { (stage: stage, book: $0) } }
        }
        let current = all[lastTouched]
        if !isDone(current.book, finished) { return current }
        return all[(lastTouched + 1)...].first { !isDone($0.book, finished) }
    }

    /// Para el lector: ¿este cómic suma puntos en alguna ruta?
    func routes(for comic: LocalComic) -> [GuideRoute] {
        guard let series = comic.cvSeriesName, let number = comic.cvIssueNumber.flatMap(Double.init),
              let year = comic.cvSeriesYear.flatMap({ Int($0) }) else { return [] }
        let name = Self.normalized(series)
        return GuideRoutes.all.filter { route in
            route.stages.contains { stage in
                stage.books.contains { book in
                    Self.normalized(book.series) == name && abs(book.year - year) <= 1
                        && number >= book.first && number <= (book.last ?? .greatestFiniteMagnitude)
                }
            }
        }
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
        let target = GuideProgress.normalized(query)
        var bestScore = 0
        var best: CVVolumeSummary?
        for result in results {
            let name = GuideProgress.normalized(result.name ?? "")
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

// MARK: - Pantalla principal de la guía

struct StartGuideView: View {
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let finished = progress.finished()
        let total = progress.total(finished)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Por dónde empezar")
                    .font(.system(size: 28, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.6)
                    .padding(.top, 8)
                Text("Elegí una ruta, empezá donde dice \"Empezá por acá\" y seguí las etapas en orden. Cada número que leas suma puntos.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                LevelCard(score: total)
                    .padding(.top, 16)

                SectionTitle("Rutas de lectura")
                VStack(spacing: 12) {
                    ForEach(GuideRoutes.all) { route in
                        NavigationLink(value: CommunityRoute.guideRoute(route.id)) {
                            RouteCard(route: route, score: progress.score(route, finished),
                                      next: progress.next(in: route, finished)?.book)
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

                Text("Datos y portadas: Comic Vine. Las portadas pertenecen a sus editoriales. Las rutas, recomendaciones y textos son de Cómic Unlimited.")
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

    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lo básico").font(.headline).foregroundStyle(Theme.ink)
            term("Número (#)", "Cada revista que sale, por ejemplo Batman #1 (unas 20 a 30 páginas).")
            term("Serie", "Todos los números de un título. Cuando vuelve a empezar desde el #1 es un \"volumen\" nuevo: por eso ves el año al lado del nombre.")
            term("Tomo", "Un libro que junta varios números, casi siempre una historia completa. En la guía cada tomo dice qué números trae.")
            term("Evento", "Una historia grande que cruza muchas series. Para el orden exacto, buscalo en Biblioteca → Listas → Subir lista .cbl → Buscar en la colección.")
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
                stat("\(score.stagesDone)", "medallas", "medal.fill")
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
    let route: GuideRoute
    let score: GuideProgress.Score
    let next: GuideBook?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: route.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(route.color, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(route.title).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(score.points) pts").font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.magenta)
                }
                Text(route.subtitle).font(.caption).foregroundStyle(Theme.ink2).lineLimit(1)
                ProgressBar(value: Double(score.stagesDone) / Double(max(score.stages, 1)))
                Text(score.issues == 0
                     ? "Empezá: \(next?.title ?? route.stages.first?.title ?? "")"
                     : next.map { "Seguí por: \($0.title)" } ?? "¡Ruta completa!")
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

// MARK: - Una ruta

struct GuideRouteView: View {
    let routeID: String
    private var progress: GuideProgress { GuideProgress.shared }
    @State private var banner: String?
    @State private var celebrate = 0

    var body: some View {
        if let route = GuideRoutes.route(routeID) {
            content(route)
        } else {
            Text("Esta ruta ya no existe.").foregroundStyle(Theme.ink2)
        }
    }

    private func content(_ route: GuideRoute) -> some View {
        let finished = progress.finished()
        let score = progress.score(route, finished)
        let next = progress.next(in: route, finished)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: route.icon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(route.color, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.title).font(.system(size: 26, weight: .black).width(.expanded)).foregroundStyle(Theme.ink)
                        Text("\(score.points) puntos · \(score.stagesDone) de \(score.stages) etapas")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.magenta)
                    }
                }
                .padding(.top, 8)
                ProgressBar(value: Double(score.stagesDone) / Double(max(score.stages, 1)))
                    .padding(.top, 12)

                if let next {
                    NextUpCard(stage: next.stage, book: next.book, started: score.issues > 0,
                               read: progress.read(next.book, finished), color: route.color) {
                        mark(next.book, in: route)
                    }
                    .padding(.top, 16)
                } else {
                    Label("¡Completaste toda la ruta! +\(GuideProgress.pointsPerRoute) puntos", systemImage: "trophy.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.magenta)
                        .padding(.top, 16)
                }

                SectionTitle("Etapas")
                ForEach(route.stages.indices, id: \.self) { index in
                    StageRow(stage: route.stages[index], number: index + 1,
                             isLast: index == route.stages.count - 1,
                             finished: finished, color: route.color,
                             isNext: next?.stage.id == route.stages[index].id) { book in
                        mark(book, in: route)
                    }
                }

                Text("Cada número que terminás en el lector suma \(GuideProgress.pointsPerIssue) puntos solo (si su ficha de Comic Vine es de la serie de la ruta). Si lo leíste en otro lado, marcá el tomo como leído. Cada etapa completa da una medalla (+\(GuideProgress.pointsPerStage)).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .overlay(alignment: .top) {
            if let banner {
                Text(banner)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.yellow, in: Capsule())
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: celebrate)
    }

    /// Marca o desmarca un tomo y festeja lo que ganaste.
    private func mark(_ book: GuideBook, in route: GuideRoute) {
        let before = progress.score(route, progress.finished())
        let levelBefore = GuideProgress.level(for: progress.total(progress.finished()).points).index
        progress.toggle(book)
        let finished = progress.finished()
        let after = progress.score(route, finished)
        let gained = after.points - before.points
        guard gained > 0 else { return }
        var text = "+\(gained) puntos"
        if after.stagesDone > before.stagesDone { text = "¡Etapa completada! 🏅 " + text }
        if after.routesDone > before.routesDone { text = "¡Ruta completa! 🏆 " + text }
        let levelAfter = GuideProgress.level(for: progress.total(finished).points)
        if levelAfter.index > levelBefore { text += "\nSubiste a: \(levelAfter.name)" }
        celebrate += 1
        withAnimation(.spring(duration: 0.35)) { banner = text }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.3)) { if banner == text { banner = nil } }
        }
    }
}

/// "Seguí por acá": el próximo tomo de la ruta.
private struct NextUpCard: View {
    let stage: GuideStage
    let book: GuideBook
    let started: Bool
    let read: Int
    let color: Color
    let onMark: () -> Void
    @State private var found: GuideLookup.Found?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: CommunityRoute.guideSeries(book.series, book.year, book.title)) {
                RemoteCover(url: found?.cover.flatMap { URL(string: $0) }).frame(width: 72)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text(started ? "SEGUÍ POR ACÁ" : "EMPEZÁ POR ACÁ")
                    .font(.caption.weight(.heavy)).tracking(1).foregroundStyle(color)
                Text(book.title).font(.headline.weight(.heavy)).foregroundStyle(Theme.ink)
                Text("\(book.series) (\(String(book.year))) \(book.numbersText) · \(stage.title)")
                    .font(.caption).foregroundStyle(Theme.ink2)
                if let count = book.issueCount {
                    Text("Leíste \(read) de \(count) · vale \(count * GuideProgress.pointsPerIssue) puntos")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                HStack(spacing: 10) {
                    NavigationLink(value: CommunityRoute.guideSeries(book.series, book.year, book.title)) {
                        Text("Ver la serie").font(.subheadline.weight(.bold)).foregroundStyle(Theme.magenta)
                    }
                    if book.issueCount != nil {
                        Button(action: onMark) {
                            Text("Ya lo leí").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color, lineWidth: 2))
        .task(id: book.id) { found = await GuideResolver.shared.resolve(book.series, book.year) }
    }
}

/// Una etapa de la ruta, como en una línea de tiempo.
private struct StageRow: View {
    let stage: GuideStage
    let number: Int
    let isLast: Bool
    let finished: GuideProgress.Finished
    let color: Color
    let isNext: Bool
    let onMark: (GuideBook) -> Void
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let done = progress.stageDone(stage, finished)
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? color : Theme.card)
                    Circle().stroke(done || isNext ? color : Theme.line, lineWidth: 3)
                    if done {
                        Image(systemName: "medal.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.caption.weight(.heavy)).foregroundStyle(isNext ? color : Theme.ink2)
                    }
                }
                .frame(width: 32, height: 32)
                if !isLast {
                    Rectangle().fill(done ? color : Theme.line).frame(width: 3).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(stage.title).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink)
                    if stage.start {
                        Text("Empezá por acá")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Theme.magenta, in: Capsule())
                    }
                }
                Text(stage.years).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink2)
                Text(stage.text).font(.subheadline).foregroundStyle(Theme.ink)
                ForEach(stage.books) { book in
                    BookRow(book: book, read: progress.read(book, finished), marked: progress.isMarked(book),
                            color: color) { onMark(book) }
                }
            }
            .padding(.bottom, 22)
        }
    }
}

private struct BookRow: View {
    let book: GuideBook
    let read: Int
    let marked: Bool
    let color: Color
    let onMark: () -> Void

    var body: some View {
        let done = book.issueCount.map { read >= $0 } ?? false
        HStack(spacing: 10) {
            NavigationLink(value: CommunityRoute.guideSeries(book.series, book.year, book.title)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("\(book.series) (\(String(book.year))) \(book.numbersText)")
                        .font(.caption).foregroundStyle(Theme.ink2)
                    if let note = book.note {
                        Text(note).font(.caption2).foregroundStyle(Theme.ink2)
                    }
                    if let count = book.issueCount {
                        Text(done ? "Leído ✓ · +\(count * GuideProgress.pointsPerIssue)"
                             : read > 0 ? "Leíste \(read) de \(count)" : "\(count) \(count == 1 ? "número" : "números") · +\(count * GuideProgress.pointsPerIssue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(done ? color : Theme.ink2)
                    } else {
                        Text(read > 0 ? "En curso · leíste \(read) · +\(read * GuideProgress.pointsPerIssue)"
                             : "Serie en curso · suma \(GuideProgress.pointsPerIssue) por número")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if book.issueCount != nil {
                Button(action: onMark) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundStyle(done ? color : Theme.ink2)
                }
                .buttonStyle(.plain)
                .disabled(done && !marked)   // leído solo con tus archivos: no se desmarca
                .accessibilityLabel(done ? "Leído" : "Marcar como leído")
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(done ? color.opacity(0.6) : Theme.line))
    }
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
