import SwiftUI
import UIKit

// Lector para tus cómics en archivo (.cbz, .zip o PDF).
// - Dirección: izquierda a derecha, derecha a izquierda (manga) o vertical continua.
// - Ajuste de página: entera, llenar el ancho o llenar el alto.
// - Tocar los bordes pasa de página (se puede apagar); tocar el centro muestra u oculta los controles.
// - Abajo: miniaturas y barra para saltar de página.
// - Pantalla siempre encendida y modo nocturno (calidez y oscuridad a gusto).
// Todo se elige en el engranaje (⚙︎) del lector y queda guardado.

/// Saca las páginas del archivo de a una, en segundo plano, y recuerda las últimas que usó.
actor PageLoader {
    private let file: ComicFile
    private let cache = NSCache<NSString, UIImage>()
    let pageCount: Int

    init(file: ComicFile) {
        self.file = file
        pageCount = file.pageCount
        cache.countLimit = 40
        cache.totalCostLimit = 160_000_000
    }

    func image(_ index: Int, maxWidth: CGFloat) -> UIImage? {
        let crop = UserDefaults.standard.bool(forKey: ReaderSettings.cropMargins)
        let key = "\(index)-\(Int(maxWidth))-\(crop)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard var image = file.page(index, maxWidth: maxWidth) else { return nil }
        if crop { image = Self.trimmingWhiteMargins(image) }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Recorta los bordes blancos de una página escaneada (como mucho un 12 % de cada lado,
    /// para no cortar dibujo). Si no hay bordes, la deja igual.
    static func trimmingWhiteMargins(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width > 20, cg.height > 20 else { return image }
        // Se analiza una copia chiquita, que es rápido.
        let w = 160, h = max(20, Int(CGFloat(cg.height) * 160 / CGFloat(cg.width)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return image }
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return pixels[i] > 232 && pixels[i + 1] > 232 && pixels[i + 2] > 232
        }
        // Una fila o columna es "borde" si casi todos sus puntos son blancos.
        func rowBlank(_ y: Int) -> Bool { (0..<w).filter { !isWhite($0, y) }.count <= w / 100 + 1 }
        func colBlank(_ x: Int) -> Bool { (0..<h).filter { !isWhite(x, $0) }.count <= h / 100 + 1 }
        let maxY = h * 12 / 100, maxX = w * 12 / 100
        var top = 0; while top < maxY && rowBlank(top) { top += 1 }
        var bottom = 0; while bottom < maxY && rowBlank(h - 1 - bottom) { bottom += 1 }
        var left = 0; while left < maxX && colBlank(left) { left += 1 }
        var right = 0; while right < maxX && colBlank(w - 1 - right) { right += 1 }
        guard top + bottom + left + right > 2 else { return image }
        // La fila 0 de la copia chiquita es la de arriba de la página (igual que al recortar).
        let sx = CGFloat(cg.width) / CGFloat(w), sy = CGFloat(cg.height) / CGFloat(h)
        let rect = CGRect(x: CGFloat(left) * sx, y: CGFloat(top) * sy,
                          width: CGFloat(w - left - right) * sx, height: CGFloat(h - top - bottom) * sy)
        guard let cropped = cg.cropping(to: rect.integral) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Miniatura chiquita para la tira de abajo.
    func thumbnail(_ index: Int) -> UIImage? { image(index, maxWidth: 140) }

    /// Dos páginas juntas en una sola imagen (para el teléfono de costado).
    /// `pages` va en el orden en que se ven, de izquierda a derecha.
    func spread(_ pages: [Int], maxWidth: CGFloat) -> UIImage? {
        let crop = UserDefaults.standard.bool(forKey: ReaderSettings.cropMargins)
        let key = "spread-\(pages.map(String.init).joined(separator: "-"))-\(Int(maxWidth))-\(crop)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let images = pages.compactMap { image($0, maxWidth: maxWidth / CGFloat(max(pages.count, 1))) }
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images[0] }
        let height = images.map(\.size.height).max() ?? 1
        // Las dos a la misma altura.
        let widths = images.map { $0.size.width * height / max($0.size.height, 1) }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let result = UIGraphicsImageRenderer(size: CGSize(width: widths.reduce(0, +), height: height), format: format)
            .image { _ in
                var x: CGFloat = 0
                for (img, w) in zip(images, widths) {
                    img.draw(in: CGRect(x: x, y: 0, width: w, height: height))
                    x += w
                }
            }
        let cost = Int(result.size.width * result.size.height * 4)
        cache.setObject(result, forKey: key, cost: cost)
        return result
    }
}

// MARK: - Preferencias del lector

enum ReaderDirection: String, CaseIterable, Identifiable {
    case leftToRight, rightToLeft, vertical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leftToRight: return "Izq → der"
        case .rightToLeft: return "Der → izq"
        case .vertical: return "Vertical"
        }
    }
}

enum ReaderFit: String, CaseIterable, Identifiable {
    case page, width, height
    var id: String { rawValue }
    var label: String {
        switch self {
        case .page: return "Entera"
        case .width: return "Al ancho"
        case .height: return "Al alto"
        }
    }
}

enum ReaderSettings {
    static let direction = "reader.direction"
    static let fit = "reader.fit"
    static let tapEdges = "reader.tapEdges"
    static let thumbnails = "reader.thumbnails"
    static let keepAwake = "reader.keepAwake"
    static let night = "reader.night"
    static let warmth = "reader.warmth"
    static let dim = "reader.dim"
    static let doublePage = "reader.doublePage"
    static let cropMargins = "reader.cropMargins"
    static let brightnessOn = "reader.brightnessOn"
    static let brightness = "reader.brightness"
    static let clock = "reader.clock"
}

/// Deslizar hacia abajo para cerrar: la página (UIKit) avisa cuánto la arrastraste y el lector se mueve.
/// Solo vale el lector abierto (por si por un momento hay dos: al pasar al siguiente número).
enum ReaderPull {
    static var handler: ((CGFloat, Bool, CGFloat) -> Void)?
    static var owner: UUID?
    static var enabled = true
}

/// Brillo propio del lector: guarda el del iPhone al abrir y lo devuelve al cerrar.
enum ReaderBrightness {
    private static var saved: CGFloat?

    static func apply(_ on: Bool, _ value: Double) {
        if on {
            if saved == nil { saved = UIScreen.main.brightness }
            UIScreen.main.brightness = CGFloat(value)
        } else {
            restore()
        }
    }

    static func restore() {
        if let saved { UIScreen.main.brightness = saved }
        saved = nil
    }
}

// MARK: - Lector

struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let comic: LocalComic
    /// Abrir el siguiente número (lo maneja quien abrió el lector).
    var onOpenNext: ((LocalComic) -> Void)? = nil

    /// Opciones de siempre; cada serie puede tener las suyas (ReadingProfiles.swift).
    @AppStorage(ReaderSettings.direction) private var globalDirection: ReaderDirection = .leftToRight
    @AppStorage(ReaderSettings.fit) private var globalFit: ReaderFit = .page
    @AppStorage(ReadingProfiles.autoMangaKey) private var autoManga = true
    @AppStorage(ReaderSettings.tapEdges) private var tapEdges = true
    @AppStorage(ReaderSettings.thumbnails) private var thumbnails = true
    @AppStorage(ReaderSettings.keepAwake) private var keepAwake = true
    @AppStorage(ReaderSettings.night) private var night = false
    @AppStorage(ReaderSettings.warmth) private var warmth = 0.5
    @AppStorage(ReaderSettings.dim) private var dim = 0.25
    @AppStorage(ReaderSettings.doublePage) private var doublePage = true
    @AppStorage(ReaderSettings.cropMargins) private var cropMargins = false
    @AppStorage(ReaderSettings.brightnessOn) private var brightnessOn = false
    @AppStorage(ReaderSettings.brightness) private var brightness = 0.6
    @AppStorage(ReaderSettings.clock) private var showClock = true
    @Environment(\.scenePhase) private var scenePhase

    /// Cuánto arrastraste la página hacia abajo (para cerrar).
    @State private var pullDown: CGFloat = 0
    /// Página elegida en la barra mientras la arrastrás (se va a esa página al soltar).
    @State private var scrubPage: Double?
    /// Segundos por página según tu historial (para "quedan ~N min").
    @State private var secondsPerPage: Double = 25
    /// Brillo: se está deslizando en el rincón de abajo a la izquierda (se ve la barrita).
    @State private var adjustingBrightness = false
    @State private var brightnessStart: Double = 0
    @State private var hideBrightness: Task<Void, Never>?
    /// Candado de giro.
    @State private var rotationLocked = false
    @State private var readerID = UUID()

    @State private var page: Int
    @State private var showControls = true
    @State private var showSettings = false
    @State private var showMarks = false
    /// Lo terminaste en esta lectura (al cerrar, se marca como leído en Metron).
    @State private var finishedHere = false
    @State private var loader: PageLoader?
    @State private var errorText: String?
    /// Para el historial: cuándo abriste el cómic y qué páginas viste.
    @State private var openedAt = Date()
    @State private var seenPages: Set<Int> = []

    init(comic: LocalComic, startPage: Int, onOpenNext: ((LocalComic) -> Void)? = nil) {
        self.comic = comic
        self.onOpenNext = onOpenNext
        _page = State(initialValue: startPage)
    }

    private var pageCount: Int { loader?.pageCount ?? comic.pageCount }
    /// El cómic con lo último guardado (marcadores, números del TPB…).
    private var live: LocalComic { LocalLibrary.shared.item(comic.id) ?? comic }
    private var isBookmarked: Bool { live.bookmarks?.contains(page) == true }
    /// Dirección y tamaño que valen para este cómic (los de su serie, manga o los de siempre).
    private var direction: ReaderDirection {
        ReadingProfiles.shared.direction(for: live, global: globalDirection, autoManga: autoManga)
    }
    private var fit: ReaderFit { ReadingProfiles.shared.fit(for: live, global: globalFit) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let loader {
                    pages(loader, size: geo.size)
                        .offset(y: pullDown)
                        .scaleEffect(1 - min(pullDown, 400) / 2000)
                } else if let errorText {
                    VStack(spacing: 14) {
                        Text(errorText).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button("Cerrar") { dismiss() }.foregroundStyle(Theme.magenta)
                    }
                    .padding(30)
                } else {
                    ProgressView().tint(.white)
                }

                if night { nightFilter }

                if adjustingBrightness {
                    BrightnessIndicator(value: brightness)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 18)
                        .padding(.bottom, showControls ? 150 : 24)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomLeading)))
                        .zIndex(2)
                }

                if (showControls || page == pageCount) && pullDown == 0 {
                    controls.transition(.opacity)
                } else if showClock && pullDown == 0 && page < pageCount {
                    ReaderClock()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 2)
                        .allowsHitTesting(false)
                }
            }
        }
        // Brillo como en Netflix: deslizar hacia arriba o abajo en el rincón de abajo a la izquierda.
        .background(
            BrightnessCornerGesture(
                onBegan: {
                    brightnessStart = brightnessOn ? brightness : Double(UIScreen.main.brightness)
                    hideBrightness?.cancel()
                    withAnimation(.easeOut(duration: 0.15)) { adjustingBrightness = true }
                },
                onChanged: { moved in
                    brightness = min(max(brightnessStart + Double(-moved / 260), 0.02), 1)
                    brightnessOn = true
                },
                onEnded: {
                    hideBrightness = Task {
                        try? await Task.sleep(for: .milliseconds(900))
                        if Task.isCancelled { return }
                        withAnimation(.easeOut(duration: 0.3)) { adjustingBrightness = false }
                    }
                }
            )
        )
        .statusBarHidden(!showControls)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(comic: live)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMarks) {
            ReaderMarksSheet(comicID: comic.id, currentPage: min(page, max(pageCount - 1, 0)),
                             loader: loader) { target in
                showMarks = false
                withAnimation { page = target }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            AppOrientation.readerOpened(keepAwake: keepAwake)
            openedAt = Date()
            seenPages = [page]
            secondsPerPage = ReadingHistory.shared.secondsPerPage
            ReaderBrightness.apply(brightnessOn, brightness)
            // Deslizar hacia abajo para cerrar (no en el modo vertical, que ya se desliza hacia arriba y abajo).
            ReaderPull.owner = readerID
            ReaderPull.enabled = direction != .vertical
            ReaderPull.handler = { distance, ended, speed in
                if ended {
                    if distance > 120 || speed > 900 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pullDown = 0 }
                    }
                } else {
                    pullDown = distance
                }
            }
        }
        .onDisappear {
            // Si ya se abrió otro lector (Siguiente número), ese sigue con su brillo y su gesto.
            if ReaderPull.owner == readerID || ReaderPull.owner == nil {
                ReaderPull.handler = nil
                ReaderPull.owner = nil
                ReaderBrightness.restore()
            }
            AppOrientation.readerClosed()
            recordHistory()
            if finishedHere, let cv = live.cvIssueID {
                Task { await MetronSync.markRead(cvID: cv) }
            }
        }
        .onChange(of: keepAwake) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onChange(of: direction) { _, value in ReaderPull.enabled = value != .vertical }
        .onChange(of: brightnessOn) { _, on in ReaderBrightness.apply(on, brightness) }
        .onChange(of: brightness) { _, value in ReaderBrightness.apply(brightnessOn, value) }
        .onChange(of: scenePhase) { _, phase in
            // Al salir de la app, el iPhone vuelve a su brillo; al volver, el del lector.
            if phase == .active { ReaderBrightness.apply(brightnessOn, brightness) } else { ReaderBrightness.restore() }
        }
        .task {
            let url = LocalLibrary.shared.fileURL(comic)
            let result: Result<ComicFile, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try ComicFile(url: url)) } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let file):
                loader = PageLoader(file: file)
                page = min(page, max(file.pageCount - 1, 0))
            case .failure(let error):
                errorText = (error as? LocalizedError)?.errorDescription ?? "No se pudo abrir el archivo."
            }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.2)) { showControls = false }
        }
        .onChange(of: page) { _, newPage in
            guard loader != nil else { return }
            if newPage < pageCount { seenPages.insert(newPage) }
            if newPage >= pageCount {
                finishedHere = true
                LocalLibrary.shared.markFinished(comic.id)
            } else {
                LocalLibrary.shared.setPage(newPage, for: comic.id)
            }
        }
    }

    /// Anota esta lectura en el historial (si pasaste alguna página o estuviste al menos 30 segundos).
    private func recordHistory() {
        let now = Date()
        let seen = seenPages.filter { $0 < pageCount }
        guard let first = seen.min(), let last = seen.max(),
              seen.count > 1 || finishedHere || now.timeIntervalSince(openedAt) >= 30 else { return }
        ReadingHistory.shared.record(ReadingSession(
            comicID: comic.id, title: live.displayTitle,
            start: openedAt.timeIntervalSince1970, end: now.timeIntervalSince1970,
            fromPage: first, toPage: last, pages: seen.count, finished: finishedHere))
    }

    // MARK: Páginas

    @ViewBuilder
    private func pages(_ loader: PageLoader, size: CGSize) -> some View {
        let scale = UIScreen.main.scale
        // "Al alto" puede necesitar páginas más anchas que la pantalla (páginas dobles).
        let decodeWidth = size.width * scale * (fit == .height ? 2 : 1)
        if direction == .vertical {
            // Hecho con UIKit para que el zoom agrande donde ponés los dedos (o donde hacés doble toque).
            VerticalReader(loader: loader, decodeWidth: size.width * scale * 1.5, page: $page) {
                withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
            }
            .id(cropMargins)   // al cambiar "Recortar bordes", se vuelven a cargar las páginas
            .ignoresSafeArea()
        } else if doublePage && size.width > size.height {
            spreadPages(loader, size: size)
        } else {
            TabView(selection: $page) {
                ForEach(0..<loader.pageCount, id: \.self) { index in
                    LocalPageView(loader: loader, index: index, maxWidth: decodeWidth, fit: fit, crop: cropMargins) { x in
                        handleTap(at: x, width: size.width)
                    }
                    .environment(\.layoutDirection, .leftToRight)   // la página nunca se da vuelta
                    .tag(index)
                }
                endCard
                    .environment(\.layoutDirection, .leftToRight)
                    .tag(loader.pageCount)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Derecha a izquierda: se pasa de página deslizando hacia la derecha (como el manga).
            .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
            .ignoresSafeArea()
        }
    }

    // MARK: Doble página (teléfono de costado)

    /// Grupos de páginas: la tapa sola y después de a dos (1-2, 3-4…).
    private func spreads(_ count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        var list: [[Int]] = [[0]]
        var i = 1
        while i < count {
            list.append(i + 1 < count ? [i, i + 1] : [i])
            i += 2
        }
        return list
    }

    private func spreadIndex(for page: Int, in spreads: [[Int]]) -> Int {
        if page >= pageCount { return spreads.count }   // "Terminaste"
        return spreads.firstIndex { $0.contains(page) } ?? 0
    }

    @ViewBuilder
    private func spreadPages(_ loader: PageLoader, size: CGSize) -> some View {
        let groups = spreads(loader.pageCount)
        let selection = Binding<Int>(
            get: { spreadIndex(for: page, in: groups) },
            set: { index in page = index < groups.count ? groups[index][0] : loader.pageCount }
        )
        TabView(selection: selection) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                // En manga, la primera página del par va a la derecha.
                SpreadPageView(loader: loader, pages: direction == .rightToLeft ? Array(group.reversed()) : group,
                               maxWidth: size.width * UIScreen.main.scale, fit: fit, crop: cropMargins) { x in
                    handleTap(at: x, width: size.width, inSpreads: true)
                }
                .environment(\.layoutDirection, .leftToRight)
                .tag(index)
            }
            endCard
                .environment(\.layoutDirection, .leftToRight)
                .tag(groups.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
        .ignoresSafeArea()
    }

    private func handleTap(at x: CGFloat, width: CGFloat, inSpreads: Bool = false) {
        let ratio = x / max(width, 1)
        let leftEdge = ratio < 0.25, rightEdge = ratio > 0.75
        guard tapEdges, leftEdge || rightEdge else {
            withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
            return
        }
        // En derecha a izquierda, el borde izquierdo avanza.
        let forward = direction == .rightToLeft ? leftEdge : rightEdge
        // Con el teléfono de costado se avanza de a dos páginas.
        let groups = spreads(pageCount)
        if inSpreads, !groups.isEmpty {
            let current = spreadIndex(for: page, in: groups)
            let next = forward ? min(groups.count, current + 1) : max(0, current - 1)
            withAnimation { page = next < groups.count ? groups[next][0] : pageCount }
            return
        }
        withAnimation { page = forward ? min(pageCount, page + 1) : max(0, page - 1) }
    }

    /// Modo nocturno: luz más cálida y más tenue (no cambia el brillo del iPhone).
    private var nightFilter: some View {
        ZStack {
            Color(red: 1, green: 0.55, blue: 0.15).opacity(warmth * 0.35).blendMode(.multiply)
            Color.black.opacity(dim * 0.8)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Controles

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 36)
                        .readerButtonBackground()
                }
                .accessibilityLabel("Cerrar lector")
                Text(comic.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if page < pageCount {
                    Button {
                        LocalLibrary.shared.toggleBookmark(page, for: comic.id)
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isBookmarked ? Theme.magenta : .white)
                            .frame(width: 40, height: 36)
                            .readerButtonBackground()
                    }
                    .accessibilityLabel(isBookmarked ? "Quitar marcador" : "Marcar esta página")
                }
                Button {
                    rotationLocked.toggle()
                    AppOrientation.lockRotation(rotationLocked)
                } label: {
                    Image(systemName: rotationLocked ? "lock.rotation" : "lock.rotation.open")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(rotationLocked ? Theme.magenta : .white)
                        .frame(width: 40, height: 36)
                        .readerButtonBackground()
                }
                .accessibilityLabel(rotationLocked ? "Destrabar el giro" : "Trabar el giro")
                Button { showMarks = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 36)
                        .readerButtonBackground()
                }
                .accessibilityLabel(live.isCollection ? "Números y marcadores" : "Marcadores")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 36)
                        .readerButtonBackground()
                }
                .accessibilityLabel("Opciones de lectura")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(LinearGradient(colors: [.black.opacity(modern ? 0.55 : 0.85), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))

            Spacer()

            // En vertical, el final no tiene tarjeta propia: "¿Qué te pareció?" y "Siguiente" van acá.
            if page >= pageCount && direction == .vertical {
                ScrollView {
                    VStack(spacing: 10) {
                        RateCard(comic: live)
                        if let next = LocalLibrary.shared.next(after: live), onOpenNext != nil { nextButton(next) }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            }

            if pageCount > 1 {
                VStack(spacing: 10) {
                    // Mientras arrastrás la barra: la página en grande, para saber adónde vas.
                    if let scrubPage, let loader {
                        ScrubPreview(loader: loader, index: min(max(Int(scrubPage.rounded()) - 1, 0), pageCount - 1))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else if thumbnails, let loader {
                        ThumbnailStrip(loader: loader, current: min(page, pageCount - 1),
                                       reversed: direction == .rightToLeft,
                                       bookmarks: Set(live.bookmarks ?? [])) { index in
                            withAnimation { page = index }
                        }
                    }
                    HStack(spacing: 12) {
                        Slider(
                            value: Binding(
                                get: { scrubPage ?? Double(min(page, pageCount - 1) + 1) },
                                set: { value in withAnimation(.easeOut(duration: 0.15)) { scrubPage = value } }
                            ),
                            in: 1...Double(pageCount),
                            step: 1,
                            onEditingChanged: { editing in
                                // Al soltar, recién ahí se va a esa página.
                                guard !editing, let target = scrubPage else { return }
                                page = Int(target.rounded()) - 1
                                withAnimation(.easeOut(duration: 0.15)) { scrubPage = nil }
                            }
                        )
                        .tint(Theme.magenta)
                        .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
                        .accessibilityLabel("Ir a la página")
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(scrubPage.map { Int($0.rounded()) } ?? (min(page, pageCount - 1) + 1)) / \(pageCount)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.white)
                            // Cuánto falta, según lo rápido que leés (historial).
                            Text(timeLeftText)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                }
                .modifier(ReaderBottomPanel(modern: modern))
            }
        }
    }

    /// Estilo moderno (Personalizar): botones y panel de vidrio.
    private var modern: Bool { AppearanceSettings.shared.modern }

    /// "Quedan ~6 min" según tu velocidad de lectura.
    private var timeLeftText: String {
        let left = max(pageCount - (min(page, pageCount - 1) + 1), 0)
        guard left > 0 else { return "Última página" }
        let minutes = Int((Double(left) * secondsPerPage / 60).rounded())
        return minutes < 1 ? "Menos de 1 min" : "~\(minutes) min"
    }

    private func nextButton(_ next: (comic: LocalComic, label: String)) -> some View {
        Button {
            onOpenNext?(next.comic)
        } label: {
            HStack(spacing: 12) {
                if modern {
                    // La tapa del que sigue.
                    LocalCover(comic: next.comic).frame(width: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.label).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Text(next.comic.displayTitle).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle.fill").font(.title2)
            }
            .foregroundStyle(.white)
            .padding(12)
            .modifier(NextButtonBackground(modern: modern))
        }
        .buttonStyle(CardPressStyle())
    }

    private var endCard: some View {
        // Se puede deslizar hacia arriba (con "¿Qué te pareció?" no entra en pantallas chicas).
        ScrollView {
        VStack(spacing: 12) {
            if modern {
                // Sello de "terminado" con tu color.
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.magenta)
                    .shadow(color: Theme.magenta.opacity(0.7), radius: 18)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            Text("Terminaste")
                .font(.headline)
                .foregroundStyle(Theme.magenta)
            Text(comic.displayTitle)
                .font(.system(size: 28, weight: .black).width(Theme.titleWidth))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Quedó guardado como leído.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 4)
            // Si es de una ruta de la guía "Por dónde empezar", suma puntos.
            if let reward = GuideProgress.shared.reward(for: live) {
                Label("+\(reward.points) puntos · Ruta \(reward.routes.joined(separator: " y "))",
                      systemImage: "star.circle.fill")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color(hex: 0x121419))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xFFD400), in: Capsule())
            }
            RateCard(comic: live)
            if let next = LocalLibrary.shared.next(after: live), onOpenNext != nil {
                nextButton(next)
            }
            Button {
                withAnimation { page = 0 }
            } label: {
                Text("Volver a empezar")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .readerButtonBackground()
            }
            Button { dismiss() } label: {
                Text("Cerrar")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .overlay(Capsule().stroke(.white.opacity(0.3)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 330)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
        .background {
            // Con el estilo moderno, de fondo la tapa del cómic que terminaste, difuminada.
            if modern {
                Color.black
                    .overlay {
                        LocalCover(comic: live)
                            .scaleEffect(1.5)
                            .blur(radius: 50)
                            .opacity(0.55)
                    }
                    .clipped()
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Opciones (engranaje)

struct ReaderSettingsSheet: View {
    /// El cómic que estás leyendo (para "Recordar para esta serie").
    var comic: LocalComic? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReaderSettings.direction) private var globalDirection: ReaderDirection = .leftToRight
    @AppStorage(ReaderSettings.fit) private var globalFit: ReaderFit = .page
    @AppStorage(ReadingProfiles.autoMangaKey) private var autoManga = true
    @AppStorage(ReaderSettings.tapEdges) private var tapEdges = true
    @AppStorage(ReaderSettings.thumbnails) private var thumbnails = true
    @AppStorage(ReaderSettings.keepAwake) private var keepAwake = true
    @AppStorage(ReaderSettings.night) private var night = false
    @AppStorage(ReaderSettings.warmth) private var warmth = 0.5
    @AppStorage(ReaderSettings.dim) private var dim = 0.25
    @AppStorage(ReaderSettings.doublePage) private var doublePage = true
    @AppStorage(ReaderSettings.cropMargins) private var cropMargins = false
    @AppStorage(ReaderSettings.brightnessOn) private var brightnessOn = false
    @AppStorage(ReaderSettings.brightness) private var brightness = 0.6
    @AppStorage(ReaderSettings.clock) private var showClock = true

    private var profiles: ReadingProfiles { ReadingProfiles.shared }
    private var profile: ReadingProfiles.Profile? { comic.flatMap { profiles.profile(for: $0) } }
    private var hasSeries: Bool { comic.flatMap { ReadingProfiles.key(for: $0) } != nil }
    /// Es manga y se abre de derecha a izquierda solo (sin ajustes propios de la serie).
    private var autoMangaActive: Bool {
        guard let comic, profile == nil else { return false }
        return autoManga && globalDirection == .leftToRight && ReadingProfiles.isManga(comic)
    }

    private var direction: ReaderDirection {
        guard let comic else { return globalDirection }
        return profiles.direction(for: comic, global: globalDirection, autoManga: autoManga)
    }
    private var fit: ReaderFit { comic.map { profiles.fit(for: $0, global: globalFit) } ?? globalFit }

    /// Si la serie tiene ajustes propios (o es manga automático), el cambio queda para la serie;
    /// si no, cambia las opciones de siempre.
    private var directionBinding: Binding<ReaderDirection> {
        Binding(get: { direction }, set: { value in
            if let comic, profile != nil || autoMangaActive {
                saveProfile(comic, direction: value, fit: fit)
            } else {
                globalDirection = value
            }
        })
    }
    private var fitBinding: Binding<ReaderFit> {
        Binding(get: { fit }, set: { value in
            if let comic, profile != nil {
                saveProfile(comic, direction: direction, fit: value)
            } else {
                globalFit = value
            }
        })
    }
    private var rememberBinding: Binding<Bool> {
        Binding(get: { profile != nil }, set: { on in
            guard let comic else { return }
            if on { saveProfile(comic, direction: direction, fit: fit) } else { profiles.remove(for: comic) }
        })
    }

    private func saveProfile(_ comic: LocalComic, direction: ReaderDirection, fit: ReaderFit) {
        profiles.save(.init(name: ReadingProfiles.seriesName(for: comic), direction: direction, fit: fit), for: comic)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let comic, hasSeries {
                    Section {
                        Toggle(isOn: rememberBinding) {
                            Text("Recordar para «\(ReadingProfiles.seriesName(for: comic))»")
                        }
                    } header: {
                        Text("Esta serie")
                    } footer: {
                        Text(profile != nil
                             ? "La dirección y el tamaño de abajo quedan solo para esta serie. Apagalo para volver a las opciones de siempre."
                             : autoMangaActive
                                ? "Es manga: se abre de derecha a izquierda solo. Si cambiás la dirección, queda guardada para esta serie."
                                : "Prendelo para que esta serie recuerde su dirección y tamaño (por ejemplo, manga de derecha a izquierda).")
                    }
                }

                Section {
                    Picker("Dirección", selection: directionBinding) {
                        ForEach(ReaderDirection.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Manga de derecha a izquierda", isOn: $autoManga)
                } header: {
                    Text("Dirección de lectura")
                } footer: {
                    Text("Der → izq es para manga. Vertical muestra las páginas una debajo de la otra. Con \"Manga de derecha a izquierda\", los cómics de editoriales de manga (Viz, Kodansha…) se abren así solos.")
                }

                Section {
                    Picker("Ajuste", selection: fitBinding) {
                        ForEach(ReaderFit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(direction == .vertical)
                    Toggle("Recortar bordes blancos", isOn: $cropMargins)
                } header: {
                    Text("Tamaño de la página")
                } footer: {
                    Text(direction == .vertical
                         ? "En vertical las páginas siempre ocupan el ancho."
                         : "\"Al alto\" sirve para páginas dobles: se recorren deslizando de costado.")
                    + Text(" \"Recortar bordes blancos\" saca los márgenes blancos de las páginas escaneadas (como mucho un poco de cada lado).")
                }

                Section {
                    Toggle("Dos páginas con el teléfono de costado", isOn: $doublePage)
                } footer: {
                    Text("Girá el teléfono dentro del lector: se ven dos páginas juntas (la tapa va sola).")
                }

                Section("Al tocar") {
                    Toggle("Tocar los bordes pasa de página", isOn: $tapEdges)
                    Toggle("Mostrar miniaturas abajo", isOn: $thumbnails)
                }

                Section {
                    if brightnessOn {
                        Button("Volver al brillo del iPhone") { brightnessOn = false }
                    }
                    Toggle("Mostrar hora y batería", isOn: $showClock)
                    Toggle("Pantalla siempre encendida", isOn: $keepAwake)
                    Toggle("Modo nocturno", isOn: $night)
                    if night {
                        VStack(alignment: .leading) {
                            Text("Calidez").font(.subheadline)
                            Slider(value: $warmth, in: 0...1)
                        }
                        VStack(alignment: .leading) {
                            Text("Oscurecer").font(.subheadline)
                            Slider(value: $dim, in: 0...0.9)
                        }
                    }
                } header: {
                    Text("Pantalla")
                } footer: {
                    Text("El brillo se cambia deslizando el dedo hacia arriba o abajo en el rincón de abajo a la izquierda, y vuelve al del iPhone al cerrar el lector. La hora y la batería se ven abajo, en chiquito, mientras leés. El modo nocturno pone una luz más cálida y tenue sobre las páginas.")
                }
            }
            .tint(Theme.magenta)
            .navigationTitle("Opciones de lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Marcadores y números del TPB

/// Lista de marcadores (y, si es un TPB, sus números con la página donde empieza cada uno).
struct ReaderMarksSheet: View {
    let comicID: String
    let currentPage: Int
    let loader: PageLoader?
    let onJump: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let comic = library.item(comicID)
        NavigationStack {
            List {
                if let contents = comic?.contents, !contents.isEmpty {
                    Section {
                        ForEach(contents, id: \.cvID) { issue in
                            HStack(spacing: 10) {
                                Button {
                                    if let start = issue.startPage { onJump(start) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.title).font(.subheadline.weight(.bold))
                                        Text(issue.startPage.map { "Empieza en la página \($0 + 1)" } ?? "Sin marcar")
                                            .font(.caption)
                                            .foregroundStyle(issue.startPage == nil ? Color.secondary : Theme.magenta)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(issue.startPage == nil)
                                Button(issue.startPage == currentPage ? "Marcado acá" : "Empieza acá") {
                                    library.setStartPage(currentPage, issue: issue.cvID, in: comicID)
                                }
                                .font(.caption.weight(.bold))
                                .buttonStyle(.bordered)
                                .disabled(issue.startPage == currentPage)
                            }
                        }
                    } header: {
                        Text("Números de este TPB")
                    } footer: {
                        Text("Andá a la primera página de un número y tocá \"Empieza acá\". Después, tocando el número, saltás directo.")
                    }
                }

                Section {
                    let marks = comic?.bookmarks ?? []
                    if marks.isEmpty {
                        Text("Todavía no marcaste páginas. Tocá el marcador (arriba) en una página que te guste.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(marks, id: \.self) { mark in
                        Button {
                            onJump(mark)
                        } label: {
                            HStack(spacing: 12) {
                                if let loader {
                                    ThumbnailView(loader: loader, index: mark).frame(width: 36, height: 54)
                                }
                                Text("Página \(mark + 1)").font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for offset in offsets { library.toggleBookmark(marks[offset], for: comicID) }
                    }
                } header: {
                    Text("Marcadores")
                }
            }
            .navigationTitle(comic?.displayTitle ?? "Marcadores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Miniaturas

private struct ThumbnailStrip: View {
    let loader: PageLoader
    let current: Int
    let reversed: Bool
    var bookmarks: Set<Int> = []
    let onSelect: (Int) -> Void
    private var modern: Bool { AppearanceSettings.shared.modern }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(0..<loader.pageCount, id: \.self) { index in
                        Button { onSelect(index) } label: {
                            ThumbnailView(loader: loader, index: index)
                                .frame(width: 44, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: modern ? 7 : 3, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: modern ? 7 : 3, style: .continuous)
                                    .stroke(index == current ? Theme.magenta : .white.opacity(0.2),
                                            lineWidth: index == current ? 2 : 1))
                                .shadow(color: modern && index == current ? Theme.magenta.opacity(0.7) : .clear, radius: 6)
                                .scaleEffect(modern && index == current ? 1.08 : 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: current)
                                .opacity(index == current ? 1 : 0.75)
                                .overlay(alignment: .topTrailing) {
                                    if bookmarks.contains(index) {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.magenta)
                                            .padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 70)
            .environment(\.layoutDirection, reversed ? .rightToLeft : .leftToRight)
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, value in
                withAnimation { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }
}

struct ThumbnailView: View {
    let loader: PageLoader
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text("\(index + 1)").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .environment(\.layoutDirection, .leftToRight)
        .task(id: index) { image = await loader.thumbnail(index) }
    }
}

// MARK: - Página (deslizando)

/// Una página: la carga en segundo plano y deja hacer zoom.
private struct LocalPageView: View {
    let loader: PageLoader
    let index: Int
    let maxWidth: CGFloat
    let fit: ReaderFit
    var crop = false
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                ZoomableImage(image: image, fit: fit, onSingleTap: onTap)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(index)-\(Int(maxWidth))-\(crop)") {
            image = await loader.image(index, maxWidth: maxWidth)
            // Dejamos lista la siguiente página para que no haya espera al pasar.
            _ = await loader.image(index + 1, maxWidth: maxWidth)
        }
    }
}

/// Dos páginas juntas (teléfono de costado), con zoom.
private struct SpreadPageView: View {
    let loader: PageLoader
    let pages: [Int]
    let maxWidth: CGFloat
    let fit: ReaderFit
    var crop = false
    let onTap: (CGFloat) -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                ZoomableImage(image: image, fit: fit == .height ? .height : .page, onSingleTap: onTap)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: pages.map(String.init).joined(separator: "-") + "-\(crop)") {
            image = await loader.spread(pages, maxWidth: maxWidth)
        }
    }
}

/// Modo vertical continuo: todas las páginas una debajo de la otra, con zoom de verdad
/// (dos dedos o doble toque, agranda donde tocás). Las páginas se cargan a medida que aparecen.
private struct VerticalReader: UIViewRepresentable {
    let loader: PageLoader
    let decodeWidth: CGFloat
    @Binding var page: Int
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> VerticalScrollView {
        let c = context.coordinator
        let scroll = VerticalScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = c
        scroll.addSubview(c.container)
        for _ in 0..<loader.pageCount {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.backgroundColor = UIColor(white: 1, alpha: 0.04)
            c.container.addSubview(view)
            c.views.append(view)
            c.aspects.append(1.5)
        }
        c.footer.text = "Terminaste ✓\nQuedó guardado como leído."
        c.footer.numberOfLines = 0
        c.footer.textAlignment = .center
        c.footer.textColor = UIColor(white: 1, alpha: 0.8)
        c.footer.font = .preferredFont(forTextStyle: .headline)
        c.container.addSubview(c.footer)
        c.scroll = scroll
        scroll.onLayout = { [weak c] in c?.boundsChanged() }

        let doubleTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ scroll: VerticalScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Saltar de página desde las miniaturas o la barra (no cuando el cambio vino de deslizar).
        if c.lastSeen != page {
            c.lastSeen = page
            if page != c.reportedPage, c.width > 0 { c.scrollTo(page) }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: VerticalReader
        let container = UIView()
        let footer = UILabel()
        var views: [UIImageView] = []
        var aspects: [CGFloat] = []
        weak var scroll: VerticalScrollView?
        var width: CGFloat = 0
        var reportedPage = -1
        var lastSeen = -1
        private var loading = Set<Int>()
        private var placedFirstPage = false
        private let gap: CGFloat = 2
        private let footerHeight: CGFloat = 220

        init(parent: VerticalReader) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { visibleChanged() }

        /// Cambió el tamaño de la pantalla (por ejemplo, al girar): se vuelven a acomodar las páginas.
        func boundsChanged() {
            guard let scroll, scroll.bounds.width > 0, abs(scroll.bounds.width - width) > 0.5 else { return }
            let current = max(0, min(parent.page, views.count - 1))
            width = scroll.bounds.width
            scroll.zoomScale = 1
            layout()
            scrollTo(placedFirstPage ? current : parent.page)
            placedFirstPage = true
            visibleChanged()
        }

        /// Acomoda las páginas una debajo de la otra (tamaño sin zoom).
        private func layout() {
            guard let scroll else { return }
            var y: CGFloat = 0
            for (i, view) in views.enumerated() {
                let h = width * aspects[i]
                view.frame = CGRect(x: 0, y: y, width: width, height: h)
                y += h + gap
            }
            footer.frame = CGRect(x: 0, y: y, width: width, height: footerHeight)
            y += footerHeight
            let zoom = scroll.zoomScale
            container.bounds = CGRect(x: 0, y: 0, width: width, height: y)
            container.center = CGPoint(x: width * zoom / 2, y: y * zoom / 2)
            scroll.contentSize = CGSize(width: width * zoom, height: y * zoom)
        }

        func scrollTo(_ index: Int) {
            guard let scroll, !views.isEmpty else { return }
            let zoom = scroll.zoomScale
            let target = index >= views.count ? footer.frame.minY : views[max(0, index)].frame.minY
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(target * zoom, maxY)), animated: false)
            reportedPage = index
            visibleChanged()
        }

        /// Carga las páginas que se ven (y las de al lado), suelta las lejanas y avisa en qué página vas.
        private func visibleChanged() {
            guard let scroll, width > 0, !views.isEmpty else { return }
            let zoom = scroll.zoomScale
            let top = scroll.contentOffset.y / zoom
            let bottom = (scroll.contentOffset.y + scroll.bounds.height) / zoom
            let first = views.firstIndex { $0.frame.maxY >= top } ?? views.count - 1
            let last = views.lastIndex { $0.frame.minY <= bottom } ?? first
            for i in max(0, first - 1)...min(views.count - 1, max(first, last) + 2) { load(i) }
            for (i, view) in views.enumerated() where (i < first - 4 || i > last + 6) && view.image != nil {
                view.image = nil
            }
            // Página actual: la que está en el medio de la pantalla (o "terminado" si se ve el final).
            let middle = (top + bottom) / 2
            var current = views.firstIndex { $0.frame.minY <= middle && $0.frame.maxY + gap >= middle } ?? first
            if bottom >= footer.frame.minY + 60 { current = views.count }
            if current != reportedPage {
                reportedPage = current
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.page != current else { return }
                    self.parent.page = current
                }
            }
        }

        private func load(_ i: Int) {
            guard views[i].image == nil, !loading.contains(i) else { return }
            loading.insert(i)
            let loader = parent.loader, width = parent.decodeWidth
            Task { @MainActor [weak self] in
                let image = await loader.image(i, maxWidth: width)
                guard let self else { return }
                self.loading.remove(i)
                guard let image, image.size.width > 0 else { return }
                self.views[i].image = image
                let aspect = image.size.height / image.size.width
                if abs(aspect - self.aspects[i]) > 0.01, let scroll = self.scroll {
                    // Si la página que cambió de tamaño está arriba de lo que estás viendo, compensamos
                    // para que la pantalla no salte.
                    let zoom = scroll.zoomScale
                    let above = self.views[i].frame.maxY <= scroll.contentOffset.y / zoom
                    let delta = (aspect - self.aspects[i]) * self.width
                    self.aspects[i] = aspect
                    self.layout()
                    if above {
                        scroll.contentOffset.y += delta * zoom
                    }
                }
            }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: container)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }

        @objc func singleTapped() { parent.onTap() }
    }
}

/// Scroll que avisa cuando cambia de tamaño (al abrir o al girar el teléfono).
final class VerticalScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

// MARK: - Zoom

/// Imagen con zoom (dos dedos o doble toque), hecha con UIKit. Respeta el ajuste elegido.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let fit: ReaderFit
    let onSingleTap: (CGFloat) -> Void

    func makeUIView(context: Context) -> PageScrollView {
        let scroll = PageScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator
        scroll.imageView.image = image
        scroll.fit = fit

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped(_:)))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        // Deslizar hacia abajo (sin zoom y arriba de todo) cierra el lector.
        let pull = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pulled(_:)))
        pull.delegate = context.coordinator
        scroll.addGestureRecognizer(pull)
        return scroll
    }

    func updateUIView(_ scroll: PageScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if scroll.imageView.image !== image || scroll.fit != fit {
            scroll.setZoomScale(1, animated: false)
            scroll.imageView.image = image
            scroll.fit = fit
            scroll.relayoutImage()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onSingleTap: (CGFloat) -> Void

        init(onSingleTap: @escaping (CGFloat) -> Void) { self.onSingleTap = onSingleTap }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.delegate === self,
                  let scroll = pan.view as? UIScrollView else { return true }
            let speed = pan.velocity(in: scroll)
            return ReaderPull.enabled && scroll.zoomScale <= 1.01 && scroll.contentOffset.y <= 1
                && speed.y > 0 && speed.y > abs(speed.x) * 1.4
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func pulled(_ pan: UIPanGestureRecognizer) {
            let distance = max(0, pan.translation(in: pan.view).y)
            switch pan.state {
            case .changed:
                ReaderPull.handler?(distance, false, 0)
            case .ended, .cancelled, .failed:
                ReaderPull.handler?(distance, true, pan.velocity(in: pan.view).y)
            default:
                break
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? PageScrollView)?.imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { (scrollView as? PageScrollView)?.centerContent() }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? PageScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }

        @objc func singleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            // Con zoom, un toque solo muestra u oculta los controles (no pasa de página).
            if scroll.zoomScale > 1.01 {
                onSingleTap(scroll.bounds.width / 2)
            } else {
                // Posición del toque en la pantalla (no en la página, que puede ser más ancha).
                onSingleTap(gesture.location(in: scroll).x - scroll.contentOffset.x)
            }
        }
    }
}

/// Scroll con la imagen adentro: la acomoda según el ajuste (entera, al ancho o al alto) y la centra.
final class PageScrollView: UIScrollView {
    let imageView = UIImageView()
    var fit: ReaderFit = .page
    private var lastLayout: (CGSize, ReaderFit, ObjectIdentifier?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key = (bounds.size, fit, imageView.image.map(ObjectIdentifier.init))
        if lastLayout == nil || lastLayout!.0 != key.0 || lastLayout!.1 != key.1 || lastLayout!.2 != key.2 {
            relayoutImage()
        }
    }

    /// Tamaño de la imagen con zoom 1, según el ajuste.
    func relayoutImage() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        lastLayout = (bounds.size, fit, ObjectIdentifier(image))
        let w = bounds.width / image.size.width
        let h = bounds.height / image.size.height
        let scale: CGFloat
        switch fit {
        case .page: scale = min(w, h)
        case .width: scale = w
        case .height: scale = h
        }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        contentOffset = .zero
        centerContent()
    }

    /// Si la página es más chica que la pantalla, la centra.
    func centerContent() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }
}

// MARK: - Barra para saltar y hora

/// La página en grande mientras arrastrás la barra de abajo.
private struct ScrubPreview: View {
    let loader: PageLoader
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Color.white.opacity(0.08)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                .frame(width: 130)
            Text("Página \(index + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .environment(\.layoutDirection, .leftToRight)
        .task(id: index) {
            // Primero la miniatura (al instante) y después, si te quedás, una más nítida.
            image = await loader.thumbnail(index)
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            if let sharp = await loader.image(index, maxWidth: 420) { image = sharp }
        }
    }
}

/// Hora y batería en chiquito, abajo, mientras leés (el lector esconde las del iPhone).
private struct ReaderClock: View {
    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { context in
            let level = UIDevice.current.batteryLevel
            let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            HStack(spacing: 6) {
                Text(Self.format.string(from: context.date))
                if level >= 0 {
                    Image(systemName: batteryIcon(level, charging: charging))
                    Text("\(Int((level * 100).rounded())) %")
                }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
        }
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .accessibilityHidden(true)
    }

    private func batteryIcon(_ level: Float, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// La barrita de brillo que se ve mientras deslizás en el rincón de abajo a la izquierda.
private struct BrightnessIndicator: View {
    let value: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.ultraThinMaterial)
            Capsule()
                .fill(.white.opacity(0.92))
                .frame(height: max(36, 150 * CGFloat(value)))
            Image(systemName: value < 0.5 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .padding(.bottom, 10)
        }
        .frame(width: 36, height: 150)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .accessibilityHidden(true)
    }
}

/// Rincón invisible de abajo a la izquierda: deslizar hacia arriba o abajo cambia el brillo.
/// Un toque suelto ahí sigue pasando de página, y deslizar de costado sigue pasando de página.
private struct BrightnessCornerGesture: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    /// Tamaño del rincón (más o menos un pulgar).
    static let cornerWidth: CGFloat = 110
    static let cornerHeight: CGFloat = 200

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CornerView {
        let view = CornerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ view: CornerView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ view: CornerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Vista vacía que pone el gesto en la ventana mientras el lector está abierto.
    final class CornerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window, area: self) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BrightnessCornerGesture?
        private weak var area: UIView?
        private var pan: UIPanGestureRecognizer?

        func attach(to window: UIWindow, area: UIView) {
            self.area = area
            guard pan == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            window.addGestureRecognizer(pan)
            self.pan = pan
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
        }

        /// La pantalla del lector (para no reaccionar si hay una hoja abierta encima).
        private var readerRoot: UIView? {
            var responder: UIResponder? = area
            while let current = responder {
                if let controller = current as? UIViewController { return controller.view }
                responder = current.next
            }
            return nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let area, let window = area.window else { return false }
            // Hacia arriba o abajo, no de costado.
            let speed = pan.velocity(in: area)
            guard abs(speed.y) > abs(speed.x) * 1.3 else { return false }
            // Dónde apoyaste el dedo.
            let now = pan.location(in: area)
            let moved = pan.translation(in: area)
            let start = CGPoint(x: now.x - moved.x, y: now.y - moved.y)
            guard start.x >= 0, start.x < BrightnessCornerGesture.cornerWidth,
                  start.y > area.bounds.height - BrightnessCornerGesture.cornerHeight else { return false }
            // Que el dedo esté sobre el lector y no sobre una hoja (opciones, marcadores).
            let point = area.convert(start, to: window)
            guard let hit = window.hitTest(point, with: nil), let root = readerRoot else { return false }
            return hit.isDescendant(of: root)
        }

        /// Mientras se decide si es para el brillo, los otros deslizamientos (páginas, cerrar, desplazar) esperan.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }

        @objc func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                UISelectionFeedbackGenerator().selectionChanged()
                parent?.onBegan()
                parent?.onChanged(pan.translation(in: pan.view).y)
            case .changed:
                parent?.onChanged(pan.translation(in: pan.view).y)
            case .ended, .cancelled, .failed:
                parent?.onEnded()
            default:
                break
            }
        }
    }
}

// MARK: - Estilo moderno del lector

private extension View {
    /// Fondo de los botones de arriba: cápsula clara (clásico) o de vidrio (moderno).
    func readerButtonBackground() -> some View { modifier(ReaderButtonBackground()) }
}

private struct ReaderButtonBackground: ViewModifier {
    func body(content: Content) -> some View {
        if AppearanceSettings.shared.modern {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        } else {
            content.background(.white.opacity(0.16), in: Capsule())
        }
    }
}

/// Panel de abajo (miniaturas y barra): degradado oscuro (clásico) o tarjeta de vidrio flotante (moderno).
private struct ReaderBottomPanel: ViewModifier {
    let modern: Bool

    func body(content: Content) -> some View {
        if modern {
            content
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.28), Theme.magenta.opacity(0.35)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        } else {
            content
                .padding(.top, 24)
                .padding(.bottom, 16)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        }
    }
}

/// Botón "Siguiente número": con el estilo moderno, degradado de tu color con brillo.
private struct NextButtonBackground: ViewModifier {
    let modern: Bool

    func body(content: Content) -> some View {
        if modern {
            content
                .background(LinearGradient(colors: [Theme.magenta, Theme.magenta.opacity(0.7)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Theme.magenta.opacity(0.5), radius: 16, y: 6)
        } else {
            content.background(Theme.magenta, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
