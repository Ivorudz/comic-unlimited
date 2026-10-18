import Foundation

// Convierte un .cbr (comprimido como RAR) a .cbz, para que la app lo pueda leer.
// Lee el RAR con libarchive (viene dentro de iOS) y escribe un .zip sin comprimir:
// las páginas ya son JPG o PNG, comprimirlas otra vez casi no ahorra lugar.

enum CbrConverter {
    /// Convierte `source` (.cbr) en `destination` (.cbz). Devuelve cuántas páginas pasó.
    static func convert(_ source: URL, to destination: URL) throws -> Int {
        guard let reader = archive_read_new() else { throw ConvertError.failed("no se pudo empezar") }
        defer { archive_read_free(reader) }
        archive_read_support_format_all(reader)
        archive_read_support_filter_all(reader)

        guard archive_read_open_filename(reader, source.path, 1 << 16) == 0 else {
            throw ConvertError.failed(lastError(reader))
        }

        let writer = try StoredZipWriter(url: destination)
        var pages = 0
        var entry: OpaquePointer?
        var buffer = [UInt8](repeating: 0, count: 1 << 16)

        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == 1 { break }                      // terminó
            if status < -20 { throw ConvertError.failed(lastError(reader)) }
            guard let entry else { break }

            let cName = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
            let name = cName.map { String(cString: $0) } ?? ""
            let file = (name as NSString).lastPathComponent
            let isPage = !name.hasSuffix("/")
                && !name.contains("__MACOSX")
                && !file.hasPrefix(".")
                && ComicFile.imageExtensions.contains((file as NSString).pathExtension.lowercased())
            guard isPage else {
                archive_read_data_skip(reader)
                continue
            }

            var data = Data()
            while true {
                let read = buffer.withUnsafeMutableBytes { raw in
                    archive_read_data(reader, raw.baseAddress, raw.count)
                }
                if read == 0 { break }
                if read < 0 { throw ConvertError.failed(lastError(reader)) }
                data.append(buffer, count: read)
            }
            try writer.add(name: name, data: data)
            pages += 1
        }

        try writer.finish()
        guard pages > 0 else { throw ArchiveError.noPages }
        return pages
    }

    private static func lastError(_ reader: OpaquePointer) -> String {
        archive_error_string(reader).map { String(cString: $0) } ?? "error desconocido"
    }

    enum ConvertError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let why): return "No se pudo convertir el .cbr (\(why))."
            }
        }
    }
}

// MARK: - Escritor de .zip sin comprimir

/// Arma un .zip guardando cada archivo tal cual (sin comprimir).
final class StoredZipWriter {
    private struct Central {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var central: [Central] = []

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    func add(name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        guard offset + UInt64(data.count) + 30 + UInt64(nameData.count) < 0xFFFF_FFFF,
              central.count < 0xFFFF else { throw ArchiveError.tooBig }
        let crc = CRC32.checksum(data)
        var header = Data()
        header.append32(0x0403_4b50)       // firma
        header.append16(20)                // versión
        header.append16(0x0800)            // nombres en UTF-8
        header.append16(0)                 // sin comprimir
        header.append16(0)                 // hora
        header.append16(0x21)              // fecha (1/1/1980)
        header.append32(crc)
        header.append32(UInt32(data.count))
        header.append32(UInt32(data.count))
        header.append16(UInt16(nameData.count))
        header.append16(0)
        header.append(nameData)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        central.append(Central(name: nameData, crc: crc, size: UInt32(data.count), offset: UInt32(offset)))
        offset += UInt64(header.count + data.count)
    }

    func finish() throws {
        let start = offset
        var directory = Data()
        for item in central {
            directory.append32(0x0201_4b50)
            directory.append16(20)          // hecho con
            directory.append16(20)          // versión necesaria
            directory.append16(0x0800)
            directory.append16(0)
            directory.append16(0)
            directory.append16(0x21)
            directory.append32(item.crc)
            directory.append32(item.size)
            directory.append32(item.size)
            directory.append16(UInt16(item.name.count))
            directory.append16(0)           // extra
            directory.append16(0)           // comentario
            directory.append16(0)           // disco
            directory.append16(0)           // atributos internos
            directory.append32(0)           // atributos externos
            directory.append32(item.offset)
            directory.append(item.name)
        }
        var end = Data()
        end.append32(0x0605_4b50)
        end.append16(0)
        end.append16(0)
        end.append16(UInt16(central.count))
        end.append16(UInt16(central.count))
        end.append32(UInt32(directory.count))
        end.append32(UInt32(start))
        end.append16(0)
        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.close()
    }
}

/// Suma de control que pide el formato .zip.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }

    mutating func append32(_ v: UInt32) {
        append16(UInt16(v & 0xFFFF))
        append16(UInt16(v >> 16))
    }
}
