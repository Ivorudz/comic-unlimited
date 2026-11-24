import SwiftUI
import WebKit

// "Leer en Marvel Comics": abre el lector web oficial de Marvel Comics (marvelcomicsapp.com) dentro de nuestra app,
// con la cuenta y la suscripción del dueño. La página solo deja leer en computadora, así que el navegador de adentro
// se presenta como una computadora (Safari de Mac, sin pantalla táctil). Lo pidió el dueño, con autorización para
// uso personal y no comercial (0.47). También se puede abrir la app oficial directo en el cómic
// (marvelcomicsapp://viewer?issueId=1477). La app no lee ni guarda nada de la página: solo el número de cada cómic
// cuando el dueño toca "Guardar".

/// Números de cada cómic en Marvel Comics, guardados en el iPhone (`marvel-comics.json`).
@MainActor
@Observable
final class MarvelLinks {
    static let shared = MarvelLinks()
    nonisolated static let site = URL(string: "https://www.marvelcomicsapp.com")!

    /// Código de Comic Vine del número → número en Marvel Comics.
    private(set) var ids: [Int: Int]

    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("marvel-comics.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            ids = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in Int(key).map { ($0, value) } })
        } else {
            ids = [:]
        }
    }

    func id(forCV cvID: Int) -> Int? { ids[cvID] }

    func set(_ marvelID: Int?, forCV cvID: Int) {
        ids[cvID] = marvelID
        let saved = Dictionary(uniqueKeysWithValues: ids.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: Self.file, options: .atomic) }
    }

    nonisolated static func viewerURL(_ id: Int) -> URL { site.appendingPathComponent("viewer/\(id)") }
    nonisolated static func issueURL(_ id: Int) -> URL { site.appendingPathComponent("issues/\(id)") }
    /// Link de la app oficial que abre directo el lector de ese cómic.
    nonisolated static func appURL(_ id: Int) -> URL { URL(string: "marvelcomicsapp://viewer?issueId=\(id)")! }

    /// Abre el cómic en la app oficial de Marvel Comics; si no está instalada, su página en Safari.
    static func openInApp(_ id: Int) {
        UIApplication.shared.open(appURL(id)) { opened in
            if !opened { UIApplication.shared.open(issueURL(id)) }
        }
    }

    /// El número de Marvel Comics de una dirección como .../viewer/1477 o .../issues/1477.
    nonisolated static func marvelID(from url: URL?) -> Int? {
        guard let url, let host = url.host?.lowercased(), host.hasSuffix("marvelcomicsapp.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, ["viewer", "issues"].contains(parts[0]) else { return nil }
        return Int(parts[1])
    }
}

/// ¿La serie es de Marvel? Se mira tu Biblioteca y, si no, se le pregunta a Comic Vine (una vez por serie; queda guardado).
enum MarvelPublisher {
    private static let key = "marvel.publisherByVolume"

    static func isMarvel(_ name: String?) -> Bool { name?.lowercased().contains("marvel") == true }

    @MainActor
    static func isMarvel(volumeID: Int) async -> Bool {
        if let mine = LocalLibrary.shared.items.first(where: { $0.cvSeriesID == volumeID && $0.cvPublisher?.isEmpty == false }) {
            return isMarvel(mine.cvPublisher)
        }
        var saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        if let name = saved[String(volumeID)] { return isMarvel(name) }
        guard !ComicVineKey.current.isEmpty else { return false }
        let found = await ComicVineKey.client.publishers(volumeIDs: [volumeID])
        guard let name = found[volumeID] else { return false }
        saved[String(volumeID)] = name
        UserDefaults.standard.set(saved, forKey: key)
        return isMarvel(name)
    }
}

// MARK: - Botón en la ficha

/// "Leer en Marvel Comics" (solo en cómics de Marvel).
struct MarvelReadButton: View {
    let cvID: Int
    let volumeID: Int?
    /// Lo que se copia para buscar en Marvel Comics ("New Avengers 9").
    let searchText: String
    @State private var isMarvel = false
    @State private var open = false
    private var links: MarvelLinks { MarvelLinks.shared }

    var body: some View {
        // Siempre hay una vista (aunque sea vacía), así la consulta de la editorial de abajo arranca.
        VStack(spacing: 0) {
            if isMarvel {
                let saved = links.id(forCV: cvID)
                Button {
                    // Con el número guardado abre el lector; si no, el buscador de Marvel Comics.
                    open = true
                } label: {
                    Label(saved == nil ? "Buscar en Marvel Comics" : "Leer en Marvel Comics",
                          systemImage: saved == nil ? "magnifyingglass" : "book.pages")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .detailButtonBackground(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .contextMenu {
                    if let saved {
                        Button { MarvelLinks.openInApp(saved) } label: {
                            Label("Abrir en la app de Marvel Comics", systemImage: "arrow.up.forward.app")
                        }
                        Button(role: .destructive) { links.set(nil, forCV: cvID) } label: {
                            Label("Olvidar el link de este cómic", systemImage: "link")
                        }
                    }
                }
                if saved != nil {
                    Text("Se lee acá, con tu cuenta de Marvel Comics. Mantené apretado para abrirlo en la app de Marvel.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .fullScreenCover(isPresented: $open) {
                    MarvelWebScreen(cvID: cvID, searchText: searchText)
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: volumeID) {
            guard let volumeID else { return }
            isMarvel = await MarvelPublisher.isMarvel(volumeID: volumeID)
        }
    }
}

// MARK: - Página de Marvel Comics adentro de la app

struct MarvelWebScreen: View {
    let cvID: Int
    let searchText: String
    @Environment(\.dismiss) private var dismiss
    @State private var model = MarvelWebModel()
    @State private var copiedNotice = false
    @State private var showSignOut = false
    private var links: MarvelLinks { MarvelLinks.shared }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            MarvelWebView(model: model, start: startURL)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) { banner.padding(14) }
        .preferredColorScheme(.dark)
        .onAppear {
            AppOrientation.readerOpened(keepAwake: true)
            if links.id(forCV: cvID) == nil {
                // Todavía no sabemos su número: se copia el nombre para pegarlo en el buscador de Marvel.
                UIPasteboard.general.string = searchText
                copiedNotice = true
            }
        }
        .onDisappear { AppOrientation.readerClosed() }
        .confirmationDialog("¿Cerrar la sesión de Marvel Comics en esta app?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                Task {
                    await MarvelWebModel.signOut()
                    model.reload()
                }
            }
        }
    }

    private var startURL: URL {
        if let id = links.id(forCV: cvID) { return MarvelLinks.viewerURL(id) }
        return MarvelLinks.site.appendingPathComponent("explore")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 36)
            }
            .accessibilityLabel("Cerrar")
            Button { model.goBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36)
            }
            .disabled(!model.canGoBack)
            .accessibilityLabel("Atrás")
            Text("Marvel Comics")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
            if model.loading { ProgressView().tint(.white) }
            Menu {
                Button { model.reload() } label: { Label("Recargar", systemImage: "arrow.clockwise") }
                if let id = model.currentID {
                    Button { MarvelLinks.openInApp(id) } label: {
                        Label("Abrir en la app de Marvel", systemImage: "arrow.up.forward.app")
                    }
                    Button { UIApplication.shared.open(MarvelLinks.issueURL(id)) } label: {
                        Label("Abrir en Safari", systemImage: "safari")
                    }
                }
                if links.id(forCV: cvID) != nil {
                    Button(role: .destructive) { links.set(nil, forCV: cvID) } label: {
                        Label("Olvidar el link de este cómic", systemImage: "link.badge.plus")
                    }
                }
                Button(role: .destructive) { showSignOut = true } label: {
                    Label("Cerrar sesión de Marvel", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 36)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black)
    }

    @ViewBuilder
    private var banner: some View {
        if let current = model.currentID, !(model.inViewer && current == links.id(forCV: cvID)) {
            let isSaved = current == links.id(forCV: cvID)
            // Abriste un cómic en Marvel Comics: ¿es este? Al guardarlo, el botón de la ficha abre directo la app.
            HStack(spacing: 10) {
                Text(isSaved ? "Guardado ✓ \(searchText)" : "¿Es \(searchText)?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if isSaved {
                    Button("Leer en la app") { MarvelLinks.openInApp(current) }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.magenta, in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Button("Guardar") {
                        links.set(current, forCV: cvID)
                        copiedNotice = false
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.magenta, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if copiedNotice {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                Text("Copié \"\(searchText)\": pegalo en el buscador (la lupa de arriba) y abrí el cómic.")
                    .font(.footnote)
                Spacer(minLength: 4)
                Button { copiedNotice = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cerrar aviso")
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Estado de la página: si está cargando, si se puede volver y en qué cómic estás.
@MainActor
@Observable
final class MarvelWebModel {
    var loading = false
    var canGoBack = false
    /// Número de Marvel Comics del cómic abierto (nil si no estás en un cómic).
    var currentID: Int?
    /// Estás en el lector (…/viewer/N), no en la página del cómic.
    var inViewer = false
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func reload() { webView?.reload() }

    /// Borra la sesión y lo guardado de Marvel Comics (solo de esa página).
    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let marvel = records.filter { $0.displayName.lowercased().contains("marvelcomicsapp") }
        await store.removeData(ofTypes: types, for: marvel)
    }
}

/// El navegador (WKWebView), presentado como una computadora para que la página deje leer.
private struct MarvelWebView: UIViewRepresentable {
    let model: MarvelWebModel
    let start: URL

    /// Safari de Mac.
    private static let desktopAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Antes de que cargue la página: una Mac sin pantalla táctil (la página mira esto para mandar a su app).
    private static let desktopScript = """
    (function () {
      try {
        Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: function () { return 0; }, configurable: true });
        Object.defineProperty(Navigator.prototype, 'platform', { get: function () { return 'MacIntel'; }, configurable: true });
      } catch (e) {}
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // la sesión queda guardada
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.userContentController.addUserScript(
            WKUserScript(source: Self.desktopScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = Self.desktopAgent
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        context.coordinator.observe(web)
        model.webView = web
        web.load(URLRequest(url: start))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: MarvelWebModel
        private var watchers: [NSKeyValueObservation] = []

        init(model: MarvelWebModel) { self.model = model }

        func observe(_ web: WKWebView) {
            watchers = [
                web.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
                    let url = change.newValue ?? nil
                    let id = MarvelLinks.marvelID(from: url)
                    let viewer = url?.pathComponents.contains("viewer") == true
                    Task { @MainActor in
                        self?.model.currentID = id
                        self?.model.inViewer = viewer
                    }
                },
                web.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, change in
                    let loading = change.newValue ?? false
                    Task { @MainActor in self?.model.loading = loading }
                },
                web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, change in
                    let back = change.newValue ?? false
                    Task { @MainActor in self?.model.canGoBack = back }
                },
            ]
        }

        /// Lo que no es la página web (la App Store, "Abrir en la app") se abre afuera.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }
            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            let external = !["http", "https", "about", "blob", "data"].contains(scheme)
                || host == "apps.apple.com" || host == "itunes.apple.com" || host == "goto.marvelcomicsapp.com"
            if external {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        /// Los links que abren otra pestaña se abren en la misma.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, let url = action.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
