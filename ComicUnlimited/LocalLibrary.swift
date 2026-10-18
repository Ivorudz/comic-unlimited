import Foundation
import Observation
import UIKit

// Tus cómics en archivo (.cbz, .zip o PDF). Al importarlos, la app guarda una copia
// en su carpeta privada del iPhone, junto con una portada chiquita (la primera página).
// Son archivos tuyos: no se suben a ningún lado.

struct LocalComic: Codable, Identifiable, Hashable {
    let id: String
    /// Nombre sacado del archivo.
    var title: String
    let fileName: String
    var pageCount: Int
    let added: Double

    // Lectura
    var lastPage: Int?
    var finished: Bool?
    var lastOpened: Double?

    // Unión con Comic Vine
    var cvIssueID: Int?
    var cvSeriesID: Int?
    var cvTitle: String?
    var cvIssueName: String?
    var cvSeriesName: String?
    var cvSeriesYear: String?
    var cvIssueNumber: String?
    /// Fecha de publicación (fecha de tapa) según Comic Vine, por ejemplo "2004-08-01". "" = no se sabe.
    var cvCoverDate: String?
    /// Editorial según Comic Vine. "" = no se sabe.
    var cvPublisher: String?
    /// Arcos argumentales a los que pertenece. nil = todavía no se buscaron.
    var cvArcs: [ArcRef]?

    /// Nombre que le pusiste vos (si lo cambiaste).
    var customTitle: String?
    /// Año del paquete de donde salió (por ejemplo "Avengers Disassembled (2004).zip"),
    /// para elegir bien la ficha cuando el archivo no dice el año.
    var packYear: Int?

    /// El nombre que se muestra: el tuyo, o el de Comic Vine, o el del archivo.
    var displayTitle: String { customTitle ?? cvTitle ?? title }
    var isFinished: Bool { finished ?? false }
    var hasStarted: Bool { lastPage != nil }

    /// Nombre de la serie (de Comic Vine).
    var seriesName: String? {
        cvSeriesName ?? cvTitle.map { t in t.components(separatedBy: " #").first ?? t }
    }

    /// Número dentro de la serie (de Comic Vine).
    var issueNumber: String? {
        cvIssueNumber ?? cvTitle.flatMap { t in t.components(separatedBy: " #").dropFirst().first }
    }

    /// Para ordenar por número: 2 antes que 10, y 0.5 entre 0 y 1.
    var numberForSorting: Double { Double(issueNumber ?? "") ?? .greatestFiniteMagnitude }

    /// Fecha de publicación para ordenar, o nil si no se sabe.
    var publicationDate: String? {
        guard let d = cvCoverDate, !d.isEmpty else { return nil }
        return d
    }

    var readState: ReadState {
        if isFinished { return .finished }
        return hasStarted ? .reading : .unread
    }
}

/// Un arco argumental (por ejemplo "Avengers Disassembled").
struct ArcRef: Codable, Hashable {
    let id: Int
    let name: String
}

/// En qué punto de la lectura está un cómic.
enum ReadState: String, CaseIterable, Hashable, Identifiable {
    case unread, reading, finished

    var id: String { rawValue }
    var label: String {
        switch self {
        case .unread: return "Sin empezar"
        case .reading: return "Leyendo"
        case .finished: return "Leídos"
        }
    }
    var icon: String {
        switch self {
        case .unread: return "book.closed"
        case .reading: return "book"
        case .finished: return "checkmark.circle"
        }
    }
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

    /// Avisos de la última importación (por ejemplo, "Se agregaron 12 cómics de Pack.zip").
    var importNotices: [String] = []

    /// Importa archivos elegidos en la app Archivos. Devuelve los problemas que hubo (si hubo).
    /// Un .zip o .rar con cómics enteros adentro (un "paquete") se importa como varios cómics.
    func importFiles(_ urls: [URL]) async -> [String] {
        importing = true
        importNotices = []
        defer { importing = false }
        return await importBatch(urls, depth: 0, packYear: nil)
    }

    /// `depth`: cuántos paquetes hay "por encima" (un paquete adentro de otro). Hasta 2 niveles.
    private func importBatch(_ urls: [URL], depth: Int, packYear: Int?) async -> [String] {
        var problems: [String] = []

        for url in urls {
            let name = url.lastPathComponent
            var ext = url.pathExtension.lowercased()
            // Un .rar se trata igual que un .cbr (puede ser un cómic o un paquete de cómics).
            if ext == "rar" { ext = "cbr" }
            guard ["cbz", "zip", "cbr", "pdf"].contains(ext) else {
                problems.append("\(name): \(ArchiveError.notSupported.errorDescription ?? "")")
                continue
            }

            // Pedimos permiso para leer el archivo y hacemos una copia en la carpeta de la app.
            let id = UUID().uuidString
            let dest = Self.folder.appendingPathComponent("\(id).\(ext)")
            let access = url.startAccessingSecurityScopedResource()
            // Si el iPhone nos dio una copia temporal, la movemos (así no ocupa lugar dos veces).
            // Si es el archivo original, lo copiamos: nunca se toca el original.
            let isTemporaryCopy = url.standardizedFileURL.path
                .hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path)
            do {
                if isTemporaryCopy {
                    try FileManager.default.moveItem(at: url, to: dest)
                } else {
                    try FileManager.default.copyItem(at: url, to: dest)
                }
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                problems.append("\(name): no se pudo copiar el archivo.")
                continue
            }
            if access { url.stopAccessingSecurityScopedResource() }

            // Abrimos la copia (fuera de la pantalla, para que no se trabe) y sacamos la portada.
            // Si es un .cbr de tipo RAR, lo convertimos a .cbz (con libarchive, que viene en iOS).
            let result: Result<(pages: Int, cover: Data?, file: URL), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    var fileURL = dest
                    let file: ComicFile
                    do {
                        file = try ComicFile(url: dest)
                    } catch ArchiveError.rar {
                        let converted = dest.deletingPathExtension().appendingPathExtension("cbz")
                        do {
                            _ = try CbrConverter.convert(dest, to: converted)
                        } catch {
                            try? FileManager.default.removeItem(at: converted)
                            throw error
                        }
                        try? FileManager.default.removeItem(at: dest)
                        fileURL = converted
                        file = try ComicFile(url: converted)
                    }
                    let cover = file.page(0, maxWidth: 400)?.jpegData(compressionQuality: 0.8)
                    return .success((pages: file.pageCount, cover: cover, file: fileURL))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let info):
                let comic = LocalComic(
                    id: id,
                    title: Self.cleanTitle(url.deletingPathExtension().lastPathComponent),
                    fileName: info.file.lastPathComponent,
                    pageCount: info.pages,
                    added: Date().timeIntervalSince1970,
                    packYear: packYear
                )
                if let cover = info.cover { try? cover.write(to: coverURL(comic)) }
                items.insert(comic, at: 0)
                saveIndex()
                // Buscamos su ficha en Comic Vine sin hacer esperar.
                Task { await autoLink(comic.id) }
                if depth == 0 { importNotices.append("Se agregó \(name).") }
            case .failure(let error as ArchiveError) where [.noPages, .tooBig].contains(error) && ext != "pdf" && depth < 2:
                // Sin páginas: puede ser un paquete con cómics enteros adentro.
                // Si era un RAR, se borra el .cbz a medio convertir (nunca el paquete mismo).
                let converted = dest.deletingPathExtension().appendingPathExtension("cbz")
                if converted != dest { try? FileManager.default.removeItem(at: converted) }
                let pack: Result<(folder: URL, files: [URL]), Error> = await Task.detached(priority: .userInitiated) {
                    Result { try PackExtractor.extractComics(from: dest) }
                }.value
                try? FileManager.default.removeItem(at: dest)   // el paquete ya no hace falta
                switch pack {
                case .success(let found) where !found.files.isEmpty:
                    let before = items.count
                    let year = FileNameInfo(url.deletingPathExtension().lastPathComponent).year ?? packYear
                    problems += await importBatch(found.files, depth: depth + 1, packYear: year)
                    try? FileManager.default.removeItem(at: found.folder)
                    let added = items.count - before
                    if added > 0 { importNotices.append(added == 1 ? "Se agregó 1 cómic de \(name)."
                                                    : "Se agregaron \(added) cómics de \(name).") }
                case .success(let found):
                    try? FileManager.default.removeItem(at: found.folder)
                    problems.append("\(name): \(ArchiveError.noPages.errorDescription ?? "") Tampoco tiene cómics adentro.")
                case .failure(let error):
                    problems.append("\(name): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
            case .failure(let error):
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.removeItem(at: dest.deletingPathExtension().appendingPathExtension("cbz"))
                problems.append("\(name): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
        return problems
    }

    func item(_ id: String) -> LocalComic? { items.first { $0.id == id } }

    private func update(_ id: String, _ change: (inout LocalComic) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        saveIndex()
    }

    // MARK: Lectura

    /// Se llama al abrir el lector. Devuelve la página donde arrancar.
    func open(_ comic: LocalComic) -> Int {
        var start = 0
        update(comic.id) { c in
            c.lastOpened = Date().timeIntervalSince1970
            if c.isFinished {
                // Si ya lo terminaste, empieza de nuevo.
                c.finished = false
                c.lastPage = 0
            } else {
                c.lastPage = min(c.lastPage ?? 0, max(c.pageCount - 1, 0))
            }
            start = c.lastPage ?? 0
        }
        return start
    }

    func setPage(_ page: Int, for id: String) {
        update(id) { c in c.lastPage = max(0, min(page, c.pageCount - 1)) }
    }

    func markFinished(_ id: String) {
        update(id) { c in
            c.finished = true
            c.lastPage = c.pageCount - 1
        }
    }

    /// Lo que empezaste a leer, lo último primero (para "Seguir leyendo").
    var recentlyRead: [LocalComic] {
        items.filter(\.hasStarted).sorted { ($0.lastOpened ?? 0) > ($1.lastOpened ?? 0) }
    }

    // MARK: Comic Vine

    func link(_ id: String, series: CVVolumeSummary, issue: CVIssueSummary) {
        update(id) { c in
            c.cvIssueID = issue.id
            c.cvSeriesID = series.id
            c.cvTitle = CVText.issueTitle(series: series.name ?? c.title, number: issue.issueNumber)
            c.cvSeriesName = series.name
            c.cvSeriesYear = series.startYear
            c.cvIssueNumber = issue.issueNumber
            c.cvCoverDate = issue.coverDate ?? issue.storeDate ?? ""
            c.cvPublisher = series.publisher?.name
            c.cvArcs = nil
            let name = issue.name?.trimmingCharacters(in: .whitespaces) ?? ""
            c.cvIssueName = name.isEmpty ? nil : name
        }
        // Completa editorial y arcos sin hacer esperar.
        Task { await completeSeriesInfo() }
    }

    func unlink(_ id: String) {
        update(id) { c in
            c.cvIssueID = nil
            c.cvSeriesID = nil
            c.cvTitle = nil
            c.cvIssueName = nil
            c.cvSeriesName = nil
            c.cvSeriesYear = nil
            c.cvIssueNumber = nil
            c.cvCoverDate = nil
            c.cvPublisher = nil
            c.cvArcs = nil
        }
    }

    /// Cambia el nombre que se muestra. Vacío o nil vuelve al nombre original.
    func rename(_ id: String, to newTitle: String?) {
        let clean = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(id) { c in c.customTitle = clean.isEmpty ? nil : clean }
    }

    private var completing = false

    /// Los archivos unidos con versiones anteriores no tienen guardados el año de la serie
    /// ni la fecha de publicación: los busca en Comic Vine (pocas consultas por serie).
    func completeSeriesInfo() async {
        guard !ComicVineKey.current.isEmpty, !completing else { return }
        completing = true
        defer { completing = false }
        await completeSeriesYears()
        await completeCoverDates()
        await completeArcs()
    }

    /// Cuántos cómics faltan revisar para saber sus arcos (se muestra en Biblioteca → Arcos).
    private(set) var arcsPending = 0

    /// Busca los arcos de cada número (una consulta por cómic, de a una, para cuidar el límite).
    private func completeArcs() async {
        let pending = items.filter { $0.cvIssueID != nil && $0.cvArcs == nil }
        arcsPending = pending.count
        defer { arcsPending = 0 }
        for comic in pending {
            guard let issueID = comic.cvIssueID else { continue }
            guard let detail = try? await ComicVineKey.client.issue(id: issueID) else { break }
            let arcs = (detail.storyArcCredits ?? []).compactMap { ref in ref.name.map { ArcRef(id: ref.id, name: $0) } }
            update(comic.id) { c in c.cvArcs = arcs }
            arcsPending = max(arcsPending - 1, 0)
        }
    }

    private func completeSeriesYears() async {
        let missing = Set(items.filter { $0.cvSeriesID != nil && ($0.cvSeriesYear == nil || $0.cvPublisher == nil) }
            .compactMap(\.cvSeriesID))
        for seriesID in missing {
            guard let detail = try? await ComicVineKey.client.series(id: seriesID) else { continue }
            for comic in items where comic.cvSeriesID == seriesID {
                update(comic.id) { c in
                    c.cvSeriesName = detail.name ?? c.cvSeriesName
                    c.cvSeriesYear = detail.startYear ?? ""
                    c.cvPublisher = detail.publisher?.name ?? ""
                }
            }
        }
    }

    /// Busca la fecha de publicación de cada número revisando la lista de números de su serie.
    private func completeCoverDates() async {
        let pending = items.filter { $0.cvIssueID != nil && $0.cvCoverDate == nil }
        let bySeries = Dictionary(grouping: pending.filter { $0.cvSeriesID != nil }, by: { $0.cvSeriesID! })
        for (seriesID, comics) in bySeries {
            var wanted = Set(comics.compactMap(\.cvIssueID))
            var dates: [Int: String] = [:]
            var offset = 0
            // Como mucho 5 páginas de 100 números por serie, para cuidar el límite de Comic Vine.
            for _ in 0..<5 where !wanted.isEmpty {
                guard let page = try? await ComicVineKey.client.issues(ofSeries: seriesID, offset: offset, ascending: true)
                else { break }
                for issue in page.items where wanted.contains(issue.id) {
                    dates[issue.id] = issue.coverDate ?? issue.storeDate ?? ""
                    wanted.remove(issue.id)
                }
                offset += page.items.count
                if page.items.isEmpty || offset >= page.total { break }
            }
            for comic in comics {
                guard let issueID = comic.cvIssueID else { continue }
                update(comic.id) { c in c.cvCoverDate = dates[issueID] ?? "" }
            }
        }
    }

    /// Ids que se están buscando en Comic Vine ahora mismo.
    private(set) var matching: Set<String> = []

    /// Busca sola la ficha en Comic Vine a partir del nombre del archivo. Devuelve true si la encontró.
    @discardableResult
    func autoLink(_ id: String) async -> Bool {
        guard let comic = item(id), !ComicVineKey.current.isEmpty, !matching.contains(id) else { return false }
        matching.insert(id)
        defer { matching.remove(id) }
        var info = FileNameInfo(comic.title)
        if info.year == nil { info.year = comic.packYear }
        guard let found = try? await ComicVineMatcher.find(for: info) else { return false }
        link(id, series: found.series, issue: found.issue)
        return true
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
