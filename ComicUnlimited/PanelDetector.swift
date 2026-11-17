import UIKit

// Detecta las viñetas de una página, sin internet y en el iPhone.
// 1. Achica la página (240 px de ancho) y la pasa a grises.
// 2. Mira el color de los bordes: si casi todo es blanco (o negro), ese es el "fondo" (las calles).
// 3. "Pinta" el fondo desde los bordes hacia adentro; lo que no se pinta son viñetas.
// 4. Separa lo que quedó en manchas y corta cada mancha por las calles (aunque un globo cruce la calle).
// 5. Saca lo muy chico, lo repetido y la página de un solo dibujo, y ordena en orden de lectura.
// Devuelve rectángulos de 0 a 1 (proporción de la página). Si no encuentra viñetas claras, devuelve [].

enum PanelDetector {
    static let width = 240

    static func detect(_ image: UIImage, rightToLeft: Bool) -> [CGRect] {
        guard let cg = image.cgImage, cg.width > 40, cg.height > 40 else { return [] }
        let w = width
        let h = max(20, Int((CGFloat(cg.height) * CGFloat(w) / CGFloat(cg.width)).rounded()))
        // Páginas larguísimas (tiras verticales): no se buscan viñetas.
        guard h <= w * 4 else { return [] }
        var gray = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = gray.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        // La fila 0 de la copia es la de arriba de la página.
        return PanelGrid(gray: gray, width: w, height: h)?.panels(rightToLeft: rightToLeft) ?? []
    }
}

private struct PanelBox {
    var x0: Int, y0: Int, x1: Int, y1: Int   // x1 e y1 no incluidos
    var width: Int { x1 - x0 }
    var height: Int { y1 - y0 }
    var area: Int { width * height }

    func overlap(_ other: PanelBox) -> Int {
        let ix = max(0, min(x1, other.x1) - max(x0, other.x0))
        let iy = max(0, min(y1, other.y1) - max(y0, other.y0))
        return ix * iy
    }
}

private final class PanelGrid {
    let w: Int
    let h: Int
    /// El punto tiene el color del fondo (blanco o negro).
    private var bg: [Bool]
    /// El punto es fondo y se llega a él desde el borde de la página (calles y márgenes).
    private var out: [Bool]
    private var pieces: [PanelBox] = []

    init?(gray: [UInt8], width w: Int, height h: Int) {
        self.w = w
        self.h = h
        // ¿El fondo es blanco o negro? Se mira el borde de la página.
        var light = 0, dark = 0, total = 0
        func sample(_ v: UInt8) {
            total += 1
            if v >= 200 { light += 1 } else if v <= 60 { dark += 1 }
        }
        for x in 0..<w { sample(gray[x]); sample(gray[(h - 1) * w + x]) }
        for y in 0..<h { sample(gray[y * w]); sample(gray[y * w + w - 1]) }
        let isLight: Bool
        if Double(light) >= 0.55 * Double(total) {
            isLight = true
        } else if Double(dark) >= 0.55 * Double(total) {
            isLight = false
        } else {
            return nil   // el dibujo llega a los bordes: página de un solo dibujo
        }
        let bgMask = gray.map { isLight ? $0 >= 200 : $0 <= 60 }

        // Pintar el fondo desde los bordes.
        var out = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        stack.reserveCapacity(w * h / 4)
        func seed(_ i: Int) {
            if bgMask[i] && !out[i] {
                out[i] = true
                stack.append(i)
            }
        }
        for x in 0..<w { seed(x); seed((h - 1) * w + x) }
        for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > 0 { seed(i - 1) }
            if x < w - 1 { seed(i + 1) }
            if y > 0 { seed(i - w) }
            if y < h - 1 { seed(i + w) }
        }
        self.bg = bgMask
        self.out = out
    }

    func panels(rightToLeft: Bool) -> [CGRect] {
        let pageArea = w * h
        // Cada mancha (lo que no es calle), y cada mancha cortada por sus calles.
        for box in components() where box.area >= pageArea / 100 {
            cut(box, depth: 0)
        }
        let minW = w / 10, minH = h * 6 / 100, minArea = pageArea * 2 / 100
        let found = pieces.filter { $0.width >= minW && $0.height >= minH && $0.area >= minArea }
        // Sin repetidos: si una está casi toda dentro de otra más grande, se descarta.
        var kept: [PanelBox] = []
        for box in found.sorted(by: { $0.area > $1.area }) {
            if kept.contains(where: { $0.overlap(box) * 10 >= box.area * 6 }) { continue }
            kept.append(box)
        }
        // Una sola viñeta, o una que ocupa casi toda la página: no hay nada que separar.
        guard kept.count >= 2, !kept.contains(where: { $0.area * 100 >= pageArea * 85 }) else { return [] }
        return readingOrder(kept, rightToLeft: rightToLeft).map {
            CGRect(x: CGFloat($0.x0) / CGFloat(w), y: CGFloat($0.y0) / CGFloat(h),
                   width: CGFloat($0.width) / CGFloat(w), height: CGFloat($0.height) / CGFloat(h))
        }
    }

    /// Manchas de puntos que no son calle (unidas por arriba, abajo y los costados).
    private func components() -> [PanelBox] {
        var seen = [Bool](repeating: false, count: w * h)
        var boxes: [PanelBox] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where !out[start] && !seen[start] {
            seen[start] = true
            stack.append(start)
            var box = PanelBox(x0: start % w, y0: start / w, x1: start % w + 1, y1: start / w + 1)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                box.x0 = min(box.x0, x); box.x1 = max(box.x1, x + 1)
                box.y0 = min(box.y0, y); box.y1 = max(box.y1, y + 1)
                if x > 0, !out[i - 1], !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
                if x < w - 1, !out[i + 1], !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
                if y > 0, !out[i - w], !seen[i - w] { seen[i - w] = true; stack.append(i - w) }
                if y < h - 1, !out[i + w], !seen[i + w] { seen[i + w] = true; stack.append(i + w) }
            }
            boxes.append(box)
        }
        return boxes
    }

    /// Lo que no es calle dentro del recuadro, ajustado.
    private func contentBox(_ b: PanelBox) -> PanelBox? {
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        for y in b.y0..<b.y1 {
            let row = y * w
            for x in b.x0..<b.x1 where !out[row + x] {
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
                if y < y0 { y0 = y }
                if y > y1 { y1 = y }
            }
        }
        return x1 < 0 ? nil : PanelBox(x0: x0, y0: y0, x1: x1 + 1, y1: y1 + 1)
    }

    /// Corta el recuadro por la primera calle que lo cruza (primero de lado a lado, después de arriba abajo).
    private func cut(_ start: PanelBox, depth: Int) {
        guard let b = contentBox(start) else { return }
        if depth < 8 {
            for horizontal in [true, false] {
                if let found = gutter(in: b, horizontal: horizontal) {
                    let (a, z) = found
                    if horizontal {
                        cut(PanelBox(x0: b.x0, y0: b.y0, x1: b.x1, y1: a), depth: depth + 1)
                        cut(PanelBox(x0: b.x0, y0: z, x1: b.x1, y1: b.y1), depth: depth + 1)
                    } else {
                        cut(PanelBox(x0: b.x0, y0: b.y0, x1: a, y1: b.y1), depth: depth + 1)
                        cut(PanelBox(x0: z, y0: b.y0, x1: b.x1, y1: b.y1), depth: depth + 1)
                    }
                    return
                }
            }
        }
        pieces.append(b)
    }

    /// Busca una calle que cruce todo el recuadro (filas si `horizontal`, columnas si no).
    /// Cuenta como calle: casi toda calle; o casi todo fondo y al menos la mitad calle (un globo que la cruza);
    /// o una franja de al menos dos filas mayormente calle (un dibujo que se sale un poco).
    private func gutter(in b: PanelBox, horizontal: Bool) -> (Int, Int)? {
        let length = Double(horizontal ? b.width : b.height)
        let lines = horizontal ? Array(b.y0..<b.y1) : Array(b.x0..<b.x1)
        guard lines.count >= 3 else { return nil }
        var outside = [Double](repeating: 0, count: lines.count)
        var background = [Double](repeating: 0, count: lines.count)
        for (k, line) in lines.enumerated() {
            var o = 0, g = 0
            if horizontal {
                let row = line * w
                for x in b.x0..<b.x1 {
                    if out[row + x] { o += 1 }
                    if bg[row + x] { g += 1 }
                }
            } else {
                for y in b.y0..<b.y1 {
                    if out[y * w + line] { o += 1 }
                    if bg[y * w + line] { g += 1 }
                }
            }
            outside[k] = Double(o) / length
            background[k] = Double(g) / length
        }
        var isGutter = [Bool](repeating: false, count: lines.count)
        for k in 0..<lines.count {
            let strong = outside[k] >= 0.85 || (background[k] >= 0.92 && outside[k] >= 0.45)
            let before = k > 0 && outside[k - 1] >= 0.6
            let after = k + 1 < lines.count && outside[k + 1] >= 0.6
            isGutter[k] = strong || (outside[k] >= 0.6 && (before || after))
        }
        // La primera calle de adentro (no en el borde).
        var k = 1
        while k < lines.count - 1 {
            if isGutter[k] {
                var e = k
                while e < lines.count && isGutter[e] { e += 1 }
                return e < lines.count ? (lines[k], lines[e]) : nil
            }
            k += 1
        }
        return nil
    }

    /// Orden de lectura: por filas de arriba abajo; en cada fila, de izquierda a derecha (o al revés en manga).
    private func readingOrder(_ boxes: [PanelBox], rightToLeft: Bool) -> [PanelBox] {
        var rows: [[PanelBox]] = []
        for box in boxes.sorted(by: { $0.y0 < $1.y0 }) {
            var placed = false
            for r in rows.indices {
                let top = rows[r].map(\.y0).min() ?? 0
                let bottom = rows[r].map(\.y1).max() ?? 0
                let shared = min(bottom, box.y1) - max(top, box.y0)
                if shared * 2 >= min(box.height, bottom - top) {
                    rows[r].append(box)
                    placed = true
                    break
                }
            }
            if !placed { rows.append([box]) }
        }
        rows.sort { ($0.map(\.y0).min() ?? 0) < ($1.map(\.y0).min() ?? 0) }
        return rows.flatMap { row in
            // Orden estable: en una misma columna quedan de arriba abajo.
            row.enumerated().sorted { a, b in
                if a.element.x0 != b.element.x0 {
                    return rightToLeft ? a.element.x0 > b.element.x0 : a.element.x0 < b.element.x0
                }
                return a.offset < b.offset
            }.map(\.element)
        }
    }
}

/// Guarda las viñetas encontradas de cada página (en memoria y en la carpeta de caché), así se buscan una sola vez.
actor PanelStore {
    static let shared = PanelStore()
    /// Si cambia la forma de buscar, se cambia este número y se vuelven a buscar.
    private static let version = 1
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
