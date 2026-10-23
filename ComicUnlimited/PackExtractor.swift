import Foundation

// Paquetes: un .zip o .rar que adentro no tiene páginas sino cómics enteros (.cbz, .cbr, .zip, .rar o PDF).
// Los saca de a uno a una carpeta temporal, para importarlos como cómics separados.
// Usa libarchive (viene dentro de iOS), que lee tanto .zip como RAR, y copia cada archivo
// por partes, sin cargarlo entero en memoria.

enum PackExtractor {
    static let comicExtensions: Set<String> = ["cbz", "cbr", "zip", "rar", "pdf"]

    /// Saca los cómics que hay adentro de `pack`. Devuelve la carpeta temporal y los archivos sacados
    /// (vacío si no había ningún cómic adentro).
    static func extractComics(from pack: URL) throws -> (folder: URL, files: [URL]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Paquete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let reader = archive_read_new() else { throw PackError.failed("no se pudo empezar") }
        defer { archive_read_free(reader) }
        archive_read_support_format_all(reader)
        archive_read_support_filter_all(reader)
        guard archive_read_open_filename(reader, pack.path, 1 << 16) == 0 else {
            throw PackError.failed(lastError(reader))
        }

        var files: [URL] = []
        var usedNames: Set<String> = []
        var entry: OpaquePointer?
        var buffer = [UInt8](repeating: 0, count: 1 << 16)

        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == 1 { break }                      // terminó
            if status < -20 { throw PackError.failed(lastError(reader)) }
            guard let entry else { break }

            let cName = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
            let name = cName.map { String(cString: $0) } ?? ""
            let file = (name as NSString).lastPathComponent
            let isComic = !name.hasSuffix("/")
                && !name.contains("__MACOSX")
                && !file.hasPrefix(".")
                && comicExtensions.contains((file as NSString).pathExtension.lowercased())
            guard isComic else {
                archive_read_data_skip(reader)
                continue
            }

            // Mismo nombre en dos carpetas distintas: al segundo le agregamos un número.
            var outName = file
            var n = 2
            while usedNames.contains(outName.lowercased()) {
                let base = (file as NSString).deletingPathExtension
                outName = "\(base) (\(n)).\((file as NSString).pathExtension)"
                n += 1
            }
            usedNames.insert(outName.lowercased())

            let out = folder.appendingPathComponent(outName)
            guard FileManager.default.createFile(atPath: out.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: out) else {
                throw PackError.failed("no se pudo guardar \(file)")
            }
            do {
                defer { try? handle.close() }
                while true {
                    let read = buffer.withUnsafeMutableBytes { raw in
                        archive_read_data(reader, raw.baseAddress, raw.count)
                    }
                    if read == 0 { break }
                    if read < 0 { throw PackError.failed(lastError(reader)) }
                    try handle.write(contentsOf: buffer[0..<read])
                }
            }
            files.append(out)
        }
        return (folder, files)
    }

    private static func lastError(_ reader: OpaquePointer) -> String {
        archive_error_string(reader).map { String(cString: $0) } ?? "error desconocido"
    }

    enum PackError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let why): return "No se pudieron sacar los cómics del paquete (\(why))."
            }
        }
    }
}
