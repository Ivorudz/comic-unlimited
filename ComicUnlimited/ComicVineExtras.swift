import SwiftUI
import UIKit
import Translation

// Piezas de las fichas de Comic Vine:
// - Personajes con su imagen (en círculo) y arcos con su imagen.
// - Textos de Comic Vine traducidos automáticamente con el traductor de Apple (viene en el iPhone, iOS 18+).
// Las imágenes se cargan al momento y no se guardan. Pertenecen a sus editoriales.

// MARK: - Personajes

/// Fila deslizable de personajes: imagen redonda y nombre. Al tocar uno se abre su página en Comic Vine.
struct CharacterStrip: View {
    let refs: [CVRef]
    @Environment(\.openURL) private var openURL
    @State private var info: [Int: CVImageItem] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(refs, id: \.id) { ref in
                    Button {
                        if let link = info[ref.id]?.siteDetailUrl.flatMap({ URL(string: $0) }) { openURL(link) }
                    } label: {
                        VStack(spacing: 6) {
                            RemoteCircle(url: info[ref.id]?.image?.small, name: ref.name ?? "?")
                                .frame(width: 72, height: 72)
                            Text(ref.name ?? "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 84)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
        .task {
            guard info.isEmpty, !ComicVineKey.current.isEmpty else { return }
            let items = (try? await ComicVineKey.client.characters(ids: refs.map(\.id))) ?? []
            info = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
}

/// Imagen redonda cargada de internet. Mientras carga muestra la inicial del nombre.
struct RemoteCircle: View {
    let url: URL?
    let name: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.chip
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        .task(id: url) {
            guard let url else { return }
            image = await CoverLoader.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Arcos

/// Fila deslizable de arcos ("Forma parte de"): imagen y nombre. Al tocar uno se abre el arco.
struct ArcStrip: View {
    let refs: [CVRef]
    @State private var info: [Int: CVImageItem] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(refs, id: \.id) { ref in
                    NavigationLink(value: CVRoute.arc(id: ref.id, name: ref.name ?? "Arco")) {
                        VStack(alignment: .leading, spacing: 4) {
                            RemoteCover(url: info[ref.id]?.image?.small)
                            Text(ref.name ?? "Arco")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(width: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
        .task {
            guard info.isEmpty, !ComicVineKey.current.isEmpty else { return }
            let items = (try? await ComicVineKey.client.storyArcs(ids: refs.map(\.id))) ?? []
            info = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
}

// MARK: - Traducción

enum TranslationSettings {
    static let enabledKey = "settings.translate"
    static let languageKey = "settings.language"

    /// Idiomas que se pueden elegir (código y nombre).
    static let languages: [(code: String, name: String)] = [
        ("es", "Español"),
        ("pt", "Portugués"),
        ("it", "Italiano"),
        ("fr", "Francés"),
        ("de", "Alemán"),
        ("en", "Inglés (sin traducir)"),
    ]
}

/// Traducciones ya hechas, solo en memoria mientras la app está abierta.
@MainActor
enum TranslationMemory {
    static var cache: [String: String] = [:]
}

/// "De qué se trata" de Comic Vine: el resumen corto arriba y, abajo, solo la parte de la historia
/// (sin las listas de personajes, arcos relacionados, ediciones, etc.).
struct ComicVineSummary: View {
    let deck: String?
    let description: String?

    static func hasContent(deck: String?, description: String?) -> Bool {
        CVText.plain(deck) != nil || CVText.story(description) != nil
    }

    var body: some View {
        let lead = CVText.plain(deck)
        var story = CVText.story(description)
        // Si la historia repite el resumen, no lo mostramos dos veces.
        if let l = lead, let s = story, s.hasPrefix(l) { story = String(s.dropFirst(l.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if story?.isEmpty == true { story = nil }
        return VStack(alignment: .leading, spacing: 12) {
            if let lead {
                ComicVineText(text: lead, isLead: true, showsFooter: story == nil)
            }
            if let story {
                ComicVineText(text: story)
            }
        }
    }
}

/// Texto largo de Comic Vine, con "Leer más" y traducción automática según Perfil → Configuración.
struct ComicVineText: View {
    let text: String
    /// Resumen corto: se muestra un poco más destacado y entero.
    var isLead = false
    /// Mostrar abajo "Traducido automáticamente · Ver original".
    var showsFooter = true
    @AppStorage(TranslationSettings.enabledKey) private var enabled = true
    @AppStorage(TranslationSettings.languageKey) private var language = "es"
    @State private var translated: String?
    @State private var failed = false
    @State private var showOriginal = false
    @State private var expanded = false

    private var wantsTranslation: Bool { enabled && language != "en" }
    private var cacheKey: String { "\(language)|\(text)" }

    var body: some View {
        let shown = (wantsTranslation && !showOriginal ? translated : nil) ?? text
        VStack(alignment: .leading, spacing: 6) {
            Text(shown)
                .font(isLead ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .lineLimit(expanded || isLead ? nil : 6)
            if !isLead && shown.count > 300 {
                Button(expanded ? "Leer menos" : "Leer más") {
                    withAnimation { expanded.toggle() }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.magenta)
            }
            if showsFooter { footer }
        }
        .modifier(AutoTranslate(text: text, language: language,
                                active: wantsTranslation && translated == nil && !failed) { result in
            if let result {
                translated = result
                TranslationMemory.cache[cacheKey] = result
            } else {
                failed = true
            }
        })
        .onAppear { translated = TranslationMemory.cache[cacheKey] }
        .onChange(of: language) { _, _ in
            translated = TranslationMemory.cache[cacheKey]
            failed = false
        }
    }

    @ViewBuilder
    private var footer: some View {
        if wantsTranslation {
            if translated != nil {
                HStack(spacing: 4) {
                    Text("Traducido automáticamente ·")
                    Button(showOriginal ? "Ver traducción" : "Ver original") { showOriginal.toggle() }
                        .foregroundStyle(Theme.magenta)
                }
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            } else if failed {
                Text("No se pudo traducir; se muestra el original de Comic Vine (en inglés).")
                    .font(.caption).foregroundStyle(Theme.ink2)
            } else {
                Text("Traduciendo…").font(.caption).foregroundStyle(Theme.ink2)
            }
        } else {
            Text("El texto viene de Comic Vine (en inglés). Podés traducirlo en Perfil → Configuración.")
                .font(.caption).foregroundStyle(Theme.ink2)
        }
    }
}

/// Usa el traductor de Apple (iOS 18 o más nuevo). En versiones anteriores no hace nada.
private struct AutoTranslate: ViewModifier {
    let text: String
    let language: String
    let active: Bool
    let done: (String?) -> Void

    func body(content: Content) -> some View {
        if active {
            if #available(iOS 18.0, *) {
                content.translationTask(source: Locale.Language(identifier: "en"),
                                        target: Locale.Language(identifier: language)) { session in
                    do {
                        let response = try await session.translate(text)
                        done(response.targetText)
                    } catch {
                        done(nil)
                    }
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}
