import SwiftUI
import Observation

// Datos de las rutas de lectura de la guía (StartGuide.swift).
// El orden sale de las listas de Comic Book Reading Orders (CBRO) de la colección pública CBL-ReadingLists,
// guardadas dentro de la app en Guides/ruta-*.json (se generan con tools/rutas/armar_rutas.py).
// Cada número trae su código de Comic Vine, así que lo leído se cuenta exacto.
// Tipos de número: 1 = de una serie principal de la ruta, 2 = núcleo de un evento (los dos son "esenciales"),
// 0 = otra serie o cruce ("extra").

struct RouteSeries: Decodable {
    let name: String
    let volume: Int
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        volume = try c.decode(Int.self)
    }
    var label: String { volume > 0 ? "\(name) (\(volume))" : name }
}

struct RouteItem: Decodable {
    let cvID: Int
    let series: Int
    let number: String
    let kind: Int
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        cvID = try c.decode(Int.self)
        series = try c.decode(Int.self)
        number = try c.decode(String.self)
        kind = try c.decode(Int.self)
    }
    var isExtra: Bool { kind == 0 }
    var isEvent: Bool { kind == 2 }
}

struct RouteEra: Decodable {
    /// Nombre, años y desde qué posición empieza.
    let t: String
    let y: String
    let i: Int
}

struct RouteMark: Decodable {
    let i: Int
    let t: String
    /// "s" = buen lugar para empezar (un #1 de una serie principal), "e" = evento.
    let k: String
    var isStart: Bool { k == "s" }
}

struct RouteData: Decodable {
    let id: String
    let title: String
    let source: String
    let series: [RouteSeries]
    let items: [RouteItem]
    let stages: [RouteEra]
    let marks: [RouteMark]
}

/// Cómo se ve cada ruta (ícono y color) y en qué orden aparecen.
struct RouteInfo: Identifiable {
    let id: String
    let subtitle: String
    let icon: String
    let color: Color

    static let all: [RouteInfo] = [
        RouteInfo(id: "avengers", subtitle: "Marvel · los Vengadores", icon: "shield.lefthalf.filled", color: Color(hex: 0x2F6FDB)),
        RouteInfo(id: "xmen", subtitle: "Marvel · los mutantes", icon: "xmark.shield.fill", color: Color(hex: 0xE0A100)),
        RouteInfo(id: "spiderman", subtitle: "Marvel · el Hombre Araña", icon: "circle.hexagongrid.fill", color: Color(hex: 0xD62828)),
        RouteInfo(id: "batman", subtitle: "DC · el Caballero Oscuro", icon: "moon.stars.fill", color: Color(hex: 0x4B5160)),
        RouteInfo(id: "justiceleague", subtitle: "DC · la Liga de la Justicia", icon: "bolt.shield.fill", color: Color(hex: 0x0A8F5A)),
    ]
}

/// Los tres caminos de cada ruta.
enum RoutePath: String, CaseIterable, Identifiable {
    case essential, withExtras, everything
    var id: String { rawValue }
    var label: String {
        switch self {
        case .essential: return "Esencial"
        case .withExtras: return "+ Extras"
        case .everything: return "Con todo"
        }
    }
    var explanation: String {
        switch self {
        case .essential: return "Solo las series principales (con sus anuales) y el centro de cada evento."
        case .withExtras: return "Lo esencial, con las demás series y los cruces marcados como extras opcionales (valen el doble)."
        case .everything: return "Todo el orden de CBRO, con cada cruce en su lugar (los extras valen el doble)."
        }
    }
}

/// Un tramo de números seguidos de la misma serie (una "parada" del camino).
struct RouteBlock: Identifiable {
    let id: Int            // posición del primer número en la ruta
    let series: RouteSeries
    let indices: [Int]     // posiciones de sus números en la ruta
    let isExtra: Bool
    let isEvent: Bool
    let first: String
    let last: String

    var numbersText: String { first == last ? "#\(first)" : "#\(first)–\(last)" }
    var count: Int { indices.count }
}

enum GuideRoutesStore {
    private static var cache: [String: RouteData] = [:]

    static func route(_ id: String) -> RouteData? {
        if let found = cache[id] { return found }
        guard let url = Bundle.main.url(forResource: "ruta-\(id)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let route = try? JSONDecoder().decode(RouteData.self, from: data) else { return nil }
        cache[id] = route
        return route
    }

    /// Los tramos del camino elegido, desde `start`.
    static func blocks(_ route: RouteData, path: RoutePath, from start: Int = 0) -> [RouteBlock] {
        var result: [RouteBlock] = []
        var current: (series: Int, extra: Bool, event: Bool, indices: [Int])?
        func close() {
            guard let c = current, let firstIndex = c.indices.first, let lastIndex = c.indices.last else { return }
            result.append(RouteBlock(id: firstIndex, series: route.series[c.series], indices: c.indices,
                                     isExtra: c.extra, isEvent: c.event,
                                     first: route.items[firstIndex].number, last: route.items[lastIndex].number))
        }
        for index in max(start, 0)..<route.items.count {
            let item = route.items[index]
            if path == .essential && item.isExtra { continue }
            let extra = path != .essential && item.isExtra
            if let c = current, c.series == item.series, c.extra == extra {
                current?.indices.append(index)
            } else {
                close()
                current = (item.series, extra, item.isEvent, [index])
            }
        }
        close()
        return result
    }

    /// La era de una posición.
    static func era(_ route: RouteData, at index: Int) -> RouteEra? {
        route.stages.last { $0.i <= index }
    }
}

// MARK: - Progreso, puntos y punto de partida

@MainActor
@Observable
final class GuideProgress {
    static let shared = GuideProgress()

    static let pointsPerIssue = 10
    static let pointsPerExtra = 20
    static let pointsPerEra = 50
    static let pointsPerRoute = 300

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

    private struct Saved: Codable {
        /// Números marcados a mano como leídos (código de Comic Vine).
        var marked: Set<Int> = []
        /// Punto de partida de cada ruta (posición en la ruta).
        var starts: [String: Int] = [:]
        /// Camino y forma de ver elegidos en cada ruta.
        var paths: [String: String] = [:]
        var formats: [String: String] = [:]
    }

    private var saved = Saved()
    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("guia-progreso.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let loaded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = loaded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: Self.file, options: .atomic) }
    }

    // MARK: Preferencias de cada ruta

    func start(_ routeID: String) -> Int { saved.starts[routeID] ?? 0 }
    func setStart(_ index: Int, for routeID: String) { saved.starts[routeID] = index; save() }

    func path(_ routeID: String) -> RoutePath { saved.paths[routeID].flatMap { RoutePath(rawValue: $0) } ?? .essential }
    func setPath(_ path: RoutePath, for routeID: String) { saved.paths[routeID] = path.rawValue; save() }

    func showsWay(_ routeID: String) -> Bool { saved.formats[routeID] != "bloques" }
    func setShowsWay(_ way: Bool, for routeID: String) { saved.formats[routeID] = way ? "camino" : "bloques"; save() }

    // MARK: Leídos

    /// Lo que leíste: tus archivos terminados (y los números de tus TPB terminados) + lo marcado a mano.
    func readSet() -> Set<Int> {
        var set = saved.marked
        for comic in LocalLibrary.shared.items where comic.isFinished {
            if let cv = comic.cvIssueID { set.insert(cv) }
            for issue in comic.contents ?? [] { set.insert(issue.cvID) }
        }
        return set
    }

    func isMarked(_ cvID: Int) -> Bool { saved.marked.contains(cvID) }

    /// Marca (o desmarca, si ya estaban todos marcados) estos números.
    func toggle(_ ids: [Int]) {
        let read = readSet()
        if ids.allSatisfy({ read.contains($0) }) {
            for id in ids { saved.marked.remove(id) }
        } else {
            for id in ids { saved.marked.insert(id) }
        }
        save()
    }

    // MARK: Puntos

    struct Score {
        var points = 0
        var issues = 0
        var medals = 0
        var eras = 0
        var routesDone = 0
        static func + (a: Score, b: Score) -> Score {
            Score(points: a.points + b.points, issues: a.issues + b.issues, medals: a.medals + b.medals,
                  eras: a.eras + b.eras, routesDone: a.routesDone + b.routesDone)
        }
    }

    /// Puntos de una ruta: 10 por número esencial leído, 20 por extra, +50 por era completa (lo esencial)
    /// y +300 si leíste todo lo esencial.
    func score(_ route: RouteData, _ read: Set<Int>) -> Score {
        var score = Score()
        var eraTotal = Array(repeating: 0, count: route.stages.count)
        var eraRead = Array(repeating: 0, count: route.stages.count)
        var era = 0
        for (index, item) in route.items.enumerated() {
            while era + 1 < route.stages.count && route.stages[era + 1].i <= index { era += 1 }
            let done = read.contains(item.cvID)
            if done {
                score.issues += 1
                score.points += item.isExtra ? Self.pointsPerExtra : Self.pointsPerIssue
            }
            if !item.isExtra {
                eraTotal[era] += 1
                if done { eraRead[era] += 1 }
            }
        }
        let erasWithIssues = eraTotal.filter { $0 > 0 }.count
        score.eras = erasWithIssues
        score.medals = zip(eraTotal, eraRead).filter { $0.0 > 0 && $0.0 == $0.1 }.count
        score.points += score.medals * Self.pointsPerEra
        if erasWithIssues > 0 && score.medals == erasWithIssues {
            score.routesDone = 1
            score.points += Self.pointsPerRoute
        }
        return score
    }

    func total(_ read: Set<Int>) -> Score {
        RouteInfo.all.compactMap { GuideRoutesStore.route($0.id) }.map { score($0, read) }.reduce(Score(), +)
    }

    static func level(for points: Int) -> (index: Int, name: String, from: Int, next: Int?) {
        let index = levels.lastIndex { points >= $0.points } ?? 0
        let next = index + 1 < levels.count ? levels[index + 1].points : nil
        return (index, levels[index].name, levels[index].points, next)
    }

    /// El próximo tramo para leer en el camino elegido (desde tu punto de partida).
    func next(_ route: RouteData, path: RoutePath, read: Set<Int>) -> RouteBlock? {
        let blocks = GuideRoutesStore.blocks(route, path: path, from: start(route.id))
        return blocks.first { block in
            // En "+ Extras", los extras son opcionales: no frenan el "seguí por acá".
            if path == .withExtras && block.isExtra { return false }
            return block.indices.contains { !read.contains(route.items[$0].cvID) }
        }
    }

    /// Para el lector: cuántos puntos da este cómic y en qué rutas.
    func reward(for comic: LocalComic) -> (points: Int, routes: [String])? {
        let ids = Set([comic.cvIssueID].compactMap { $0 } + (comic.contents ?? []).map(\.cvID))
        guard !ids.isEmpty else { return nil }
        var points = 0
        var names: [String] = []
        for info in RouteInfo.all {
            guard let route = GuideRoutesStore.route(info.id) else { continue }
            let matches = route.items.filter { ids.contains($0.cvID) }
            guard !matches.isEmpty else { continue }
            names.append(route.title)
            points += matches.reduce(0) { $0 + ($1.isExtra ? Self.pointsPerExtra : Self.pointsPerIssue) }
        }
        return names.isEmpty ? nil : (points, names)
    }
}

// MARK: - Tapas (links de Comic Vine, de a 100 por consulta)

@MainActor
@Observable
final class GuideCovers {
    static let shared = GuideCovers()
    private(set) var links: [Int: String] = [:]
    private var pending: Set<Int> = []
    private var asked: Set<Int> = []
    private var scheduled = false

    private static let file: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("guia-tapas.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([Int: String].self, from: data) {
            links = saved
        }
    }

    func url(_ cvID: Int) -> URL? { links[cvID].flatMap { URL(string: $0) } }

    /// Pide la tapa de este número (se juntan los pedidos y se hacen de a 100).
    func want(_ cvID: Int) {
        guard links[cvID] == nil, !asked.contains(cvID), !ComicVineKey.current.isEmpty else { return }
        pending.insert(cvID)
        guard !scheduled else { return }
        scheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await flush()
        }
    }

    private func flush() async {
        scheduled = false
        let ids = Array(pending.prefix(100))
        pending.subtract(ids)
        asked.formUnion(ids)
        guard !ids.isEmpty else { return }
        if let found = try? await ComicVineKey.client.issues(ids: ids) {
            for issue in found {
                if let link = issue.image?.small?.absoluteString { links[issue.id] = link }
            }
            if let data = try? JSONEncoder().encode(links) { try? data.write(to: Self.file, options: .atomic) }
        }
        if !pending.isEmpty {
            scheduled = true
            try? await Task.sleep(for: .milliseconds(600))
            await flush()
        }
    }
}
