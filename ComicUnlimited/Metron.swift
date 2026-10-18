import Foundation

// Conexión con Metron (metron.cloud), una base de datos de cómics hecha por la comunidad.
// La usamos en Próximos porque permite pedir "lo que sale entre tal y tal fecha" y filtrar por editorial.
// Uso personal y no comercial. Límite de Metron: unas 20 consultas por minuto y 5.000 por día.

/// Usuario y contraseña de Metron, guardados solo en este iPhone.
enum MetronAccount {
    private static let userKey = "metron.user"
    private static let passwordKey = "metron.password"

    static var user: String { UserDefaults.standard.string(forKey: userKey) ?? "" }
    static var password: String { UserDefaults.standard.string(forKey: passwordKey) ?? "" }
    static var isSet: Bool { !user.isEmpty && !password.isEmpty }

    static func save(user: String, password: String) {
        UserDefaults.standard.set(user.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userKey)
        UserDefaults.standard.set(password, forKey: passwordKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
    }
}

enum MetronError: LocalizedError {
    case badLogin
    case tooManyRequests
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badLogin:
            return "Metron dice que el usuario o la contraseña no son correctos."
        case .tooManyRequests:
            return "Hicimos demasiadas consultas a Metron. Esperá un minuto y probá de nuevo."
        case .server(let message):
            return "Metron respondió con un error: \(message)"
        case .network(let message):
            return "No se pudo conectar con Metron. (\(message))"
        }
    }
}

struct MetronClient {
    let user: String
    let password: String

    private static let session = URLSession(configuration: .ephemeral)

    /// Editoriales que se pueden elegir en Próximos: (texto del botón, nombre para Metron).
    static let publishers: [(label: String, query: String)] = [
        ("Marvel", "marvel"),
        ("DC", "dc comics"),
        ("Image", "image"),
        ("Dark Horse", "dark horse"),
        ("IDW", "idw"),
        ("BOOM!", "boom"),
        ("Dynamite", "dynamite"),
    ]

    /// Cómics que salen en comiquerías entre `from` y `to`. Si se pasa `publisher`, solo de esa editorial.
    func issues(from: Date, to: Date, publisher: String?, maxPages: Int = 6,
                onProgress: (@MainActor ([UpcomingIssue]) -> Void)? = nil) async throws -> [UpcomingIssue] {
        let day = ComicVineClient.dayFormatter
        var components = URLComponents(string: "https://metron.cloud/api/issue/")!
        var items = [
            URLQueryItem(name: "store_date_range_after", value: day.string(from: from)),
            URLQueryItem(name: "store_date_range_before", value: day.string(from: to)),
        ]
        if let publisher { items.append(URLQueryItem(name: "publisher_name", value: publisher)) }
        components.queryItems = items

        var next: URL? = components.url
        var all: [MetronIssue] = []
        // Un máximo de páginas, para cuidar el límite de Metron.
        var pages = 0
        while let url = next, pages < maxPages {
            let page: MetronPage = try await get(url)
            all += page.results
            next = page.next.flatMap { URL(string: $0) }
            pages += 1
            if let onProgress { await onProgress(convert(all)) }
        }

        return convert(all)
    }

    /// Pasa los datos de Metron al formato de la app (sin repetidos ni cómics sin fecha).
    private func convert(_ all: [MetronIssue]) -> [UpcomingIssue] {
        let day = ComicVineClient.dayFormatter
        var seen = Set<Int>()
        return all.compactMap { issue in
            guard seen.insert(issue.id).inserted,
                  let text = issue.storeDate,
                  let date = day.date(from: text) else { return nil }
            var series = issue.series?.name ?? "Sin título"
            if let volume = issue.series?.volume, volume > 1 { series += " (vol. \(volume))" }
            return UpcomingIssue(
                id: issue.id,
                series: series,
                number: issue.number ?? "",
                issueName: nil,
                date: date,
                coverURL: issue.image.flatMap { URL(string: $0) },
                link: nil,
                volumeID: nil,
                publisher: nil
            )
        }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let login = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ComicUnlimited/0.4 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")

        let fetched: (Data, URLResponse)
        do {
            fetched = try await Self.session.data(for: request)
        } catch {
            throw MetronError.network(error.localizedDescription)
        }
        let (data, response) = fetched
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401, 403: throw MetronError.badLogin
        case 429: throw MetronError.tooManyRequests
        default: throw MetronError.server("código \(code)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MetronError.server("no se pudo leer la respuesta")
        }
    }
}

// MARK: - Cómo vienen los datos de Metron

struct MetronPage: Decodable {
    let count: Int?
    let next: String?
    let results: [MetronIssue]
}

struct MetronIssue: Decodable {
    let id: Int
    let series: MetronSeries?
    let number: String?
    let issue: String?
    let storeDate: String?
    let image: String?
}

struct MetronSeries: Decodable {
    let name: String?
    let volume: Int?
}
