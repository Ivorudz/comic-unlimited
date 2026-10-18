import Foundation
import Compression
import PDFKit
import UIKit

// Abre cómics en archivo (.cbz, .zip o PDF) y saca sus páginas como imágenes.
// Un .cbz es un .zip con las páginas adentro. El iPhone no trae una herramienta pública para abrir .zip,
// así que acá hay un lector chiquito hecho a mano, usando solo lo que Apple incluye (Compression).
// No usa programas de terceros.

enum ArchiveError: LocalizedError {
    case notSupported
    case notZip
    case tooBig
    case damaged
    case encrypted
    case noPages
    case badPDF
    case rar

    var errorDescription: String? {
        switch self {
        case .notSupported: return "Ese tipo de archivo no se puede abrir. Usá .cbz, .zip o PDF."
        case .notZip: return "No parece un .cbz o .zip válido."
        case .tooBig: return "El archivo es demasiado grande para abrirlo (más de 4 GB)."
        case .damaged: return "El archivo parece dañado."
        case .encrypted: return "El archivo tiene contraseña y no se puede abrir."
        case .noPages: return "No encontré páginas (imágenes) adentro del archivo."
        case .badPDF: return "No se pudo abrir el PDF."
        case .rar: return "Este .cbr está comprimido como RAR, y la app no puede abrir RAR. Podés convertirlo a .cbz con otra app y volver a importarlo."
        }
    }
}

// MARK: - Lector de .zip / .cbz

struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        // "Mapeado": el archivo no se carga entero en memoria, se lee a medida que hace falta.
        data = try Data(contentsOf: url, options: .alwaysMapped)
        entries = try Self.readDirectory(data)
    }

    /// Saca el contenido de un archivo de adentro del .zip.
    func extract(_ entry: Entry) throws -> Data {
        let d = data
        let o = entry.localHeaderOffset
        guard entry.flags & 0x1 == 0 else { throw ArchiveError.encrypted }
        guard o >= 0, o + 30 <= d.count, Self.u32(d, o) == 0x0403_4b50 else { throw ArchiveError.damaged }
        let start = o + 30 + Int(Self.u16(d, o + 26)) + Int(Self.u16(d, o + 28))
        guard start + entry.compressedSize <= d.count else { throw ArchiveError.damaged }
        let raw = d.subdata(in: (d.startIndex + start) ..< (d.startIndex + start + entry.compressedSize))

        switch entry.method {
        case 0: // sin comprimir
            return raw
        case 8: // comprimido (deflate)
            guard entry.uncompressedSize > 0 else { return Data() }
            var out = Data(count: entry.uncompressedSize)
            let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                    guard let output = dst.bindMemory(to: UInt8.self).baseAddress,
                          let input = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(output, entry.uncompressedSize, input, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.uncompressedSize else { throw ArchiveError.damaged }
            return out
        default:
            throw ArchiveError.damaged
        }
    }

    private static func readDirectory(_ d: Data) throws -> [Entry] {
        let n = d.count
        guard n >= 22 else { throw ArchiveError.notZip }

        // Buscamos el "índice" del .zip, que está al final del archivo.
        var eocd = -1
        var i = n - 22
        let lowest = max(0, n - 22 - 65_535)
        while i >= lowest {
            if u32(d, i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ArchiveError.notZip }

        let count = Int(u16(d, eocd + 10))
        let offset = Int(u32(d, eocd + 16))
        if count == 0xFFFF || offset == 0xFFFF_FFFF { throw ArchiveError.tooBig }

        var entries: [Entry] = []
        var p = offset
        for _ in 0..<count {
            guard p + 46 <= n, u32(d, p) == 0x0201_4b50 else { throw ArchiveError.damaged }
            let flags = u16(d, p + 8)
            let method = u16(d, p + 10)
            let compressed = Int(u32(d, p + 20))
            let uncompressed = Int(u32(d, p + 24))
            let nameLength = Int(u16(d, p + 28))
            let extraLength = Int(u16(d, p + 30))
            let commentLength = Int(u16(d, p + 32))
            let local = Int(u32(d, p + 42))
            guard p + 46 + nameLength <= n else { throw ArchiveError.damaged }
            let nameData = d.subdata(in: (d.startIndex + p + 46) ..< (d.startIndex + p + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            entries.append(Entry(name: name, method: method, flags: flags,
                                 compressedSize: compressed, uncompressedSize: uncompressed,
                                 localHeaderOffset: local))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func u16(_ d: Data, _ o: Int) -> UInt16 {
        let b = d.startIndex + o
        return UInt16(d[b]) | UInt16(d[b + 1]) << 8
    }

    static func u32(_ d: Data, _ o: Int) -> UInt32 {
        let b = d.startIndex + o
        return UInt32(d[b]) | UInt32(d[b + 1]) << 8 | UInt32(d[b + 2]) << 16 | UInt32(d[b + 3]) << 24
    }
}

// MARK: - Un cómic en archivo

/// Abre un .cbz, .zip o PDF y da sus páginas como imágenes.
final class ComicFile {
    private enum Source {
        case zip(ZipArchive, [ZipArchive.Entry])
        case pdf(PDFDocument)
    }

    private let source: Source
    let pageCount: Int

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "bmp"]

    init(url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw ArchiveError.badPDF }
            source = .pdf(doc)
            pageCount = doc.pageCount
        case "cbz", "zip", "cbr":
            // Muchos .cbr en realidad son .zip con otro nombre: los intentamos abrir igual.
            let zip: ZipArchive
            do {
                zip = try ZipArchive(url: url)
            } catch ArchiveError.notZip where url.pathExtension.lowercased() == "cbr" {
                throw ArchiveError.rar
            }
            // Solo imágenes, sin las carpetas ocultas que agrega la Mac, en orden natural (2 antes que 10).
            let pages = zip.entries
                .filter { entry in
                    let name = entry.name
                    let file = (name as NSString).lastPathComponent
                    return !name.hasSuffix("/")
                        && !name.contains("__MACOSX")
                        && !file.hasPrefix(".")
                        && Self.imageExtensions.contains((file as NSString).pathExtension.lowercased())
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !pages.isEmpty else { throw ArchiveError.noPages }
            source = .zip(zip, pages)
            pageCount = pages.count
        default:
            throw ArchiveError.notSupported
        }
    }

    /// La página número `index` (la primera es 0), achicada para que no ocupe más de `maxSize` puntos de ancho.
    func page(_ index: Int, maxWidth: CGFloat) -> UIImage? {
        guard index >= 0, index < pageCount else { return nil }
        switch source {
        case .zip(let zip, let pages):
            guard let data = try? zip.extract(pages[index]), let image = UIImage(data: data) else { return nil }
            guard image.size.width > maxWidth else { return image }
            let scale = maxWidth / image.size.width
            return image.preparingThumbnail(of: CGSize(width: maxWidth, height: image.size.height * scale)) ?? image
        case .pdf(let doc):
            guard let page = doc.page(at: index) else { return nil }
            let box = page.bounds(for: .mediaBox)
            let scale = maxWidth / max(box.width, 1)
            return page.thumbnail(of: CGSize(width: maxWidth, height: box.height * scale), for: .mediaBox)
        }
    }
}
