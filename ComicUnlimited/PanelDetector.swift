import UIKit

// Detecta las viñetas de una página, sin internet y en el iPhone.
// Las viñetas están separadas por "calles": franjas rectas de un solo color (blanco, negro, gris, beige…).
// 1. Achica la página (400 px de ancho).
// 2. Busca los colores de calle: filas o columnas de toda la página que son casi de un solo color.
//    Si no hay ninguna, mira sin el 5 % de cada borde (páginas con un marco dibujado alrededor).
// 3. Corta la página por las calles que la cruzan de lado a lado (primero en filas, después en columnas)
//    y repite adentro de cada parte, solo con calles del mismo color que las que la separaron.
//    Una línea es calle si al menos el 72 % es de ese color (así un globo puede cruzarla)
//    y el color aparece en el 5 % de cada punta (al recortar los bordes de una zona se pide más).
// 4. Saca lo muy chico; si queda una sola parte (página de un solo dibujo), no hay viñetas.
// El orden de los cortes ya es el orden de lectura (en manga, las columnas de derecha a izquierda).
// Devuelve rectángulos de 0 a 1 (proporción de la página). Probado con páginas reales y dibujadas.

enum PanelDetector {
    static let width = 400

    static func detect(_ image: UIImage, rightToLeft: Bool) -> [CGRect] {
        guard let cg = image.cgImage, cg.width > 40, cg.height > 40 else { return [] }
        let w = width
        let h = max(20, Int((CGFloat(cg.height) * CGFloat(w) / CGFloat(cg.width)).rounded()))
        // Páginas larguísimas (tiras verticales): no se buscan viñetas.
        guard h <= w * 4 else { return [] }
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        // La fila 0 de la copia es la de arriba de la página.
        return PanelCutter(pixels: pixels, width: w, height: h).panels(rightToLeft: rightToLeft)
    }
}

private struct PanelColor {
    var r: Int, g: Int, b: Int

    /// Diferencia más grande entre los tres canales.
    func distance(_ o: PanelColor) -> Int { max(abs(r - o.r), abs(g - o.g), abs(b - o.b)) }
}

private struct PanelBox {
    var x0: Int, y0: Int, x1: Int, y1: Int   // x1 e y1 no incluidos
    var width: Int { x1 - x0 }
    var height: Int { y1 - y0 }
    var area: Int { width * height }
}

private final class PanelCutter {
    /// "Mismo color": diferencia de hasta 32 en cada canal.
    private static let tolerance = 32
    /// Colores parecidos (para agrupar colores de calle).
    private static let similar = 40
    /// Parte de la línea que tiene que ser del color de la calle.
    private static let lineShare = 0.72
    /// Porcentaje de cada punta de la línea que se mira (o se saltea, si la página tiene marco).
    private static let edge = 5

    private let px: [UInt8]
    private let w: Int
    private let h: Int
    private var pieces: [PanelBox] = []

    init(pixels: [UInt8], width: Int, height: Int) {
        px = pixels
        w = width
        h = height
    }

    func panels(rightToLeft: Bool) -> [CGRect] {
        // Si no hay ninguna, puede haber un marco dibujado alrededor de la página: se mira sin los bordes.
        var colors = pageColors(skip: 0)
        if colors.isEmpty { colors = pageColors(skip: Self.edge) }
        guard !colors.isEmpty else { return [] }
        cut(PanelBox(x0: 0, y0: 0, x1: w, y1: h), colors: colors, depth: 0, rightToLeft: rightToLeft)
        let pageArea = w * h
        let found = pieces.filter {
            $0.width * 10 >= w && $0.height * 100 >= h * 6 && $0.area * 100 >= pageArea * 2
        }
        // Una sola viñeta, o una que ocupa casi toda la página: no hay nada que separar.
        guard found.count >= 2, !found.contains(where: { $0.area * 100 >= pageArea * 85 }) else { return [] }
        return found.map {
            CGRect(x: CGFloat($0.x0) / CGFloat(w), y: CGFloat($0.y0) / CGFloat(h),
                   width: CGFloat($0.width) / CGFloat(w), height: CGFloat($0.height) / CGFloat(h))
        }
    }

    // MARK: Píxeles y líneas

    private func color(_ x: Int, _ y: Int) -> PanelColor {
        let i = (y * w + x) * 4
        return PanelColor(r: Int(px[i]), g: Int(px[i + 1]), b: Int(px[i + 2]))
    }

    /// Punto número `i` de una línea: una fila `k` (de `a0` a `a1`) o una columna.
    private func point(_ horizontal: Bool, _ k: Int, _ i: Int) -> PanelColor {
        horizontal ? color(i, k) : color(k, i)
    }

    /// Si la línea es casi toda de un color (95 %), ese color.
    private func uniformColor(_ horizontal: Bool, _ k: Int, _ a0: Int, _ a1: Int) -> PanelColor? {
        let n = a1 - a0
        guard n > 0 else { return nil }
        var r = 0, g = 0, b = 0
        for i in a0..<a1 {
            let c = point(horizontal, k, i)
            r += c.r; g += c.g; b += c.b
        }
        let mean = PanelColor(r: r / n, g: g / n, b: b / n)
        var near = 0
        for i in a0..<a1 where point(horizontal, k, i).distance(mean) <= Self.tolerance { near += 1 }
        return near * 100 >= n * 95 ? mean : nil
    }

    /// ¿La línea es calle de alguno de esos colores? Devuelve el color.
    /// `loose`: alcanza con que el color aparezca en el 5 % de cada punta (marcos o bordes sucios).
    /// Sin `loose` (al recortar bordes) la mitad del 2 % de cada punta tiene que ser de ese color.
    private func separator(_ horizontal: Bool, _ k: Int, _ a0: Int, _ a1: Int, _ colors: [PanelColor],
                           loose: Bool = true) -> PanelColor? {
        let n = a1 - a0
        guard n > 0 else { return nil }
        let end = loose ? max(2, n * Self.edge / 100) : max(2, n / 50)
        for c in colors {
            var near = 0, first = 0, last = 0
            for i in a0..<a1 where point(horizontal, k, i).distance(c) <= Self.tolerance {
                near += 1
                if i - a0 < end { first += 1 }
                if a1 - 1 - i < end { last += 1 }
            }
            guard Double(near) >= Self.lineShare * Double(n) else { continue }
            if loose ? (first > 0 && last > 0) : (first * 2 >= end && last * 2 >= end) {
                return c
            }
        }
        return nil
    }

    private func adding(_ c: PanelColor, to colors: [PanelColor]) -> [PanelColor] {
        colors.contains { $0.distance(c) <= Self.similar } ? colors : colors + [c]
    }

    /// Colores de calle de la página: los de las filas y columnas enteras de un solo color (los 3 más comunes).
    /// `skip`: porcentaje de cada punta que no se mira.
    private func pageColors(skip: Int) -> [PanelColor] {
        var found: [(color: PanelColor, count: Int)] = []
        for horizontal in [true, false] {
            let lines = horizontal ? h : w
            let length = horizontal ? w : h
            let cut = length * skip / 100
            for k in 0..<lines {
                guard let c = uniformColor(horizontal, k, cut, length - cut) else { continue }
                if let i = found.firstIndex(where: { $0.color.distance(c) <= Self.similar }) {
                    found[i].count += 1
                } else {
                    found.append((c, 1))
                }
            }
        }
        return found.filter { $0.count >= 2 }.sorted { $0.count > $1.count }.prefix(3).map(\.color)
    }

    // MARK: Cortes

    /// Saca márgenes y calles de los bordes de la zona (solo de los colores de calle).
    private func trim(_ start: PanelBox, _ colors: [PanelColor]) -> PanelBox {
        var b = start
        var changed = true
        while changed && b.width > 4 && b.height > 4 {
            changed = false
            if separator(true, b.y0, b.x0, b.x1, colors, loose: false) != nil { b.y0 += 1; changed = true }
            if b.height > 4, separator(true, b.y1 - 1, b.x0, b.x1, colors, loose: false) != nil { b.y1 -= 1; changed = true }
            if separator(false, b.x0, b.y0, b.y1, colors, loose: false) != nil { b.x0 += 1; changed = true }
            if b.width > 4, separator(false, b.x1 - 1, b.y0, b.y1, colors, loose: false) != nil { b.x1 -= 1; changed = true }
        }
        return b
    }

    private func cut(_ start: PanelBox, colors: [PanelColor], depth: Int, rightToLeft: Bool) {
        let b = trim(start, colors)
        guard b.width >= 8, b.height >= 8 else { return }
        if depth < 10 {
            for horizontal in [true, false] {
                let lines = horizontal ? Array(b.y0..<b.y1) : Array(b.x0..<b.x1)
                let (a0, a1) = horizontal ? (b.x0, b.x1) : (b.y0, b.y1)
                let seps = lines.map { separator(horizontal, $0, a0, a1, colors) }
                // Bandas entre calles (las muy finitas no cuentan).
                let minBand = max(3, (horizontal ? h : w) * 4 / 100)
                var bands: [(Int, Int)] = []
                var bandStart: Int?
                for (i, s) in seps.enumerated() {
                    if s == nil, bandStart == nil { bandStart = i }
                    if s != nil, let begin = bandStart { bands.append((begin, i)); bandStart = nil }
                }
                if let begin = bandStart { bands.append((begin, seps.count)) }
                bands = bands.filter { $0.1 - $0.0 >= minBand }
                guard bands.count >= 2 else { continue }
                // Adentro, las calles son del mismo color que las que separaron estas bandas.
                var used: [PanelColor] = []
                for (left, right) in zip(bands, bands.dropFirst()) {
                    let run = seps[left.1..<right.0].compactMap { $0 }
                    let best = run.max { a, c in
                        run.filter { $0.distance(a) <= Self.similar }.count < run.filter { $0.distance(c) <= Self.similar }.count
                    }
                    if let best { used = adding(best, to: used) }
                }
                if used.isEmpty { used = colors }
                let base = horizontal ? b.y0 : b.x0
                let ordered = (!horizontal && rightToLeft) ? Array(bands.reversed()) : bands
                for (s, e) in ordered {
                    let part = horizontal
                        ? PanelBox(x0: b.x0, y0: base + s, x1: b.x1, y1: base + e)
                        : PanelBox(x0: base + s, y0: b.y0, x1: base + e, y1: b.y1)
                    cut(part, colors: used, depth: depth + 1, rightToLeft: rightToLeft)
                }
                return
            }
        }
        pieces.append(b)
    }
}

/// Guarda las viñetas encontradas de cada página (en memoria y en la carpeta de caché), así se buscan una sola vez.
actor PanelStore {
    static let shared = PanelStore()
    /// Si cambia la forma de buscar, se cambia este número y se vuelven a buscar.
    private static let version = 3
    private var memory: [String: [String: [[Double]]]] = [:]

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vinetas", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func file(_ comicID: String) -> URL {
        let safe: [Character] = comicID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return Self.folder.appendingPathComponent("v\(Self.version)-\(String(safe)).json")
    }

    func panels(comicID: String, index: Int, crop: Bool, rightToLeft: Bool, image: UIImage) -> [CGRect] {
        let key = "\(index)-\(crop ? 1 : 0)-\(rightToLeft ? 1 : 0)"
        if memory[comicID] == nil {
            if let data = try? Data(contentsOf: file(comicID)),
               let saved = try? JSONDecoder().decode([String: [[Double]]].self, from: data) {
                memory[comicID] = saved
            } else {
                memory[comicID] = [:]
            }
        }
        if let saved = memory[comicID]?[key] {
            return saved.compactMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        }
        let found = PanelDetector.detect(image, rightToLeft: rightToLeft)
        memory[comicID, default: [:]][key] = found.map {
            [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)]
        }
        if let data = try? JSONEncoder().encode(memory[comicID]) {
            try? data.write(to: file(comicID), options: .atomic)
        }
        return found
    }
}
