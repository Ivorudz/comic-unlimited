import SwiftUI
import WebKit

// "Leer en Marvel Comics": abre la página oficial de Marvel Comics (marvelcomicsapp.com) dentro de la app,
// pidiendo la versión de computadora (como "Solicitar sitio de escritorio" de Safari), porque en el celular
// la página no deja leer. Entrás con tu propia cuenta y la sesión queda guardada en el iPhone.
// La app no lee ni guarda nada de la página: solo recuerda el número de cada cómic en Marvel Comics
// (el de la dirección .../viewer/1477) cuando vos confirmás "Guardar", así la próxima vez abre directo.

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
        Group {
            if isMarvel {
                Button { open = true } label: {
                    Label(links.id(forCV: cvID) == nil ? "Buscar en Marvel Comics" : "Leer en Marvel Comics",
                          systemImage: "safari")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .detailButtonBackground(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .fullScreenCover(isPresented: $open) {
                    MarvelWebScreen(cvID: cvID, searchText: searchText)
                }
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
                    Button {
                        UIApplication.shared.open(MarvelLinks.site.appendingPathComponent("issues/\(id)"))
                    } label: { Label("Abrir en Safari", systemImage: "safari") }
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
        if let current = model.currentID, current != links.id(forCV: cvID) {
            // Abriste un cómic en Marvel Comics: ¿es este? Así la próxima vez va directo.
            HStack(spacing: 10) {
                Text("¿Es \(searchText)?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
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
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if copiedNotice {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                Text("Copié \"\(searchText)\": pegalo en el buscador de Marvel Comics y abrí el cómic.")
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

/// El navegador (WKWebView) en modo computadora.
private struct MarvelWebView: UIViewRepresentable {
    let model: MarvelWebModel
    let start: URL

    /// Safari de Mac: así la página muestra su lector (en el celular solo ofrece bajar la app).
    private static let desktopAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // la sesión queda guardada
        config.defaultWebpagePreferences.preferredContentMode = .desktop
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
                    let id = MarvelLinks.marvelID(from: change.newValue ?? nil)
                    Task { @MainActor in self?.model.currentID = id }
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
