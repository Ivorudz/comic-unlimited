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
    func issues(from: Date, to: Date) async throws -> [UpcomingIssue] {
        let range = "\(Self.dayFormatter.string(from: from))|\(Self.dayFormatter.string(from: to))"
        var all: [CVIssue] = []
        var offset = 0
        // Como mucho 5 pedidos de 100 cómics, para no pasarnos del límite de Comic Vine.
        for _ in 0..<5 {
            let page: CVResponse<CVIssue> = try await request("issues", [
                "filter": "store_date:\(range)",
                "sort": "id:asc",
                "field_list": "id,name,issue_number,store_date,image,site_detail_url,volume",
                "limit": "100",
                "offset": "\(offset)",
            ])
            all += page.results
            offset += 100
            if page.results.count < 100 || offset >= (page.numberOfTotalResults ?? 0) { break }
        }

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

    private func request<T: Decodable>(_ resource: String, _ params: [String: String]) async throws -> CVResponse<T> {
        var components = URLComponents(string: "https://comicvine.gamespot.com/api/\(resource)/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
        ] + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        // Comic Vine pide que cada app se identifique.
        request.setValue("ComicUnlimited/0.1 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")

        let fetched: (Data, URLResponse)
        do {
            fetched = try await Self.session.data(for: request)
        } catch {
            throw ComicVineError.network(error.localizedDescription)
        }
        let (data, response) = fetched

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let body = try? decoder.decode(CVResponse<T>.self, from: data) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw ComicVineError.invalidKey }
            throw ComicVineError.server("respuesta inesperada (código \(code))")
        }
        if body.statusCode == 100 { throw ComicVineError.invalidKey }
        if body.statusCode != 1 { throw ComicVineError.server(body.error) }
        return body
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
        request.setValue("ComicUnlimited/0.1 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")
        guard let fetched = try? await session.data(for: request),
              let image = UIImage(data: fetched.0) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
