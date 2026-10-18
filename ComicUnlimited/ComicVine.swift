import Foundation
import UIKit

// Conexión con Comic Vine (comicvine.gamespot.com), la base de datos de cómics
// que usamos para saber qué sale y cuándo. Uso personal y no comercial, como piden sus condiciones.
// Las portadas se cargan desde internet al momento de verlas: no se guardan en el iPhone.

/// Un cómic que va a salir, listo para mostrar en la pestaña Próximos.
struct UpcomingIssue: Identifiable, Hashable {
    let id: Int
    let series: String
    let number: String
    let issueName: String?
    let date: Date
    let coverURL: URL?
    let link: URL?
    let volumeID: Int?
    var publisher: String?

    var title: String { number.isEmpty ? series : "\(series) #\(number)" }
}

enum ComicVineError: LocalizedError {
    case invalidKey
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Comic Vine dice que la clave no es válida. Revisá que la hayas copiado completa."
        case .server(let message):
            return "Comic Vine respondió con un error: \(message)"
        case .network(let message):
            return "No se pudo conectar con Comic Vine. Revisá tu conexión a internet. (\(message))"
        }
    }
}

struct ComicVineClient {
    let apiKey: String

    private static let session = URLSession(configuration: .ephemeral)

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Cómics con fecha de salida en comiquerías entre `from` y `to` (incluidos).
    /// `onProgress` recibe lo que va llegando, para mostrarlo de a poco.
    func issues(from: Date, to: Date, onProgress: (@MainActor ([UpcomingIssue]) -> Void)? = nil) async throws -> [UpcomingIssue] {
        // Comic Vine no entiende bien los rangos de fechas, así que preguntamos día por día.
        var days: [Date] = []
        var day = Calendar.current.startOfDay(for: from)
        while day <= to {
            days.append(day)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        var all: [CVIssue] = []
        for date in days {
            var offset = 0
            // Como mucho 2 pedidos de 100 cómics por día, para no pasarnos del límite de Comic Vine.
            for _ in 0..<2 {
                let page: CVResponse<CVIssue> = try await request("issues", [
                    "filter": "store_date:\(Self.dayFormatter.string(from: date))",
                    "sort": "id:asc",
                    "field_list": "id,name,issue_number,store_date,image,site_detail_url,volume",
                    "limit": "100",
                    "offset": "\(offset)",
                ])
                all += page.results
                offset += 100
                if page.results.count < 100 || offset >= (page.numberOfTotalResults ?? 0) { break }
            }
            if let onProgress { await onProgress(convert(all)) }
        }

        return convert(all)
    }

    /// Pasa los datos de Comic Vine al formato de la app (sin repetidos ni cómics sin fecha).
    private func convert(_ all: [CVIssue]) -> [UpcomingIssue] {
        var seen = Set<Int>()
        return all.compactMap { issue in
            guard seen.insert(issue.id).inserted,
                  let dateText = issue.storeDate,
                  let date = Self.dayFormatter.date(from: dateText) else { return nil }
            return UpcomingIssue(
                id: issue.id,
                series: issue.volume?.name ?? "Sin título",
                number: issue.issueNumber ?? "",
                issueName: issue.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                date: date,
                coverURL: (issue.image?.smallUrl ?? issue.image?.thumbUrl).flatMap { URL(string: $0) },
                link: issue.siteDetailUrl.flatMap { URL(string: $0) },
                volumeID: issue.volume?.id,
                publisher: nil
            )
        }
    }

    /// Busca la editorial de cada serie. Si algo falla, devuelve lo que pudo (no es grave).
    func publishers(volumeIDs: [Int]) async -> [Int: String] {
        var result: [Int: String] = [:]
        let unique = Array(Set(volumeIDs)).sorted()
        var start = 0
        while start < unique.count {
            let chunk = unique[start..<min(start + 100, unique.count)]
            start += 100
            do {
                let page: CVResponse<CVVolume> = try await request("volumes", [
                    "filter": "id:" + chunk.map(String.init).joined(separator: "|"),
                    "field_list": "id,publisher",
                    "limit": "100",
                ])
                for volume in page.results {
                    if let name = volume.publisher?.name { result[volume.id] = name }
                }
            } catch {
                break
            }
        }
        return result
    }

    // MARK: Buscador y fichas

    /// Busca series (por ejemplo "Batman") por nombre.
    func searchSeries(_ query: String) async throws -> [CVVolumeSummary] {
        let page: CVResponse<CVVolumeSummary> = try await request("search", [
            "query": query,
            "resources": "volume",
            "field_list": "id,name,start_year,count_of_issues,publisher,image",
            "limit": "30",
        ], cached: true)
        return page.results
    }

    /// Ficha de una serie.
    func series(id: Int) async throws -> CVVolumeDetail {
        try await requestObject("volume/4050-\(id)", [
            "field_list": "id,name,start_year,count_of_issues,publisher,image,deck,description,site_detail_url,person_credits,character_credits",
        ])
    }

    /// Números de una serie, de a 100. Del más nuevo al más viejo, o al revés con `ascending`.
    func issues(ofSeries id: Int, offset: Int, ascending: Bool = false) async throws -> (items: [CVIssueSummary], total: Int) {
        let page: CVResponse<CVIssueSummary> = try await request("issues", [
            "filter": "volume:\(id)",
            "sort": ascending ? "cover_date:asc" : "cover_date:desc",
            "field_list": "id,name,issue_number,cover_date,store_date,image",
            "limit": "100",
            "offset": "\(offset)",
        ], cached: true)
        return (page.results, page.numberOfTotalResults ?? page.results.count)
    }

    /// Busca un número exacto dentro de una serie (por ejemplo, el #500 de Avengers).
    func findIssue(seriesID: Int, number: String) async throws -> CVIssueSummary? {
        let page: CVResponse<CVIssueSummary> = try await request("issues", [
            "filter": "volume:\(seriesID),issue_number:\(number)",
            "field_list": "id,name,issue_number,cover_date,store_date,image",
            "limit": "5",
        ], cached: true)
        return page.results.first
    }

    /// Ficha de un número.
    func issue(id: Int) async throws -> CVIssueDetail {
        try await requestObject("issue/4000-\(id)", [
            "field_list": "id,name,issue_number,cover_date,store_date,image,deck,description,person_credits,character_credits,story_arc_credits,volume,site_detail_url",
        ])
    }

    /// Series en las que trabajó una persona (guionista, dibujante…).
    func personSeries(id: Int) async throws -> [CVRef] {
        let person: CVCreditsDetail = try await requestObject("person/4040-\(id)", [
            "field_list": "id,name,volume_credits",
        ])
        return person.volumeCredits ?? []
    }

    /// Series en las que aparece un personaje.
    func characterSeries(id: Int) async throws -> [CVRef] {
        let character: CVCreditsDetail = try await requestObject("character/4005-\(id)", [
            "field_list": "id,name,volume_credits",
        ])
        return character.volumeCredits ?? []
    }

    // MARK: Pedidos a Comic Vine

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Respuestas ya pedidas, guardadas solo en memoria mientras la app está abierta,
    /// para no gastar consultas del límite por hora.
    private static let memory = NSCache<NSString, NSData>()

    private func request<T: Decodable>(_ resource: String, _ params: [String: String], cached: Bool = false) async throws -> CVResponse<T> {
        let data = try await fetch(resource, params, cached: cached)
        do {
            return try Self.decoder.decode(CVResponse<T>.self, from: data)
        } catch {
            throw ComicVineError.server("no se pudo leer la respuesta")
        }
    }

    private func requestObject<T: Decodable>(_ resource: String, _ params: [String: String]) async throws -> T {
        let data = try await fetch(resource, params, cached: true)
        guard let body = try? Self.decoder.decode(CVObjectResponse<T>.self, from: data),
              let result = body.results else {
            throw ComicVineError.server("no se encontró esa ficha")
        }
        return result
    }

    private func fetch(_ resource: String, _ params: [String: String], cached: Bool) async throws -> Data {
        var components = URLComponents(string: "https://comicvine.gamespot.com/api/\(resource)/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
        ] + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = components.url!
        let cacheKey = url.absoluteString as NSString
        if cached, let saved = Self.memory.object(forKey: cacheKey) {
            return saved as Data
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Comic Vine pide que cada app se identifique.
        request.setValue("ComicUnlimited/0.3 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")

        let fetched: (Data, URLResponse)
        do {
            fetched = try await Self.session.data(for: request)
        } catch {
            throw ComicVineError.network(error.localizedDescription)
        }
        let (data, response) = fetched

        guard let status = try? Self.decoder.decode(CVStatus.self, from: data) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw ComicVineError.invalidKey }
            throw ComicVineError.server("respuesta inesperada (código \(code))")
        }
        if status.statusCode == 100 { throw ComicVineError.invalidKey }
        if status.statusCode != 1 { throw ComicVineError.server(status.error ?? "error desconocido") }
        if cached { Self.memory.setObject(data as NSData, forKey: cacheKey) }
        return data
    }
}

// MARK: - Cómo vienen los datos de Comic Vine

struct CVResponse<T: Decodable>: Decodable {
    let error: String
    let statusCode: Int
    let numberOfTotalResults: Int?
    let results: [T]

    enum CodingKeys: String, CodingKey {
        case error, statusCode, numberOfTotalResults, results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = (try? c.decode(String.self, forKey: .error)) ?? "error desconocido"
        statusCode = try c.decode(Int.self, forKey: .statusCode)
        numberOfTotalResults = try? c.decode(Int.self, forKey: .numberOfTotalResults)
        // Cuando hay un error, Comic Vine a veces manda los resultados vacíos con otro formato.
        results = (try? c.decode([T].self, forKey: .results)) ?? []
    }
}

struct CVStatus: Decodable {
    let error: String?
    let statusCode: Int
}

/// Respuesta de Comic Vine cuando se pide una sola ficha.
struct CVObjectResponse<T: Decodable>: Decodable {
    let results: T?

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try? c.decode(T.self, forKey: .results)
    }
}

struct CVVolumeSummary: Decodable, Identifiable {
    let id: Int
    let name: String?
    let startYear: String?
    let countOfIssues: Int?
    let publisher: CVRef?
    let image: CVImage?
}

struct CVVolumeDetail: Decodable {
    let id: Int
    let name: String?
    let startYear: String?
    let countOfIssues: Int?
    let publisher: CVRef?
    let image: CVImage?
    let deck: String?
    let description: String?
    let siteDetailUrl: String?
    /// Personas que trabajaron en la serie, con cuántos números hicieron.
    let personCredits: [CVCountRef]?
    /// Personajes que aparecen, con en cuántos números.
    let characterCredits: [CVCountRef]?
}

/// Un nombre con un número de apariciones (Comic Vine a veces lo manda como texto).
struct CVCountRef: Decodable {
    let id: Int
    let name: String?
    let count: Int

    enum CodingKeys: String, CodingKey { case id, name, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        if let n = try? c.decode(Int.self, forKey: .count) {
            count = n
        } else if let text = try? c.decode(String.self, forKey: .count), let n = Int(text) {
            count = n
        } else {
            count = 0
        }
    }
}

struct CVIssueSummary: Decodable, Identifiable {
    let id: Int
    let name: String?
    let issueNumber: String?
    let coverDate: String?
    let storeDate: String?
    let image: CVImage?
}

struct CVIssueDetail: Decodable {
    let id: Int
    let name: String?
    let issueNumber: String?
    let coverDate: String?
    let storeDate: String?
    let image: CVImage?
    let deck: String?
    let description: String?
    let personCredits: [CVCredit]?
    let characterCredits: [CVRef]?
    let storyArcCredits: [CVRef]?
    let volume: CVRef?
    let siteDetailUrl: String?
}

struct CVCreditsDetail: Decodable {
    let id: Int
    let name: String?
    let volumeCredits: [CVRef]?
}

struct CVCredit: Decodable, Identifiable {
    let id: Int
    let name: String?
    let role: String?
}

struct CVIssue: Decodable {
    let id: Int
    let name: String?
    let issueNumber: String?
    let storeDate: String?
    let image: CVImage?
    let siteDetailUrl: String?
    let volume: CVRef?
}

struct CVImage: Decodable {
    let smallUrl: String?
    let thumbUrl: String?
    let mediumUrl: String?

    var small: URL? { (smallUrl ?? thumbUrl).flatMap { URL(string: $0) } }
    var medium: URL? { (mediumUrl ?? smallUrl).flatMap { URL(string: $0) } }
}

struct CVRef: Decodable {
    let id: Int
    let name: String?
}

struct CVVolume: Decodable {
    let id: Int
    let publisher: CVRef?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Portadas

/// Carga portadas desde internet y las guarda solo en la memoria mientras la app está abierta.
/// No se escriben en el iPhone.
final class CoverLoader {
    static let shared = CoverLoader()

    private let session = URLSession(configuration: .ephemeral)
    private let memory = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        var request = URLRequest(url: url)
        request.setValue("ComicUnlimited/0.3 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")
        guard let fetched = try? await session.data(for: request),
              let image = UIImage(data: fetched.0) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
