import SwiftUI

// Dibuja las portadas y las páginas de los cómics de ejemplo con formas simples
// (círculos, rectángulos, olas). Es el mismo dibujo del prototipo web, pasado a Swift.
// No usa imágenes: todo se genera en el momento, así no hay contenido con derechos de autor.

// MARK: - Vistas que se usan en la app

/// Portada de un cómic, con proporción 2:3.
struct CoverArt: View {
    let comic: Comic

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 400
            context.scaleBy(x: scale, y: scale)
            Drawing.cover(context, comic: comic)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Una página completa del cómic, con proporción 2:3.
struct PageArt: View {
    let comic: Comic
    let page: Int

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 600, size.height / 900)
            context.translateBy(x: (size.width - 600 * scale) / 2, y: (size.height - 900 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            Drawing.page(context, comic: comic, page: page)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .accessibilityLabel("Página \(page + 1) de \(comic.title)")
    }
}

// MARK: - Dibujo

enum Drawing {
    static let inkHex: UInt32 = 0x14161B
    static let ink = Color(hex: inkHex)
    static let white = Color.white

    /// Cómo se reparten las 3 viñetas en cada página (x, y, ancho, alto).
    static let layouts: [[CGRect]] = [
        [CGRect(x: 18, y: 18, width: 564, height: 330), CGRect(x: 18, y: 360, width: 276, height: 522), CGRect(x: 306, y: 360, width: 276, height: 522)],
        [CGRect(x: 18, y: 18, width: 276, height: 420), CGRect(x: 306, y: 18, width: 276, height: 420), CGRect(x: 18, y: 450, width: 564, height: 432)],
        [CGRect(x: 18, y: 18, width: 564, height: 276), CGRect(x: 18, y: 306, width: 564, height: 276), CGRect(x: 18, y: 594, width: 564, height: 288)],
    ]

    // MARK: Página

    static func page(_ g: GraphicsContext, comic: Comic, page p: Int) {
        let pal = comic.palette
        let layout = layouts[p % 3]
        let rand = Rand(seed: hash("\(comic.id)\(p)"))

        g.fill(Path(CGRect(x: 0, y: 0, width: 600, height: 900)), with: .color(Color(hex: 0xFBFAF7)))

        for (i, r) in layout.enumerated() {
            let k = p * 3 + i
            let bgs = [pal[0], shade(pal[0], 0.16), shade(pal[0], -0.25)]
            var panel = g
            panel.clip(to: Path(r))
            panel.fill(Path(r), with: .color(Color(hex: bgs[k % 3])))
            let lower = CGRect(x: r.minX, y: r.minY + r.height * 0.45, width: r.width, height: r.height * 0.55)
            panel.fill(dots(in: lower, spacing: 9, radius: 2.2), with: .color(Color(hex: pal[2], opacity: 0.26)))
            let sceneName = k < comic.scenes.count ? comic.scenes[k] : "sky"
            scene(panel, sceneName, r, pal, rand)
            if k < comic.lines.count {
                textBlock(panel, comic.lines[k], r, pal)
            }
            g.stroke(Path(r), with: .color(ink), lineWidth: 5)
        }

        let number = g.resolve(Text("\(p + 1)").font(.system(size: 11)).foregroundStyle(Color(hex: 0x777777)))
        g.draw(number, at: CGPoint(x: 300, y: 898), anchor: .bottom)
    }

    // MARK: Portada

    static func cover(_ g: GraphicsContext, comic: Comic) {
        let pal = comic.palette
        let rand = Rand(seed: hash("cv\(comic.id)"))
        let titleLines = wrapByCount(comic.title, max: 11)
        let fs: CGFloat = titleLines.count > 2 ? 42 : 50
        let blockH = CGFloat(titleLines.count) * fs * 1.02 + 74
        let fg = lum(pal[1]) > 0.55 ? ink : white

        g.fill(Path(CGRect(x: 0, y: 0, width: 400, height: 600)), with: .color(Color(hex: pal[0])))

        // Círculo de puntitos (trama de imprenta).
        var halftone = g
        halftone.clip(to: circle(270, 210, 175))
        halftone.fill(dots(in: CGRect(x: 95, y: 35, width: 350, height: 350), spacing: 12, radius: 3.3),
                      with: .color(Color(hex: pal[1], opacity: 0.6)))

        scene(g, comic.scenes.first ?? "sky", CGRect(x: 0, y: 40, width: 400, height: 600 - blockH - 30), pal, rand)

        // Bloque del título.
        g.fill(Path(CGRect(x: 0, y: 600 - blockH, width: 400, height: blockH)), with: .color(Color(hex: pal[1])))
        for (i, line) in titleLines.enumerated() {
            var size = fs
            var text = g.resolve(titleText(line, size: size, color: fg))
            let width = text.measure(in: CGSize(width: 2000, height: 200)).width
            if width > 356 {
                size = fs * 356 / width
                text = g.resolve(titleText(line, size: size, color: fg))
            }
            let baseline = 600 - blockH + 18 + fs * 0.9 + CGFloat(i) * fs * 1.02
            g.draw(text, at: CGPoint(x: 22, y: baseline + size * 0.22), anchor: .bottomLeading)
        }
        let author = g.resolve(Text(comic.author).font(.system(size: 17)).foregroundStyle(fg.opacity(0.85)))
        g.draw(author, at: CGPoint(x: 22, y: 584), anchor: .bottomLeading)

        // Número de edición (#1) en un recuadro amarillo.
        if !comic.issue.isEmpty {
            let box = CGRect(x: 18, y: 18, width: 62, height: 36)
            g.fill(Path(box), with: .color(Theme.yellow))
            g.stroke(Path(box), with: .color(ink), lineWidth: 3)
            let issue = g.resolve(Text(comic.issue).font(.system(size: 21, weight: .black)).foregroundStyle(ink))
            g.draw(issue, at: CGPoint(x: 49, y: 36), anchor: .center)
        }
    }

    static func titleText(_ s: String, size: CGFloat, color: Color) -> Text {
        Text(s).font(.system(size: size, weight: .black).width(.expanded)).foregroundStyle(color)
    }

    // MARK: Textos de las viñetas

    static func textBlock(_ g: GraphicsContext, _ line: String, _ r: CGRect, _ pal: [UInt32]) {
        guard !line.isEmpty else { return }
        let speech = line.hasPrefix("—")
        let content = speech ? String(line.dropFirst()) : line
        let fs: CGFloat = r.width > 400 ? 24 : 20
        let lh = fs * 1.22
        let fg = speech ? ink : (lum(pal[2]) > 0.5 ? ink : white)
        let font = Font.system(size: fs, weight: speech ? .semibold : .bold)
        let make: (String) -> GraphicsContext.ResolvedText = { s in
            g.resolve(Text(s).font(font).foregroundStyle(fg))
        }
        let measure: (String) -> CGFloat = { s in
            make(s).measure(in: CGSize(width: 4000, height: 400)).width
        }

        // Partimos el texto en renglones que entren en la viñeta.
        let maxWidth = r.width - 28 - 34
        var rows: [String] = []
        var current = ""
        for word in content.split(separator: " ").map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if !current.isEmpty && measure(candidate) > maxWidth {
                rows.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { rows.append(current) }

        let widest = rows.map(measure).max() ?? 0
        let bw = min(r.width - 28, widest + 34)
        let bh = CGFloat(rows.count) * lh + 20

        if speech {
            // Globo de diálogo blanco con colita.
            let bx = r.minX + 14, by = r.minY + 14
            let bubble = Path(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: 20)
            g.fill(bubble, with: .color(white))
            g.stroke(bubble, with: .color(ink), lineWidth: 2.5)
            let ax = bx + bw * 0.28, bx2 = bx + bw * 0.44, ty = by + bh
            var tail = Path()
            tail.move(to: CGPoint(x: ax, y: ty))
            tail.addLine(to: CGPoint(x: ax - 6, y: ty + 24))
            tail.addLine(to: CGPoint(x: bx2, y: ty))
            g.fill(tail, with: .color(white))
            g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            var gap = Path()
            gap.move(to: CGPoint(x: ax + 2, y: ty))
            gap.addLine(to: CGPoint(x: bx2 - 2, y: ty))
            g.stroke(gap, with: .color(white), lineWidth: 4)
            for (i, row) in rows.enumerated() {
                g.draw(make(row), at: CGPoint(x: bx + 17, y: by + 10 + CGFloat(i) * lh), anchor: .topLeading)
            }
        } else {
            // Recuadro de narración del color de acento.
            let box = CGRect(x: r.minX + 10, y: r.minY + 10, width: bw, height: bh)
            g.fill(Path(box), with: .color(Color(hex: pal[2])))
            g.stroke(Path(box), with: .color(ink), lineWidth: 2.5)
            for (i, row) in rows.enumerated() {
                g.draw(make(row), at: CGPoint(x: r.minX + 27, y: r.minY + 20 + CGFloat(i) * lh), anchor: .topLeading)
            }
        }
    }

    // MARK: Escenas

    static func scene(_ g: GraphicsContext, _ type: String, _ r: CGRect, _ pal: [UInt32], _ rand: Rand) {
        let x = r.minX, y = r.minY, w = r.width, h = r.height
        let cx = x + w / 2, by = y + h, m = min(w, h)
        let inkFill = GraphicsContext.Shading.color(ink)
        let accent = Color(hex: pal[2])

        switch type {
        case "sky":
            g.fill(circle(x + w * 0.68, y + h * 0.38, m * 0.2), with: .color(accent))
            for _ in 0..<14 {
                let sx = x + rand.next() * w
                let sy = y + rand.next() * h * 0.7
                let sr = 1 + rand.next() * 2
                g.fill(circle(sx, sy, sr), with: .color(white.opacity(0.8)))
            }
            var ground = Path()
            ground.move(to: CGPoint(x: x, y: by))
            ground.addLine(to: CGPoint(x: x, y: by - h * 0.18))
            ground.addQuadCurve(to: CGPoint(x: x + w * 0.55, y: by - h * 0.16), control: CGPoint(x: x + w * 0.3, y: by - h * 0.3))
            ground.addQuadCurve(to: CGPoint(x: x + w, y: by - h * 0.22), control: CGPoint(x: x + w * 0.8, y: by - h * 0.02))
            ground.addLine(to: CGPoint(x: x + w, y: by))
            ground.closeSubpath()
            g.fill(ground, with: inkFill)

        case "city":
            let n = 7
            let bw = w / CGFloat(n)
            for i in 0..<n {
                let bh = h * (0.3 + rand.next() * 0.45)
                let bx = x + CGFloat(i) * bw
                g.fill(Path(CGRect(x: bx, y: by - bh, width: bw + 1, height: bh)), with: inkFill)
                for j in 0..<6 where rand.next() > 0.55 {
                    let wx = bx + bw * 0.22 + CGFloat(j % 2) * bw * 0.34
                    let wy = by - bh + 14 + CGFloat(j / 2) * bh / 4
                    g.fill(Path(CGRect(x: wx, y: wy, width: bw * 0.16, height: bw * 0.16)), with: .color(accent))
                }
            }

        case "figure":
            figure(g, x + w * (0.38 + rand.next() * 0.24), by, m)

        case "duo":
            figure(g, x + w * 0.3, by, m * 0.95)
            figure(g, x + w * 0.68, by, m * 0.82)

        case "close":
            let ey = y + h * 0.52, dx = w * 0.17
            g.fill(circle(cx, y + h * 1.05, max(w, h) * 0.62), with: .color(Color(hex: shade(pal[0], -0.55))))
            for k: CGFloat in [-1, 1] {
                g.fill(ellipse(cx + k * dx, ey, w * 0.09, h * 0.07), with: .color(white))
                g.fill(circle(cx + k * dx + w * 0.02, ey, m * 0.045), with: inkFill)
            }

        case "sea":
            g.fill(wave(x, w, y + h * 0.55, h * 0.06, by), with: .color(Color(hex: pal[1])))
            g.fill(wave(x, w, y + h * 0.7, h * 0.05, by), with: .color(Color(hex: shade(pal[1], -0.35))))
            g.fill(wave(x, w, y + h * 0.85, h * 0.04, by), with: inkFill)

        case "object":
            let bw = w * 0.46, bh = h * 0.42
            let bx = cx - bw / 2, top = by - bh - h * 0.06
            g.fill(circle(cx, top + bh * 0.45, m * 0.42), with: .color(accent.opacity(0.3)))
            g.fill(Path(CGRect(x: bx, y: top, width: bw, height: bh)), with: inkFill)
            g.fill(Path(CGRect(x: cx - bw * 0.08, y: top + bh * 0.15, width: bw * 0.16, height: bh * 0.7)), with: .color(accent))
            g.fill(Path(CGRect(x: x, y: by - h * 0.06, width: w, height: h * 0.06)), with: inkFill)

        case "tree":
            let tx = x + w * 0.55
            g.fill(Path(CGRect(x: x, y: by - h * 0.12, width: w, height: h * 0.12)), with: inkFill)
            g.fill(Path(CGRect(x: tx - m * 0.03, y: by - h * 0.55, width: m * 0.06, height: h * 0.45)), with: inkFill)
            g.fill(circle(tx, by - h * 0.6, m * 0.2), with: inkFill)
            g.fill(circle(tx - m * 0.14, by - h * 0.52, m * 0.13), with: inkFill)
            g.fill(circle(tx + m * 0.15, by - h * 0.5, m * 0.12), with: inkFill)

        case "cats":
            let s = m * 0.32
            let floor = by - h * 0.08
            g.fill(Path(CGRect(x: x, y: floor, width: w, height: h * 0.08)), with: inkFill)
            cat(g, x + w * 0.25, floor, s, accent)
            cat(g, x + w * 0.55, floor, s * 0.8, accent)
            if w > 400 { cat(g, x + w * 0.82, floor, s * 0.9, accent) }

        case "crane":
            let tx = x + w * 0.28
            g.fill(Path(CGRect(x: tx, y: y + h * 0.14, width: w * 0.05, height: h * 0.86)), with: inkFill)
            g.fill(Path(CGRect(x: tx - w * 0.12, y: y + h * 0.14, width: w * 0.78, height: h * 0.045)), with: inkFill)
            var cable = Path()
            cable.move(to: CGPoint(x: x + w * 0.72, y: y + h * 0.18))
            cable.addLine(to: CGPoint(x: x + w * 0.72, y: y + h * 0.56))
            g.stroke(cable, with: inkFill, lineWidth: 3)
            let box = CGRect(x: x + w * 0.6, y: y + h * 0.56, width: w * 0.24, height: h * 0.16)
            g.fill(Path(box), with: .color(Color(hex: pal[1])))
            g.stroke(Path(box), with: inkFill, lineWidth: 3)
            g.fill(Path(CGRect(x: x, y: by - h * 0.08, width: w, height: h * 0.08)), with: inkFill)

        case "tower":
            let top = y + h * 0.22, b1 = w * 0.12, b2 = w * 0.065
            var beamLeft = Path()
            beamLeft.move(to: CGPoint(x: cx, y: top))
            beamLeft.addLine(to: CGPoint(x: x - w * 0.1, y: y + h * 0.02))
            beamLeft.addLine(to: CGPoint(x: x - w * 0.1, y: y + h * 0.42))
            beamLeft.closeSubpath()
            g.fill(beamLeft, with: .color(accent.opacity(0.35)))
            var beamRight = Path()
            beamRight.move(to: CGPoint(x: cx, y: top))
            beamRight.addLine(to: CGPoint(x: x + w * 1.1, y: y + h * 0.05))
            beamRight.addLine(to: CGPoint(x: x + w * 1.1, y: y + h * 0.4))
            beamRight.closeSubpath()
            g.fill(beamRight, with: .color(accent.opacity(0.35)))
            var body = Path()
            body.move(to: CGPoint(x: cx - b1, y: by - h * 0.1))
            body.addLine(to: CGPoint(x: cx - b2, y: top + h * 0.06))
            body.addLine(to: CGPoint(x: cx + b2, y: top + h * 0.06))
            body.addLine(to: CGPoint(x: cx + b1, y: by - h * 0.1))
            body.closeSubpath()
            g.fill(body, with: inkFill)
            g.fill(Path(CGRect(x: cx - b1 * 0.9, y: top + h * 0.25, width: b1 * 1.8, height: h * 0.07)), with: .color(Color(hex: pal[1])))
            g.fill(circle(cx, top, m * 0.06), with: .color(accent))
            g.fill(wave(x, w, by - h * 0.1, h * 0.03, by), with: inkFill)

        default:
            break
        }
    }

    /// Una silueta de persona.
    static func figure(_ g: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
        let hr = s * 0.09, top = by - s * 0.62
        g.fill(circle(cx, top, hr), with: .color(ink))
        var body = Path()
        body.move(to: CGPoint(x: cx - hr * 2.2, y: by))
        body.addLine(to: CGPoint(x: cx - hr * 1.5, y: top + hr * 1.4))
        body.addQuadCurve(to: CGPoint(x: cx + hr * 1.5, y: top + hr * 1.4), control: CGPoint(x: cx, y: top + hr * 1.1))
        body.addLine(to: CGPoint(x: cx + hr * 2.2, y: by))
        body.closeSubpath()
        g.fill(body, with: .color(ink))
    }

    /// Una silueta de gato sentado.
    static func cat(_ g: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ eye: Color) {
        g.fill(ellipse(cx, by - s * 0.33, s * 0.42, s * 0.33), with: .color(ink))
        g.fill(circle(cx + s * 0.26, by - s * 0.78, s * 0.24), with: .color(ink))
        var ears = Path()
        ears.move(to: CGPoint(x: cx + s * 0.07, y: by - s * 0.88))
        ears.addLine(to: CGPoint(x: cx + s * 0.1, y: by - s * 1.12))
        ears.addLine(to: CGPoint(x: cx + s * 0.25, y: by - s * 0.98))
        ears.closeSubpath()
        ears.move(to: CGPoint(x: cx + s * 0.28, y: by - s * 0.98))
        ears.addLine(to: CGPoint(x: cx + s * 0.43, y: by - s * 1.12))
        ears.addLine(to: CGPoint(x: cx + s * 0.45, y: by - s * 0.86))
        ears.closeSubpath()
        g.fill(ears, with: .color(ink))
        var tail = Path()
        tail.move(to: CGPoint(x: cx - s * 0.38, y: by - s * 0.3))
        tail.addQuadCurve(to: CGPoint(x: cx - s * 0.62, y: by - s * 0.98), control: CGPoint(x: cx - s * 0.85, y: by - s * 0.4))
        g.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
        g.fill(circle(cx + s * 0.18, by - s * 0.8, s * 0.045), with: .color(eye))
        g.fill(circle(cx + s * 0.35, by - s * 0.8, s * 0.045), with: .color(eye))
    }

    // MARK: Formas básicas

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    /// Una ola que va de izquierda a derecha y se rellena hacia abajo.
    static func wave(_ x: CGFloat, _ w: CGFloat, _ y0: CGFloat, _ a: CGFloat, _ by: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y0))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.25, y: y0), control: CGPoint(x: x + w * 0.125, y: y0 - a))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y0), control: CGPoint(x: x + w * 0.375, y: y0 + a))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.75, y: y0), control: CGPoint(x: x + w * 0.625, y: y0 - a))
        p.addQuadCurve(to: CGPoint(x: x + w, y: y0), control: CGPoint(x: x + w * 0.875, y: y0 + a))
        p.addLine(to: CGPoint(x: x + w, y: by))
        p.addLine(to: CGPoint(x: x, y: by))
        p.closeSubpath()
        return p
    }

    /// Trama de puntitos, como la de las imprentas de cómics.
    static func dots(in rect: CGRect, spacing: CGFloat, radius: CGFloat) -> Path {
        var p = Path()
        let half = spacing / 2
        var row = ((rect.minY - half) / spacing).rounded(.down)
        while row * spacing + half - radius <= rect.maxY {
            let cy = row * spacing + half
            var col = ((rect.minX - half) / spacing).rounded(.down)
            while col * spacing + half - radius <= rect.maxX {
                let cx = col * spacing + half
                p.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                col += 1
            }
            row += 1
        }
        return p
    }

    // MARK: Utilidades

    /// Corta un texto en renglones de hasta `max` letras (como el prototipo).
    static func wrapByCount(_ text: String, max: Int) -> [String] {
        var out: [String] = []
        var cur = ""
        for word in text.split(separator: " ").map(String.init) {
            if !cur.isEmpty && (cur + " " + word).count > max {
                out.append(cur)
                cur = word
            } else {
                cur = cur.isEmpty ? word : cur + " " + word
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Un número fijo a partir de un texto, para que cada página siempre se dibuje igual.
    static func hash(_ s: String) -> Int {
        var h: Int32 = 0
        for unit in s.utf16 {
            h = h &* 31 &+ Int32(unit)
        }
        return Int(h.magnitude)
    }

    /// Aclara (amt > 0) u oscurece (amt < 0) un color.
    static func shade(_ hex: UInt32, _ amt: Double) -> UInt32 {
        func f(_ v: UInt32) -> UInt32 {
            let d = Double(v)
            let out = amt < 0 ? d * (1 + amt) : d + (255 - d) * amt
            return UInt32(max(0, min(255, out.rounded())))
        }
        return (f((hex >> 16) & 0xFF) << 16) | (f((hex >> 8) & 0xFF) << 8) | f(hex & 0xFF)
    }

    /// Qué tan claro es un color (0 = negro, 1 = blanco).
    static func lum(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }
}

/// Generador de números "al azar" que siempre da la misma serie para la misma semilla.
final class Rand {
    private var s: Int

    init(seed: Int) {
        s = seed % 233_280
    }

    func next() -> CGFloat {
        s = (s * 9301 + 49297) % 233_280
        return CGFloat(s) / 233_280
    }
}
