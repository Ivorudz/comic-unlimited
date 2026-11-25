import SwiftUI
import WebKit
import Security

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

/// Mail y contraseña de Marvel Comics, guardados solo en este iPhone (la contraseña en el llavero).
/// Se completan solos en las páginas de inicio de sesión de Marvel Comics, WEBTOON o Disney, dentro de la app.
enum MarvelAccount {
    private static let emailKey = "marvel.email"
    private static let fallbackKey = "marvel.password.fallback"
    private static let service = "ComicUnlimited.marvel"

    static var email: String { UserDefaults.standard.string(forKey: emailKey) ?? "" }
    static var password: String { readKeychain() ?? UserDefaults.standard.string(forKey: fallbackKey) ?? "" }
    static var isSet: Bool { !email.isEmpty && !password.isEmpty }

    static func save(email: String, password: String) {
        UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: emailKey)
        // Si el llavero no anda (puede pasar dentro de LiveContainer), queda guardada en el iPhone igual.
        if writeKeychain(password) {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        } else {
            UserDefaults.standard.set(password, forKey: fallbackKey)
        }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "password"]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ password: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Lo que se busca en Marvel Comics: serie, número y año de tapa (para elegir el volumen correcto).
struct MarvelQuery: Equatable {
    var series: String
    var number: String
    var year: Int?
    var text: String { [series, number].filter { !$0.isEmpty }.joined(separator: " ") }
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
    /// Lo que se busca en Marvel Comics ("New Avengers" 9, 2005).
    let query: MarvelQuery
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
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .fullScreenCover(isPresented: $open) {
            MarvelWebScreen(cvID: cvID, query: query)
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
    let query: MarvelQuery
    @Environment(\.dismiss) private var dismiss
    @State private var model = MarvelWebModel()
    @State private var copiedNotice = false
    @State private var showSignOut = false
    @State private var foundDismissed = false
    private var links: MarvelLinks { MarvelLinks.shared }
    private var searchText: String { query.text }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            MarvelWebView(model: model, start: startURL,
                          autoQuery: links.id(forCV: cvID) == nil ? query : nil)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) { banner.padding(14) }
        .preferredColorScheme(.dark)
        .onAppear {
            AppOrientation.readerOpened(keepAwake: true)
            if links.id(forCV: cvID) == nil {
                // Todavía no sabemos su número: la app lo busca sola en Marvel Comics.
                // (Se copia el nombre también, por si hay que buscarlo a mano.)
                UIPasteboard.general.string = searchText
                model.query = query
                model.auto = .searching
            }
        }
        .onChange(of: model.foundID) { _, found in
            // Lo encontró: se guarda y se abre el lector.
            guard let found else { return }
            links.set(found, forCV: cvID)
            foundDismissed = false
            model.webView?.load(URLRequest(url: MarvelLinks.viewerURL(found)))
        }
        .onChange(of: model.auto) { _, state in
            if state == .notFound { copiedNotice = true }
        }
        .task(id: model.auto == .searching) {
            // Si la página no contesta en 25 segundos, se pasa a buscar a mano.
            guard model.auto == .searching else { return }
            try? await Task.sleep(for: .seconds(25))
            if model.auto == .searching { model.auto = .notFound }
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
        if model.auto == .searching {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Buscando \"\(searchText)\" en Marvel Comics…")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 4)
                Button("A mano") { model.auto = .notFound }
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if case .found(let title) = model.auto, !foundDismissed {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.magenta)
                Text("Encontré y guardé: \(title)")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("No es este") {
                    // Se olvida y se vuelve a buscar a mano.
                    links.set(nil, forCV: cvID)
                    model.foundID = nil
                    model.auto = .notFound
                    model.webView?.load(URLRequest(url: MarvelLinks.site.appendingPathComponent("explore")))
                }
                .font(.footnote.weight(.bold))
                Button { foundDismissed = true } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cerrar aviso")
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let current = model.currentID, !(model.inViewer && current == links.id(forCV: cvID)) {
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
                Text("No lo encontré solo. Copié \"\(searchText)\": pegalo en el buscador (la lupa de arriba) y abrí el cómic.")
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

    /// Búsqueda automática del cómic (la primera vez).
    enum AutoSearch: Equatable { case off, searching, found(String), notFound }
    var auto: AutoSearch = .off
    var query: MarvelQuery?
    /// Número que encontró la búsqueda automática.
    var foundID: Int?

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
    /// Si hay que buscar el cómic: se agrega la búsqueda a la página para que corra cuando termine de cargar.
    var autoQuery: MarvelQuery?

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
        // La página avisa lo que encontró la búsqueda automática.
        let proxy = MarvelScriptProxy()
        proxy.target = context.coordinator
        config.userContentController.add(proxy, name: "cuMarvel")
        if let autoQuery {
            config.userContentController.addUserScript(
                WKUserScript(source: MarvelScripts.search(autoQuery), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = Self.desktopAgent
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        context.coordinator.observe(web)
        context.coordinator.web = web
        model.webView = web
        web.load(URLRequest(url: start))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: MarvelWebModel
        private var watchers: [NSKeyValueObservation] = []
        /// Veces que se completó el inicio de sesión en cada dirección (como mucho 2, para no repetir sin fin).
        private var loginTries: [String: Int] = [:]
        weak var web: WKWebView?

        init(model: MarvelWebModel) { self.model = model }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageChanged(webView)
        }

        /// Cada página nueva: completar el inicio de sesión si hace falta y, en Explorar, buscar el cómic.
        func pageChanged(_ webView: WKWebView) {
            tryLogin(webView)
        }

        private func tryLogin(_ webView: WKWebView) {
            guard MarvelAccount.isSet, let url = webView.url, MarvelScripts.isLoginHost(url.host) else { return }
            let key = url.absoluteString
            guard loginTries[key, default: 0] < 2 else { return }
            loginTries[key, default: 0] += 1
            let script = MarvelScripts.login(email: MarvelAccount.email, password: MarvelAccount.password,
                                             clickSignIn: model.auto != .searching)
            webView.evaluateJavaScript(script) { _, _ in }
        }

        /// Lo que manda la página: "found" (con el número y el título) o "notFound".
        func received(_ body: Any) {
            guard let info = body as? [String: Any], let type = info["type"] as? String else { return }
            switch type {
            case "found":
                guard model.auto == .searching, let id = (info["id"] as? NSNumber)?.intValue else { return }
                model.auto = .found((info["title"] as? String) ?? "")
                model.foundID = id
            default:
                if model.auto == .searching { model.auto = .notFound }
            }
        }

        func observe(_ web: WKWebView) {
            watchers = [
                web.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
                    let url = change.newValue ?? nil
                    let id = MarvelLinks.marvelID(from: url)
                    let viewer = url?.pathComponents.contains("viewer") == true
                    Task { @MainActor in
                        self?.model.currentID = id
                        self?.model.inViewer = viewer
                        // La página cambia de dirección sin recargar (es una "app web"): se revisa un poco después.
                        try? await Task.sleep(for: .milliseconds(1200))
                        if let self, let web = self.web { self.pageChanged(web) }
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

/// Recibe los mensajes de la página sin quedar atado a ella (si no, la pantalla nunca se liberaría).
@MainActor
private final class MarvelScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: MarvelWebView.Coordinator?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.received(message.body)
    }
}

/// Lo que la app hace adentro de la página de Marvel Comics, como lo haría una persona con el dedo.
enum MarvelScripts {
    /// Páginas donde se completa el inicio de sesión (Marvel Comics, WEBTOON, Disney). En ninguna otra.
    static func isLoginHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["marvelcomicsapp.com", "webtoons.com", "webtoon.com", "disney.com", "go.com", "disneyplus.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func json(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// Completa mail y contraseña (o solo el mail, si la página los pide de a uno) y toca el botón de entrar.
    /// `clickSignIn`: si no hay campos, tocar el botón "Sign In" de la página (no mientras se busca un cómic).
    static func login(email: String, password: String, clickSignIn: Bool) -> String {
        loginScript.replacingOccurrences(of: "__CONFIG__",
                                         with: json(["email": email, "password": password, "clickSignIn": clickSignIn]))
    }

    /// Escribe la búsqueda en Explorar, va a la pestaña "Issues" y busca el resultado con la misma serie y número
    /// (si hay varios volúmenes, el del año más cercano antes de la tapa). Avisa "found" o "notFound".
    static func search(_ query: MarvelQuery) -> String {
        var config: [String: Any] = ["query": query.text, "series": query.series, "number": query.number]
        if let year = query.year { config["year"] = year }
        return searchScript.replacingOccurrences(of: "__CONFIG__", with: json(config))
    }

    private static let loginScript = #"""
    (function (cfg) {
      if (window.__cuLogin) { return 'running'; }
      window.__cuLogin = true;
      var clickedSignIn = false;
      var visible = function (el) { return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length); };
      var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      var fill = function (el, value) {
        el.focus(); setter.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };
      var attempt = function () {
        var inputs = Array.prototype.slice.call(document.querySelectorAll('input')).filter(visible);
        var pw = inputs.find(function (i) { return i.type === 'password'; });
        var mail = inputs.find(function (i) {
          var t = (i.type || '') + ' ' + (i.name || '') + ' ' + (i.id || '') + ' ' + (i.autocomplete || '') + ' ' + (i.placeholder || '');
          return i.type !== 'password' && i.type !== 'hidden' && /mail|user|login|account/i.test(t);
        });
        if (!pw && !mail) { return false; }
        // Sin contraseña, solo después de tocar "Sign In" o en una página de inicio de sesión
        // (nunca, por ejemplo, en un formulario de novedades).
        if (!pw && !clickedSignIn && !/login|log-in|signin|sign-in|auth|account|session/i.test(location.href)) { return false; }
        if (mail && mail.value !== cfg.email) { fill(mail, cfg.email); }
        if (pw && !pw.value) { fill(pw, cfg.password); }
        setTimeout(function () {
          var root = (pw || mail).closest('form') || document;
          var buttons = Array.prototype.slice.call(root.querySelectorAll('button, input[type=submit]')).filter(visible);
          var go = buttons.find(function (b) { return b.type === 'submit'; }) ||
                   buttons.find(function (b) { return /^(log ?in|sign ?in|continue|next|continuar|siguiente|iniciar sesi)/i.test((b.innerText || b.value || '').trim()); });
          if (go) { go.click(); }
        }, 500);
        return true;
      };
      if (attempt()) { return 'filled'; }
      if (cfg.clickSignIn) {
        var buttons = Array.prototype.slice.call(document.querySelectorAll('button, a')).filter(visible);
        var signIn = buttons.find(function (b) { return /^(sign ?in|log ?in)$/i.test((b.innerText || '').trim()); });
        if (signIn) { clickedSignIn = true; signIn.click(); }
      }
      // Los campos pueden aparecer un poco después (o en una ventanita): se reintenta unos segundos.
      var tries = 0;
      var timer = setInterval(function () {
        tries += 1;
        if (attempt() || tries > 16) { clearInterval(timer); window.__cuLogin = false; }
      }, 700);
      return 'waiting';
    })(__CONFIG__);
    """#

    private static let searchScript = #"""
    (function (cfg) {
      if (window.__cuSearch || location.pathname.indexOf('explore') < 0) { return; }
      window.__cuSearch = true;
      var post = function (m) { try { window.webkit.messageHandlers.cuMarvel.postMessage(m); } catch (e) {} };
      var norm = function (s) {
        return (s || '').toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9#]+/g, ' ').replace(/\s+/g, ' ').trim();
      };
      var seriesKey = function (s) {
        return norm(s).replace(/\b(19|20)\d\d\b/g, ' ').replace(/^the /, '').replace(/\s+/g, ' ').trim();
      };
      var target = seriesKey(cfg.series);
      var number = String(cfg.number || '').trim().replace(/^0+(?=\d)/, '').toLowerCase();
      var start = Date.now(), typedAt = 0, tabbed = false;
      var textOf = function (a) {
        var t = (a.innerText || '') + ' ' + (a.getAttribute('aria-label') || '') + ' ' + (a.title || '');
        a.querySelectorAll('img').forEach(function (i) { t += ' ' + (i.alt || ''); });
        return t.replace(/\s+/g, ' ').trim();
      };
      var typeQuery = function () {
        var inputs = Array.prototype.slice.call(document.querySelectorAll('input'));
        var box = inputs.find(function (i) { return /search/i.test(i.placeholder || '') || i.type === 'search'; });
        if (!box) { return false; }
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        box.focus(); setter.call(box, cfg.query);
        box.dispatchEvent(new Event('input', { bubbles: true }));
        box.dispatchEvent(new Event('change', { bubbles: true }));
        ['keydown', 'keypress', 'keyup'].forEach(function (type) {
          box.dispatchEvent(new KeyboardEvent(type, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
        });
        var form = box.closest('form');
        if (form && form.requestSubmit) { try { form.requestSubmit(); } catch (e) {} }
        return true;
      };
      var clickIssues = function () {
        var all = Array.prototype.slice.call(document.querySelectorAll('[role=tab], button'));
        var tab = all.find(function (e) { return (e.innerText || '').trim() === 'Issues'; });
        if (tab) { tab.click(); return true; }
        return false;
      };
      var scan = function () {
        var hits = [];
        Array.prototype.slice.call(document.querySelectorAll('a[href*="/issues/"]')).forEach(function (a) {
          var m = (a.getAttribute('href') || '').match(/\/issues\/(\d+)/);
          if (!m) { return; }
          var title = textOf(a), t = norm(title);
          var hash = t.indexOf('#');
          if (hash < 0) { return; }
          var num = t.slice(hash + 1).trim().split(' ')[0].replace(/^0+(?=\d)/, '');
          if (num !== number) { return; }
          if (seriesKey(t.slice(0, hash)) !== target) { return; }
          var y = title.match(/\((\d{4})/);
          hits.push({ id: parseInt(m[1], 10), title: title.slice(0, 120), year: y ? parseInt(y[1], 10) : null });
        });
        if (!hits.length) { return null; }
        if (cfg.year) {
          var ok = hits.filter(function (h) { return h.year === null || h.year <= cfg.year + 1; });
          if (ok.length) {
            ok.sort(function (a, b) { return (b.year || 0) - (a.year || 0); });
            return ok[0];
          }
        }
        return hits[0];
      };
      var timer = setInterval(function () {
        if (!typedAt) { if (typeQuery()) { typedAt = Date.now(); } }
        else if (!tabbed && Date.now() - typedAt > 1500) { tabbed = clickIssues() || Date.now() - typedAt > 5000; }
        if (typedAt && Date.now() - typedAt > 800) {
          var hit = scan();
          if (hit) { clearInterval(timer); post({ type: 'found', id: hit.id, title: hit.title }); return; }
        }
        if (Date.now() - start > 18000) { clearInterval(timer); post({ type: typedAt ? 'notFound' : 'noSearchBox' }); }
      }, 600);
    })(__CONFIG__);
    """#
}
