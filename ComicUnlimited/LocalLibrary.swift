import Foundation
import Observation
import UIKit

// Tus cómics en archivo (.cbz, .zip o PDF). Al importarlos, la app guarda una copia
// en su carpeta privada del iPhone, junto con una portada chiquita (la primera página).
// Son archivos tuyos: no se suben a ningún lado.

struct LocalComic: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let fileName: String
    var pageCount: Int
    let added: Double
}

@MainActor
@Observable
final class LocalLibrary {
    static let shared = LocalLibrary()

    private(set) var items: [LocalComic] = []
    /// true mientras se están importando archivos.
    private(set) var importing = false

    /// Carpeta privada de la app donde se guardan los archivos.
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Biblioteca", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static var indexURL: URL { folder.appendingPathComponent("biblioteca.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.indexURL),
           let list = try? JSONDecoder().decode([LocalComic].self, from: data) {
            items = list
        }
    }

    func fileURL(_ comic: LocalComic) -> URL { Self.folder.appendingPathComponent(comic.fileName) }
    func coverURL(_ comic: LocalComic) -> URL { Self.folder.appendingPathComponent("\(comic.id)-portada.jpg") }

    /// Importa archivos elegidos en la app Archivos. Devuelve los problemas que hubo (si hubo).
    func importFiles(_ urls: [URL]) async -> [String] {
        importing = true
        defer { importing = false }
        var problems: [String] = []

        for url in urls {
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard ["cbz", "zip", "pdf"].contains(ext) else {
                problems.append("\(name): \(ArchiveError.notSupported.errorDescription ?? "")")
                continue
            }

            // Pedimos permiso para leer el archivo y hacemos una copia en la carpeta de la app.
            let id = UUID().uuidString
            let dest = Self.folder.appendingPathComponent("\(id).\(ext)")
            let access = url.startAccessingSecurityScopedResource()
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                problems.append("\(name): no se pudo copiar el archivo.")
                continue
            }
            if access { url.stopAccessingSecurityScopedResource() }

            // Abrimos la copia (fuera de la pantalla, para que no se trabe) y sacamos la portada.
            let result: Result<(pages: Int, cover: Data?), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let file = try ComicFile(url: dest)
                    let cover = file.page(0, maxWidth: 400)?.jpegData(compressionQuality: 0.8)
                    return .success((pages: file.pageCount, cover: cover))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let info):
                let comic = LocalComic(
                    id: id,
                    title: Self.cleanTitle(url.deletingPathExtension().lastPathComponent),
                    fileName: dest.lastPathComponent,
                    pageCount: info.pages,
                    added: Date().timeIntervalSince1970
                )
                if let cover = info.cover { try? cover.write(to: coverURL(comic)) }
                items.insert(comic, at: 0)
                saveIndex()
            case .failure(let error):
                try? FileManager.default.removeItem(at: dest)
                problems.append("\(name): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
        return problems
    }

    func delete(_ comic: LocalComic) {
        try? FileManager.default.removeItem(at: fileURL(comic))
        try? FileManager.default.removeItem(at: coverURL(comic))
        items.removeAll { $0.id == comic.id }
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.indexURL)
        }
    }

    /// "Batman_001_(2016)" → "Batman 001 (2016)"
    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
