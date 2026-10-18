import Foundation
import Observation

// "Fuentes": catálogos de cómics que agregás vos con el link de un JSON.
// El JSON describe la fuente (nombre, versión, autor, licencia…) y trae la lista de cómics
// con links de descarga directos. El formato está explicado en FUENTES.md.
// La app NO trae fuentes incluidas: solo se usan fuentes con permiso para compartir esos cómics.
// La app no ejecuta programas de las fuentes: solo lee la lista y descarga los archivos.

// MARK: - Formato del JSON

struct SourceManifest: Decodable {
    let name: String
    let version: String?
    let description: String?
    let license: String?
    let author: String?
    let repository: String?
    let homepage: String?
    let comics: [SourceComic]

    enum CodingKeys: String, CodingKey {
        case name, version, description, license, author, repository, homepage, comics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        version = c.flexibleString(.version)
        description = try? c.decode(String.self, forKey: .description)
        license = try? c.decode(String.self, forKey: .license)
        // "author" puede ser un texto o {"name": ..., "email": ...}
        if let text = try? c.decode(String.self, forKey: .author) {
            author = text
        } else if let person = try? c.decode(Person.self, forKey: .author) {
            author = [person.name, person.email.map { "<\($0)>" }].compactMap { $0 }.joined(separator: " ")
        } else {
            author = nil
        }
        // "repository" puede ser un texto o {"type": "git", "url": ...}
        if let text = try? c.decode(String.self, forKey: .repository) {
            repository = text
        } else if let repo = try? c.decode(Repository.self, forKey: .repository) {
            repository = repo.url
        } else {
            repository = nil
        }
        homepage = try? c.decode(String.self, forKey: .homepage)
        // Los cómics que vengan mal armados (sin título o sin link) se saltean.
        let raw = (try? c.decode([Lenient<SourceComic>].self, forKey: .comics)) ?? []
        comics = raw.compactMap(\.value)
    }

    private struct Person: Decodable { let name: String?; let email: String? }
    private struct Repository: Decodable { let url: String? }
}

struct SourceComic: Decodable, Identifiable, Hashable {
    let title: String
    let series: String?
    let number: String?
    let year: String?
    let publisher: String?
    let cover: String?
    let download: String
    let format: String?
    let size: Int?

    var id: String { download }

    enum CodingKeys: String, CodingKey {
        case title, series, number, year, publisher, cover, download, format, size
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        download = try c.decode(String.self, forKey: .download)
        series = try? c.decode(String.self, forKey: .series)
        number = c.flexibleString(.number)
        year = c.flexibleString(.year)
        publisher = try? c.decode(String.self, forKey: .publisher)
        cover = try? c.decode(String.self, forKey: .cover)
        format = try? c.decode(String.self, forKey: .format)
        size = try? c.decode(Int.self, forKey: .size)
    }

    /// Para armar un cómic a mano (por ejemplo, desde una publicación de WordPress).
    init(title: String, download: String, format: String? = nil, year: String? = nil, cover: String? = nil) {
        self.title = title
        self.download = download
        self.format = format
        self.year = year
        self.cover = cover
        series = nil
        number = nil
        publisher = nil
        size = nil
    }

    var coverURL: URL? { cover.flatMap { URL(string: $0) } }

    /// Extensión del archivo: la de "format" o la del link.
    var fileExtension: String {
        let fromFormat = (format ?? "").lowercased()
        if ["cbz", "zip", "cbr", "pdf"].contains(fromFormat) { return fromFormat }
        let fromLink = (URL(string: download)?.pathExtension ?? "").lowercased()
        return ["cbz", "zip", "cbr", "pdf"].contains(fromLink) ? fromLink : "cbz"
    }

    /// Nombre para el archivo descargado, pensado para que se una solo con Comic Vine:
    /// "Serie 001 (1944)".
    var suggestedFileName: String {
        var parts: [String] = []
        if let series, !series.isEmpty {
            parts.append(series)
            if let number, !number.isEmpty { parts.append(number) }
        } else {
            parts.append(title)
        }
        if let year, !year.isEmpty { parts.append("(\(year))") }
        let name = parts.joined(separator: " ")
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
        return "\(name).\(fileExtension)"
    }
}

/// Decodifica sin fallar todo si un elemento viene mal.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    /// Acepta texto o número ("1944" o 1944).
    func flexibleString(_ key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(d) }
        return nil
    }
}

enum SourceError: LocalizedError {
    case badLink
    case notHTTPS
    case network(String)
    case badFormat(String)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .badLink: return "Ese link no parece válido."
        case .notHTTPS: return "El link tiene que empezar con https:// (conexión segura)."
        case .network(let why): return "No se pudo conectar. (\(why))"
        case .badFormat(let why): return "El JSON no tiene el formato de una fuente: \(why). Mirá FUENTES.md en el repositorio."
        case .server(let code): return "El servidor respondió con un error (código \(code))."
        }
    }
}

// MARK: - Fuentes guardadas

struct SavedSource: Identifiable {
    let url: String
    var manifest: SourceManifest
    /// El JSON tal cual vino, para guardarlo en el iPhone.
    var raw: Data
    let added: Double
    /// Versión nueva disponible en el servidor (si la hay).
    var availableVersion: String?
    var id: String { url }
}

@MainActor
@Observable
final class SourceStore {
    static let shared = SourceStore()

    private(set) var sources: [SavedSource] = []
    /// Avance de cada descarga (0 a 1), por link de descarga.
    private(set) var progress: [String: Double] = [:]
    /// Problemas de descarga, por link de descarga.
    private(set) var failures: [String: String] = [:]
    /// Links ya descargados a la Biblioteca.
    private(set) var downloaded: Set<String> = []

    private struct Stored: Codable {
        let url: String
        let raw: Data
        let added: Double
    }

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Fuentes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static var indexURL: URL { folder.appendingPathComponent("fuentes.json") }
    private static let downloadedKey = "sources.downloaded"

    private init() {
        if let data = try? Data(contentsOf: Self.indexURL),
           let list = try? JSONDecoder().decode([Stored].self, from: data) {
            sources = list.compactMap { stored in
                guard let manifest = try? JSONDecoder().decode(SourceManifest.self, from: stored.raw) else { return nil }
                return SavedSource(url: stored.url, manifest: manifest, raw: stored.raw, added: stored.added)
            }
        }
        downloaded = Set(UserDefaults.standard.stringArray(forKey: Self.downloadedKey) ?? [])
    }

    func source(_ url: String) -> SavedSource? { sources.first { $0.url == url } }

    /// Descarga y revisa el JSON de una fuente (sin guardarlo todavía).
    func fetch(_ link: String) async throws -> (manifest: SourceManifest, raw: Data) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else { throw SourceError.badLink }
        guard url.scheme?.lowercased() == "https" else { throw SourceError.notHTTPS }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let fetched: (Data, URLResponse)
        do {
            fetched = try await URLSession(configuration: .ephemeral).data(for: request)
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
        let (data, response) = fetched
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw SourceError.server(code)
        }
        do {
            let manifest = try JSONDecoder().decode(SourceManifest.self, from: data)
            return (manifest, data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw SourceError.badFormat("falta \"\(key.stringValue)\"")
        } catch {
            throw SourceError.badFormat("no se pudo leer")
        }
    }

    func add(link: String, manifest: SourceManifest, raw: Data) {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        sources.removeAll { $0.url == url }
        sources.append(SavedSource(url: url, manifest: manifest, raw: raw, added: Date().timeIntervalSince1970))
        save()
    }

    func remove(_ url: String) {
        sources.removeAll { $0.url == url }
        save()
    }

    /// Se fija si hay versiones nuevas de las fuentes guardadas.
    func checkForUpdates() async {
        for source in sources {
            guard let fresh = try? await fetch(source.url) else { continue }
            if let i = sources.firstIndex(where: { $0.url == source.url }) {
                let changed = fresh.manifest.version != sources[i].manifest.version || fresh.raw != sources[i].raw
                sources[i].availableVersion = changed ? (fresh.manifest.version ?? "nueva") : nil
            }
        }
    }

    /// Reemplaza la fuente guardada por la versión nueva del servidor.
    func update(_ url: String) async throws {
        let fresh = try await fetch(url)
        guard let i = sources.firstIndex(where: { $0.url == url }) else { return }
        sources[i].manifest = fresh.manifest
        sources[i].raw = fresh.raw
        sources[i].availableVersion = nil
        save()
    }

    private func save() {
        let list = sources.map { Stored(url: $0.url, raw: $0.raw, added: $0.added) }
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: Self.indexURL) }
    }

    // MARK: Descargas

    /// Descarga un cómic de una fuente y lo importa a la Biblioteca.
    func download(_ comic: SourceComic) async {
        let key = comic.download
        guard progress[key] == nil else { return }
        guard let url = URL(string: comic.download), url.scheme?.lowercased() == "https" else {
            failures[key] = SourceError.notHTTPS.errorDescription
            return
        }
        failures[key] = nil
        progress[key] = 0
        defer { progress[key] = nil }
        do {
            let file = try await FileDownloader(fileName: comic.suggestedFileName) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.progress[key] != nil else { return }
                    self.progress[key] = value
                }
            }.download(url)
            let problems = await LocalLibrary.shared.importFiles([file])
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            if problems.isEmpty {
                downloaded.insert(key)
                UserDefaults.standard.set(Array(downloaded), forKey: Self.downloadedKey)
            } else {
                failures[key] = problems.joined(separator: " ")
            }
        } catch {
            failures[key] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Descargador con avance

/// Baja un archivo informando el avance. Lo deja en una carpeta temporal con el nombre pedido.
final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private let fileName: String
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(fileName: String, onProgress: @escaping (Double) -> Void) {
        self.fileName = fileName
        self.onProgress = onProgress
    }

    func download(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { c in
            continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            continuation?.resume(throwing: SourceError.server(code))
            continuation = nil
            return
        }
        // El archivo temporal se borra al salir de esta función: lo movemos ya.
        // Si el nombre no dice bien qué es, lo averiguamos mirando los primeros bytes del archivo.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var name = fileName
        if let real = Self.detectExtension(location) {
            name = (fileName as NSString).deletingPathExtension + "." + real
        }
        let dest = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    /// "PK" = zip/cbz, "Rar!" = rar/cbr, "%PDF" = pdf. nil si no se reconoce.
    static func detectExtension(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count >= 4 else { return nil }
        let bytes = [UInt8](head)
        if bytes[0] == 0x50 && bytes[1] == 0x4B { return "cbz" }
        if bytes == [0x52, 0x61, 0x72, 0x21] { return "cbr" }
        if bytes == [0x25, 0x50, 0x44, 0x46] { return "pdf" }
        return nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: SourceError.network(error.localizedDescription))
            continuation = nil
        }
    }
}
