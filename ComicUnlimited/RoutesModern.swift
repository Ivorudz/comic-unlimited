import SwiftUI

// Pestaña Rutas, versión moderna (Personalizar → "Rutas modernas", prendida de entrada).
// Cada ruta es solo un botón grande con un dibujo propio (hecho con código, sin logos de las editoriales):
// Avengers = escudo con rayo, X-Men = hélice de ADN, Spider-Man = telaraña, Batman = ciudad de noche
// con luna y murciélagos, Liga de la Justicia = planeta con anillo y constelación.
// Efectos: fondo de colores que se mueve, entrada escalonada, dibujos que flotan, brillo que pasa,
// botón que se inclina al apretarlo y vibración. Con "Reducir movimiento" del iPhone, todo queda quieto.

struct ModernRoutesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showBasics = false
    @State private var showPicks = false
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let read = progress.readSet()
        let routes = RouteInfo.all.compactMap { info in GuideRoutesStore.route(info.id).map { ModernRoute(info: info, route: $0) } }
        let total = routes.map { progress.score($0.route, read) }.reduce(GuideProgress.Score(), +)
        let level = GuideProgress.level(for: total.points)

        ZStack {
            Theme.paper.ignoresSafeArea()
            RoutesBackdrop(colors: RouteInfo.all.map(\.color), still: reduceMotion)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Rutas")
                            .font(.system(.largeTitle, weight: .black).width(Theme.titleWidth))
                            .foregroundStyle(Theme.ink)
                            .misprint(0.6)
                        Spacer(minLength: 8)
                        // Nivel y puntos, en chiquito.
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").foregroundStyle(Theme.yellow)
                            Text("Nivel \(level.index + 1) · \(total.points)")
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Nivel \(level.index + 1), \(total.points) puntos, \(level.name)")
                        Button { showBasics = true } label: {
                            Image(systemName: "questionmark")
                                .font(.footnote.weight(.black))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Lo básico")
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    ForEach(routes.indices, id: \.self) { index in
                        let item = routes[index]
                        NavigationLink(value: CommunityRoute.guideRoute(item.info.id)) {
                            RouteHeroCard(info: item.info, title: item.route.title,
                                          fraction: essentialFraction(item.route, read),
                                          index: index, still: reduceMotion)
                        }
                        .buttonStyle(TiltPressStyle())
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 40)
                        .scaleEffect(appeared ? 1 : 0.94)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(Double(index) * 0.08), value: appeared)
                    }

                    Button { showPicks = true } label: {
                        Label("¿No sabés qué te gusta?", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(TiltPressStyle())
                    .padding(.top, 4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)

                    Text("Orden: CBRO (CBL-ReadingLists). Dibujos propios de la app.")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Rutas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if reduceMotion { appeared = true } else { withAnimation { appeared = true } }
        }
        .sheet(isPresented: $showBasics) {
            NavigationStack {
                ScrollView { GuideBasics().padding(18) }
                    .background(Theme.paper)
                    .navigationTitle("Lo básico")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Listo") { showBasics = false } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPicks) {
            NavigationStack {
                GuidePicksList()
                    .appDestinations()
                    .navigationTitle("¿No sabés qué te gusta?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Listo") { showPicks = false } }
                    }
            }
        }
    }

    private func essentialFraction(_ route: RouteData, _ read: Set<Int>) -> Double {
        let essential = route.items.filter { !$0.isExtra }
        guard !essential.isEmpty else { return 0 }
        return Double(essential.filter { read.contains($0.cvID) }.count) / Double(essential.count)
    }
}

private struct ModernRoute {
    let info: RouteInfo
    let route: RouteData
}

// MARK: - Tarjeta grande de una ruta

private struct RouteHeroCard: View {
    let info: RouteInfo
    let title: String
    let fraction: Double
    let index: Int
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            let t: Double = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase: Double = Double(index) * 1.3
            let glowX: CGFloat = 120 + CGFloat(sin(t * 0.5 + phase)) * 10
            let glowY: CGFloat = -30 + CGFloat(cos(t * 0.4 + phase)) * 8
            let dotY: CGFloat = 60 + CGFloat(sin(t * 0.6 + phase)) * 6
            let tilt: Double = sin(t * 0.8 + phase) * 3
            let bob: CGFloat = CGFloat(sin(t * 1.2 + phase)) * 5
            ZStack(alignment: .leading) {
                // Fondo: color de la ruta, más oscuro abajo, con círculos de luz.
                ZStack {
                    Color.black
                    LinearGradient(colors: [info.color, info.color.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 220, height: 220)
                        .offset(x: glowX, y: glowY)
                        .blur(radius: 2)
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 120, height: 120)
                        .offset(x: -140, y: dotY)
                }

                // El dibujo, flotando.
                RouteEmblem(routeID: info.id)
                    .frame(width: 126, height: 126)
                    .shadow(color: .white.opacity(0.45), radius: 12)
                    .rotationEffect(.degrees(tilt))
                    .offset(y: bob)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)

                // Nombre y avance.
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(.title, weight: .black).width(Theme.titleWidth))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    ProgressRing(fraction: fraction)
                }
                .padding(.leading, 22)
                .frame(maxWidth: 210, alignment: .leading)
            }
            .frame(height: 156)
            // Reflejo suave que pasa cada tanto, como una ola que baja de tarjeta en tarjeta.
            .overlay { CardSheen(time: t, delay: Double(index) * 0.22, still: still) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: info.color.opacity(0.45), radius: 18, y: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int(fraction * 100)) % de lo esencial leído")
        .accessibilityAddTraits(.isButton)
    }
}

/// Reflejo suave: cada 7 segundos pasa una luz difusa en diagonal (en 1,6 s, entra y sale despacio),
/// y arriba queda un borde de luz fijo, como un vidrio.
struct CardSheen: View {
    let time: Double
    var delay: Double = 0
    let still: Bool

    var body: some View {
        let period: Double = 7
        let duration: Double = 1.6
        let local: Double = (time + period - delay.truncatingRemainder(dividingBy: period)).truncatingRemainder(dividingBy: period)
        let active: Bool = !still && local < duration
        let raw: Double = active ? local / duration : 0
        let eased: Double = raw * raw * (3 - 2 * raw)
        let fade: Double = active ? sin(raw * .pi) : 0
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            ZStack(alignment: .topLeading) {
                // Borde de luz arriba (fijo).
                LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                    .blendMode(.plusLighter)
                // La luz que pasa.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.10), location: 0.35),
                    .init(color: .white.opacity(0.30), location: 0.5),
                    .init(color: .white.opacity(0.10), location: 0.65),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.7, height: geo.size.height * 2)
                .rotationEffect(.degrees(24))
                .offset(x: w * (CGFloat(eased) * 1.9 - 0.8), y: -geo.size.height * 0.5)
                .opacity(fade)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Aro con el porcentaje de lo esencial leído.
private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(min(fraction, 1), 0.001))
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            Text(fraction > 0 ? "\(max(1, Int(fraction * 100))) %" : "Empezar")
                .font(.footnote.weight(.heavy).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

/// Botón que se achica y se inclina un poco al apretarlo, con una vibración suave.
struct TiltPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .rotation3DEffect(.degrees(configuration.isPressed ? 6 : 0), axis: (x: 1, y: 0, z: 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

// MARK: - Encabezado moderno de una ruta (adentro de la ruta)

struct ModernRouteHeader: View {
    let info: RouteInfo
    let title: String
    let essentialRead: Int
    let essentialTotal: Int
    let medals: Int
    let eras: Int
    let points: Int
    let line: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let fraction: Double = Double(essentialRead) / Double(max(essentialTotal, 1))
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t: Double = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let tilt: Double = sin(t * 0.8) * 3
            let bob: CGFloat = CGFloat(sin(t * 1.2)) * 6
            let glowX: CGFloat = 110 + CGFloat(sin(t * 0.5)) * 12
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color.black
                    LinearGradient(colors: [info.color, info.color.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 260, height: 260)
                        .offset(x: glowX, y: -50)
                }

                RouteEmblem(routeID: info.id)
                    .frame(width: 140, height: 140)
                    .shadow(color: .white.opacity(0.45), radius: 14)
                    .rotationEffect(.degrees(tilt))
                    .offset(y: bob)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.top, 18)
                    .padding(.trailing, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(.largeTitle, weight: .black).width(Theme.titleWidth))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .frame(maxWidth: 220, alignment: .leading)
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.25), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(fraction * 100))%")
                                .font(.caption2.weight(.heavy).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(essentialRead) de \(essentialTotal)")
                                .font(.headline.weight(.heavy).monospacedDigit())
                                .foregroundStyle(.white)
                            Text("esenciales leídos")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    HStack(spacing: 8) {
                        chip("medal.fill", "\(medals)/\(eras)")
                        chip("star.fill", "\(points) pts")
                    }
                    Text(line)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(20)
            }
            .frame(height: 250)
            .overlay { CardSheen(time: t, still: reduceMotion) }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .shadow(color: info.color.opacity(0.45), radius: 20, y: 12)
        }
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.18), in: Capsule())
    }
}

// MARK: - Fondo de colores que se mueve

struct RoutesBackdrop: View {
    let colors: [Color]
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { timeline in
            let t: Double = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    ForEach(colors.indices, id: \.self) { i in
                        BackdropBlob(color: colors[i], index: i, time: t, size: geo.size)
                    }
                }
                .blur(radius: 70)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Una mancha de color del fondo, en su lugar según el tiempo.
private struct BackdropBlob: View {
    let color: Color
    let index: Int
    let time: Double
    let size: CGSize

    var body: some View {
        let a: Double = Double(index) * 1.7
        let fx: CGFloat = 0.5 + 0.38 * CGFloat(sin(time * 0.07 + a))
        let fy: CGFloat = 0.15 + 0.18 * CGFloat(index) + 0.05 * CGFloat(cos(time * 0.09 + a))
        let side: CGFloat = size.width * 0.8
        Circle()
            .fill(color.opacity(0.32))
            .frame(width: side, height: side)
            .position(x: size.width * fx, y: size.height * fy)
    }
}

// MARK: - Dibujos de cada ruta (hechos con código)

struct RouteEmblem: View {
    let routeID: String

    var body: some View {
        Canvas { context, size in
            EmblemDrawing.draw(routeID, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }
}

/// Cada dibujo en su propia función (con números de tipo CGFloat), para que el compilador los revise rápido.
private enum EmblemDrawing {
    static func draw(_ routeID: String, in context: inout GraphicsContext, size: CGSize) {
        let pen = Pen(width: size.width, height: size.height)
        switch routeID {
        case "avengers": shield(&context, pen)
        case "xmen": helix(&context, pen)
        case "spiderman": web(&context, pen)
        case "batman": night(&context, pen)
        default: planet(&context, pen)
        }
    }

    /// Pasa de coordenadas de 0 a 1 al tamaño real.
    struct Pen {
        let width: CGFloat
        let height: CGFloat
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * width, y: y * height) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * width, y: y * height, width: w * width, height: h * height)
        }
        func line(_ fraction: CGFloat) -> CGFloat { fraction * width }
    }

    static let white = GraphicsContext.Shading.color(.white)

    static func soft(_ opacity: Double) -> GraphicsContext.Shading {
        .color(Color.white.opacity(opacity))
    }

    // Escudo con un rayo.
    static func shield(_ context: inout GraphicsContext, _ pen: Pen) {
        var outline = Path()
        outline.move(to: pen.p(0.5, 0.05))
        outline.addLine(to: pen.p(0.9, 0.18))
        outline.addLine(to: pen.p(0.88, 0.52))
        outline.addQuadCurve(to: pen.p(0.5, 0.96), control: pen.p(0.84, 0.82))
        outline.addQuadCurve(to: pen.p(0.12, 0.52), control: pen.p(0.16, 0.82))
        outline.addLine(to: pen.p(0.1, 0.18))
        outline.closeSubpath()
        context.fill(outline, with: soft(0.16))
        context.stroke(outline, with: white, style: StrokeStyle(lineWidth: pen.line(0.055), lineJoin: .round))

        var bolt = Path()
        let points: [CGPoint] = [pen.p(0.58, 0.2), pen.p(0.35, 0.56), pen.p(0.49, 0.56), pen.p(0.41, 0.82),
                                 pen.p(0.67, 0.44), pen.p(0.53, 0.44), pen.p(0.62, 0.2)]
        bolt.addLines(points)
        bolt.closeSubpath()
        context.fill(bolt, with: white)
    }

    // Hélice de ADN.
    static func helix(_ context: inout GraphicsContext, _ pen: Pen) {
        var left = Path()
        var right = Path()
        let steps = 60
        for step in 0...steps {
            let y: CGFloat = 0.04 + 0.92 * CGFloat(step) / CGFloat(steps)
            let x: CGFloat = 0.28 * sin(y * .pi * 3)
            if step == 0 {
                left.move(to: pen.p(0.5 + x, y))
                right.move(to: pen.p(0.5 - x, y))
            } else {
                left.addLine(to: pen.p(0.5 + x, y))
                right.addLine(to: pen.p(0.5 - x, y))
            }
        }
        var rungs = Path()
        var y: CGFloat = 0.1
        while y < 0.95 {
            let x: CGFloat = 0.28 * sin(y * .pi * 3)
            rungs.move(to: pen.p(0.5 + x, y))
            rungs.addLine(to: pen.p(0.5 - x, y))
            y += 0.075
        }
        context.stroke(rungs, with: soft(0.6), style: StrokeStyle(lineWidth: pen.line(0.03), lineCap: .round))
        context.stroke(left, with: white, style: StrokeStyle(lineWidth: pen.line(0.055), lineCap: .round))
        context.stroke(right, with: soft(0.85), style: StrokeStyle(lineWidth: pen.line(0.055), lineCap: .round))
    }

    // Telaraña con una arañita colgando.
    static func web(_ context: inout GraphicsContext, _ pen: Pen) {
        let cx: CGFloat = 0.42
        let cy: CGFloat = 0.42
        let spokes = 8
        var threads = Path()
        for i in 0..<spokes {
            let a: CGFloat = CGFloat(i) / CGFloat(spokes) * 2 * .pi
            threads.move(to: pen.p(cx, cy))
            threads.addLine(to: pen.p(cx + cos(a) * 0.42, cy + sin(a) * 0.42))
        }
        let radii: [CGFloat] = [0.12, 0.21, 0.3, 0.39]
        for r in radii {
            for i in 0..<spokes {
                let a1: CGFloat = CGFloat(i) / CGFloat(spokes) * 2 * .pi
                let a2: CGFloat = CGFloat(i + 1) / CGFloat(spokes) * 2 * .pi
                let mid: CGFloat = (a1 + a2) / 2
                let inner: CGFloat = r * 0.82
                threads.move(to: pen.p(cx + cos(a1) * r, cy + sin(a1) * r))
                threads.addQuadCurve(to: pen.p(cx + cos(a2) * r, cy + sin(a2) * r),
                                     control: pen.p(cx + cos(mid) * inner, cy + sin(mid) * inner))
            }
        }
        context.stroke(threads, with: white, style: StrokeStyle(lineWidth: pen.line(0.022), lineCap: .round))

        var thread = Path()
        thread.move(to: pen.p(0.8, 0))
        thread.addLine(to: pen.p(0.8, 0.74))
        context.stroke(thread, with: soft(0.8), lineWidth: pen.line(0.015))

        var legs = Path()
        let sides: [CGFloat] = [-1, 1]
        for side in sides {
            for k in 0..<4 {
                let ly: CGFloat = 0.77 + CGFloat(k) * 0.035
                legs.move(to: pen.p(0.8, ly))
                legs.addQuadCurve(to: pen.p(0.8 + side * 0.1, ly + 0.04), control: pen.p(0.8 + side * 0.08, ly - 0.04))
            }
        }
        context.stroke(legs, with: white, style: StrokeStyle(lineWidth: pen.line(0.018), lineCap: .round))
        context.fill(Path(ellipseIn: pen.rect(0.765, 0.74, 0.07, 0.07)), with: white)
        context.fill(Path(ellipseIn: pen.rect(0.75, 0.79, 0.1, 0.12)), with: white)
    }

    // Luna creciente, murciélagos y ciudad de noche.
    static func night(_ context: inout GraphicsContext, _ pen: Pen) {
        let moon = Path(ellipseIn: pen.rect(0.52, 0.06, 0.34, 0.34))
        let bite = Path(ellipseIn: pen.rect(0.6, 0.02, 0.32, 0.32))
        context.drawLayer { layer in
            layer.fill(moon, with: white)
            layer.blendMode = .destinationOut
            layer.fill(bite, with: white)
        }
        context.fill(bat(pen, 0.3, 0.22, 0.09), with: white)
        context.fill(bat(pen, 0.16, 0.38, 0.06), with: soft(0.85))
        context.fill(bat(pen, 0.42, 0.42, 0.05), with: soft(0.75))

        var city = Path()
        let xs: [CGFloat] = [0.0, 0.12, 0.22, 0.36, 0.44, 0.6, 0.7, 0.84]
        let widths: [CGFloat] = [0.12, 0.1, 0.14, 0.08, 0.16, 0.1, 0.14, 0.16]
        let tops: [CGFloat] = [0.7, 0.58, 0.66, 0.52, 0.62, 0.55, 0.68, 0.6]
        for i in xs.indices {
            city.addRect(pen.rect(xs[i], tops[i], widths[i], 1 - tops[i]))
        }
        context.fill(city, with: white)
    }

    static func bat(_ pen: Pen, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) -> Path {
        let xs: [CGFloat] = [-1, -0.35, -0.15, 0, 0.15, 0.35, 1, 0.6, 0.3, 0, -0.3, -0.6]
        let ys: [CGFloat] = [0, -0.15, -0.35, -0.2, -0.35, -0.15, 0, 0.15, 0.05, 0.3, 0.05, 0.15]
        var points: [CGPoint] = []
        for i in xs.indices {
            points.append(pen.p(cx + xs[i] * s, cy + ys[i] * s))
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    // Planeta con anillo y una constelación.
    static func planet(_ context: inout GraphicsContext, _ pen: Pen) {
        let sx: [CGFloat] = [0.1, 0.26, 0.42, 0.82, 0.9, 0.12, 0.86]
        let sy: [CGFloat] = [0.18, 0.08, 0.16, 0.12, 0.3, 0.82, 0.86]
        var lines = Path()
        lines.addLines([pen.p(sx[0], sy[0]), pen.p(sx[1], sy[1]), pen.p(sx[2], sy[2])])
        lines.move(to: pen.p(sx[3], sy[3]))
        lines.addLine(to: pen.p(sx[4], sy[4]))
        context.stroke(lines, with: soft(0.55), lineWidth: pen.line(0.012))
        for i in sx.indices {
            context.fill(Path(ellipseIn: pen.rect(sx[i] - 0.022, sy[i] - 0.022, 0.044, 0.044)), with: white)
        }

        let center = pen.p(0.5, 0.54)
        let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
        let turn = CGAffineTransform(rotationAngle: -0.35)
        let back = CGAffineTransform(translationX: center.x, y: center.y)
        let ring = Path(ellipseIn: pen.rect(0.08, 0.44, 0.84, 0.2))
            .applying(toOrigin.concatenating(turn).concatenating(back))
        context.stroke(ring, with: soft(0.9), lineWidth: pen.line(0.035))
        context.fill(Path(ellipseIn: pen.rect(0.3, 0.34, 0.4, 0.4)), with: white)
    }
}

// MARK: - "Lo básico" y recomendaciones, para usar en hojas

struct GuideBasics: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            term("Número (#)", "Cada revista que sale, por ejemplo Batman #1 (unas 20 a 30 páginas).")
            term("Serie", "Todos los números de un título. Cuando vuelve a empezar desde el #1 es un \"volumen\" nuevo: por eso ves el año al lado del nombre.")
            term("Evento", "Una historia grande que cruza muchas series. En el camino \"Esencial\" está solo su centro; los cruces con otras series son extras.")
            term("Era", "Una época de la editorial (por ejemplo Marvel Disassembled o Los Nuevos 52). Completar lo esencial de una era da una medalla.")
            term("Puntos", "Cada número leído de una ruta suma 10 (los extras, 20). Las tapas a color son las que tenés en tu Biblioteca.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func term(_ name: String, _ text: String) -> some View {
        (Text(name + ": ").bold().foregroundColor(Theme.ink) + Text(text).foregroundColor(Theme.ink2))
            .font(.subheadline)
    }
}

/// "¿No sabés qué te gusta?": las recomendaciones sueltas.
struct GuidePicksList: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(StartGuide.picks) { group in
                    Text(group.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                        .padding(.bottom, 8)
                        .padding(.top, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(group.picks) { pick in
                                NavigationLink(value: CommunityRoute.guideSeries(pick.query, pick.year, pick.title)) {
                                    PickCard(pick: pick)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
    }
}
