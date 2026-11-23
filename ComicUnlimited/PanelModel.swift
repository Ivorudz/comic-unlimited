import CoreML
import UIKit

// Busca las viñetas con el modelo entrenado (Vinetas.mlmodel, ver tools/vinetas/README.md).
// El modelo mira la página estirada a 320 × 480 y pinta cada punto (en 160 × 240) como
// 0 = fondo, 1 = adentro de una viñeta, 2 = borde de viñeta.
// Cada mancha de "adentro" es una viñeta: se toma su rectángulo y se le suma el borde que se comió.
// Misma lógica que tools/vinetas/modelo_vinetas.py (componentes_a_recuadros, orden_lectura, recuadros).
// Si el modelo no está o falla, devuelve nil y se usan las reglas de PanelDetector.

enum PanelModel {
    static let inputWidth = 320
    static let inputHeight = 480
    /// Ancho del borde pintado alrededor de cada viñeta (proporción del lado de la página).
    static let band = 0.012
    /// Manchas más chicas que esto (proporción de la página) no cuentan.
    static let minArea = 0.004
    /// Cada viñeta tiene que llenar al menos esto de su rectángulo; si no, el modelo duda y se ve la página entera.
    static let minFill = 0.85

    private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "Vinetas", withExtension: "mlmodelc") else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: config)
    }()

    static func detect(_ cg: CGImage, rightToLeft: Bool) -> [CGRect]? {
        guard let model, let page = stretched(cg),
              let constraint = model.modelDescription.inputDescriptionsByName["pagina"]?.imageConstraint,
              let value = try? MLFeatureValue(cgImage: page, constraint: constraint, options: nil),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["pagina": value]),
              let output = try? model.prediction(from: input),
              let classes = output.featureValue(for: "clases")?.multiArrayValue
        else { return nil }
        let shape = classes.shape.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let h = shape[shape.count - 2], w = shape[shape.count - 1]
        guard w > 0, h > 0, classes.count == w * h else { return nil }
        var inside = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { inside[i] = classes[i].doubleValue.rounded() == 1 }
        let boxes = readingOrder(components(inside, w, h), rightToLeft: rightToLeft)
        // Igual que las reglas: una sola viñeta, o una que ocupa casi toda la página, es "sin viñetas".
        guard boxes.count >= 2, !boxes.contains(where: { $0.width * $0.height >= 0.85 }) else { return [] }
        return boxes
    }

    /// La página estirada a 320 × 480, en RGB.
    private static func stretched(_ cg: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: inputWidth, height: inputHeight, bitsPerComponent: 8,
                                  bytesPerRow: inputWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
        return ctx.makeImage()
    }

    /// Rectángulo de cada mancha de "adentro" (vecinos arriba, abajo, izquierda y derecha), en proporción.
    private static func components(_ inside: [Bool], _ w: Int, _ h: Int) -> [CGRect] {
        var seen = [Bool](repeating: false, count: w * h)
        let bx = band * Double(w), by = band * Double(h)
        var out: [CGRect] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where inside[start] && !seen[start] {
            seen[start] = true
            stack = [start]
            var x0 = w, y0 = h, x1 = 0, y1 = 0, n = 0
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                n += 1
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for q in [y > 0 ? p - w : -1, y < h - 1 ? p + w : -1, x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1]
                where q >= 0 && inside[q] && !seen[q] {
                    seen[q] = true
                    stack.append(q)
                }
            }
            guard Double(n) >= minArea * Double(w * h) else { continue }
            // Mancha que no llena su rectángulo (forma de L, dos viñetas pegadas): el modelo duda → página entera.
            if Double(n) < minFill * Double((x1 - x0 + 1) * (y1 - y0 + 1)) { return [] }
            // El borde pintado se come un poco de la viñeta: se agrega de vuelta.
            let fx0 = max(0, Double(x0) - bx), fy0 = max(0, Double(y0) - by)
            let fx1 = min(Double(w), Double(x1 + 1) + bx), fy1 = min(Double(h), Double(y1 + 1) + by)
            out.append(CGRect(x: fx0 / Double(w), y: fy0 / Double(h),
                              width: (fx1 - fx0) / Double(w), height: (fy1 - fy0) / Double(h)))
        }
        return out
    }

    /// Filas de arriba a abajo (las que se pisan en altura van juntas); en cada fila, de izquierda a derecha
    /// (o al revés en manga).
    private static func readingOrder(_ boxes: [CGRect], rightToLeft: Bool) -> [CGRect] {
        var rest = boxes.sorted { $0.minY < $1.minY }
        var out: [CGRect] = []
        while let first = rest.first {
            let limit = first.minY + first.height * 0.5
            var row = rest.filter { $0.minY < limit }
            rest.removeAll { $0.minY < limit }
            row.sort { rightToLeft ? $0.maxX > $1.maxX : $0.minX < $1.minX }
            out += row
        }
        return out
    }
}
