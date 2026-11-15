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
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase = Double(index) * 1.3
            ZStack(alignment: .leading) {
                // Fondo: color de la ruta, más oscuro abajo, con círculos de luz.
                ZStack {
                    Color.black
                    LinearGradient(colors: [info.color, info.color.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 220, height: 220)
                        .offset(x: 120 + sin(t * 0.5 + phase) * 10, y: -30 + cos(t * 0.4 + phase) * 8)
                        .blur(radius: 2)
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 120, height: 120)
                        .offset(x: -140, y: 60 + sin(t * 0.6 + phase) * 6)
                }

                // El dibujo, flotando.
                RouteEmblem(routeID: info.id)
                    .frame(width: 126, height: 126)
                    .shadow(color: .white.opacity(0.45), radius: 12)
                    .rotationEffect(.degrees(sin(t * 0.8 + phase) * 3))
                    .offset(y: sin(t * 1.2 + phase) * 5)
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
            // Un brillo que pasa cada tanto.
            .overlay {
                GeometryReader { geo in
                    let cycle = (t * 0.22 + Double(index) * 0.17).truncatingRemainder(dividingBy: 1)
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.35)
                        .rotationEffect(.degrees(18))
                        .offset(x: -geo.size.width * 0.5 + cycle * geo.size.width * 2.2)
                        .opacity(still ? 0 : 1)
                }
                .allowsHitTesting(false)
            }
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

// MARK: - Fondo de colores que se mueve

private struct RoutesBackdrop: View {
    let colors: [Color]
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    ForEach(colors.indices, id: \.self) { i in
                        let a = Double(i) * 1.7
                        Circle()
                            .fill(colors[i].opacity(0.32))
                            .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                            .position(x: geo.size.width * (0.5 + 0.38 * sin(t * 0.07 + a)),
                                      y: geo.size.height * (0.15 + 0.18 * Double(i) + 0.05 * cos(t * 0.09 + a)))
                    }
                }
                .blur(radius: 70)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dibujos de cada ruta (hechos con código)

struct RouteEmblem: View {
    let routeID: String

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let white = GraphicsContext.Shading.color(.white)
            switch routeID {
            case "avengers":
                // Escudo con un rayo.
                var shield = Path()
                shield.move(to: p(0.5, 0.05))
                shield.addLine(to: p(0.9, 0.18))
                shield.addLine(to: p(0.88, 0.52))
                shield.addQuadCurve(to: p(0.5, 0.96), control: p(0.84, 0.82))
                shield.addQuadCurve(to: p(0.12, 0.52), control: p(0.16, 0.82))
                shield.addLine(to: p(0.1, 0.18))
                shield.closeSubpath()
                context.fill(shield, with: .color(.white.opacity(0.16)))
                context.stroke(shield, with: white, style: StrokeStyle(lineWidth: w * 0.055, lineJoin: .round))
                var bolt = Path()
                bolt.addLines([p(0.58, 0.2), p(0.35, 0.56), p(0.49, 0.56), p(0.41, 0.82), p(0.67, 0.44), p(0.53, 0.44), p(0.62, 0.2)])
                bolt.closeSubpath()
                context.fill(bolt, with: white)
            case "xmen":
                // Hélice de ADN.
                var left = Path(), right = Path()
                let steps = 60
                for s in 0...steps {
                    let y = 0.04 + 0.92 * Double(s) / Double(steps)
                    let x = 0.28 * sin(y * .pi * 3)
                    if s == 0 { left.move(to: p(0.5 + x, y)); right.move(to: p(0.5 - x, y)) } else {
                        left.addLine(to: p(0.5 + x, y)); right.addLine(to: p(0.5 - x, y))
                    }
                }
                var rungs = Path()
                var y = 0.1
                while y < 0.95 {
                    let x = 0.28 * sin(y * .pi * 3)
                    rungs.move(to: p(0.5 + x, y)); rungs.addLine(to: p(0.5 - x, y))
                    y += 0.075
                }
                context.stroke(rungs, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
                context.stroke(left, with: white, style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round))
                context.stroke(right, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round))
            case "spiderman":
                // Telaraña con una arañita colgando.
                let c = p(0.42, 0.42)
                let spokes = 8
                var web = Path()
                for i in 0..<spokes {
                    let a = Double(i) / Double(spokes) * 2 * .pi
                    web.move(to: c)
                    web.addLine(to: CGPoint(x: c.x + cos(a) * w * 0.42, y: c.y + sin(a) * h * 0.42))
                }
                for r in [0.12, 0.21, 0.3, 0.39] {
                    for i in 0..<spokes {
                        let a1 = Double(i) / Double(spokes) * 2 * .pi
                        let a2 = Double(i + 1) / Double(spokes) * 2 * .pi
                        let m = (a1 + a2) / 2
                        let p1 = CGPoint(x: c.x + cos(a1) * w * r, y: c.y + sin(a1) * h * r)
                        let p2 = CGPoint(x: c.x + cos(a2) * w * r, y: c.y + sin(a2) * h * r)
                        let ctrl = CGPoint(x: c.x + cos(m) * w * r * 0.82, y: c.y + sin(m) * h * r * 0.82)
                        web.move(to: p1)
                        web.addQuadCurve(to: p2, control: ctrl)
                    }
                }
                context.stroke(web, with: white, style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
                var thread = Path()
                thread.move(to: p(0.8, 0.0)); thread.addLine(to: p(0.8, 0.74))
                context.stroke(thread, with: .color(.white.opacity(0.8)), lineWidth: w * 0.015)
                var legs = Path()
                for side in [-1.0, 1.0] {
                    for k in 0..<4 {
                        let yy = 0.77 + Double(k) * 0.035
                        legs.move(to: p(0.8, yy))
                        legs.addQuadCurve(to: p(0.8 + side * 0.1, yy + 0.04), control: p(0.8 + side * 0.08, yy - 0.04))
                    }
                }
                context.stroke(legs, with: white, style: StrokeStyle(lineWidth: w * 0.018, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 0.765 * w, y: 0.74 * h, width: 0.07 * w, height: 0.07 * h)), with: white)
                context.fill(Path(ellipseIn: CGRect(x: 0.75 * w, y: 0.79 * h, width: 0.1 * w, height: 0.12 * h)), with: white)
            case "batman":
                // Luna creciente, murciélagos y ciudad de noche.
                context.drawLayer { layer in
                    layer.fill(Path(ellipseIn: CGRect(x: 0.52 * w, y: 0.06 * h, width: 0.34 * w, height: 0.34 * h)), with: white)
                    layer.blendMode = .destinationOut
                    layer.fill(Path(ellipseIn: CGRect(x: 0.6 * w, y: 0.02 * h, width: 0.32 * w, height: 0.32 * h)), with: white)
                }
                func bat(_ cx: Double, _ cy: Double, _ s: Double) -> Path {
                    var b = Path()
                    let pts: [(Double, Double)] = [(-1, 0), (-0.35, -0.15), (-0.15, -0.35), (0, -0.2), (0.15, -0.35), (0.35, -0.15),
                                                   (1, 0), (0.6, 0.15), (0.3, 0.05), (0, 0.3), (-0.3, 0.05), (-0.6, 0.15)]
                    b.addLines(pts.map { p(cx + $0.0 * s, cy + $0.1 * s) })
                    b.closeSubpath()
                    return b
                }
                context.fill(bat(0.3, 0.22, 0.09), with: white)
                context.fill(bat(0.16, 0.38, 0.06), with: .color(.white.opacity(0.85)))
                context.fill(bat(0.42, 0.42, 0.05), with: .color(.white.opacity(0.75)))
                var city = Path()
                let buildings: [(Double, Double, Double)] = [(0.0, 0.12, 0.7), (0.12, 0.1, 0.58), (0.22, 0.14, 0.66), (0.36, 0.08, 0.52),
                                                            (0.44, 0.16, 0.62), (0.6, 0.1, 0.55), (0.7, 0.14, 0.68), (0.84, 0.16, 0.6)]
                for b in buildings {
                    city.addRect(CGRect(x: b.0 * w, y: b.2 * h, width: b.1 * w, height: (1 - b.2) * h))
                }
                context.fill(city, with: white)
            default:
                // Planeta con anillo y constelación.
                let stars: [(Double, Double)] = [(0.1, 0.18), (0.26, 0.08), (0.42, 0.16), (0.82, 0.12), (0.9, 0.3), (0.12, 0.82), (0.86, 0.86)]
                var lines = Path()
                lines.addLines(stars.prefix(3).map { p($0.0, $0.1) })
                lines.move(to: p(0.82, 0.12)); lines.addLine(to: p(0.9, 0.3))
                context.stroke(lines, with: .color(.white.opacity(0.55)), lineWidth: w * 0.012)
                for s in stars {
                    context.fill(Path(ellipseIn: CGRect(x: (s.0 - 0.022) * w, y: (s.1 - 0.022) * h, width: 0.044 * w, height: 0.044 * h)), with: white)
                }
                let ring = Path(ellipseIn: CGRect(x: 0.08 * w, y: 0.44 * h, width: 0.84 * w, height: 0.2 * h))
                    .applying(CGAffineTransform(translationX: -0.5 * w, y: -0.54 * h)
                        .concatenating(CGAffineTransform(rotationAngle: -0.35))
                        .concatenating(CGAffineTransform(translationX: 0.5 * w, y: 0.54 * h)))
                context.stroke(ring, with: .color(.white.opacity(0.9)), lineWidth: w * 0.035)
                context.fill(Path(ellipseIn: CGRect(x: 0.3 * w, y: 0.34 * h, width: 0.4 * w, height: 0.4 * h)), with: white)
            }
        }
        .accessibilityHidden(true)
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
