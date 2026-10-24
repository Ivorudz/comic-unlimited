import SwiftUI
import UIKit

// "Mi página WordPress": la app lee las publicaciones de TU página (la configurás una vez)
// usando la interfaz pública de WordPress (/wp-json/wp/v2/posts) y descarga los archivos que encuentra.
// Descarga links directos (.cbz, .cbr, .zip, .pdf), Pixeldrain (link oficial de descarga),
// Google Drive y Dropbox. Los demás links se abren en Safari.

enum WordPressSettings {
    static let siteKey = "wordpress.site"
    static var site: String { UserDefaults.standard.string(forKey: siteKey) ?? "" }
}

// MARK: - Datos

struct WPPost: Decodable, Identifiable, Hashable {
    let id: Int
    let date: String?
    let link: String?
    let title: Rendered?
    let excerpt: Rendered?
    let content: Rendered?
    let embedded: Embedded?

    struct Rendered: Decodable, Hashable { let rendered: String? }
    struct Embedded: Decodable, Hashable {
        let featuredMedia: [Media]?
        enum CodingKeys: String, CodingKey { case featuredMedia = "wp:featuredmedia" }
    }
    struct Media: Decodable, Hashable { let sourceUrl: String? }

    enum CodingKeys: String, CodingKey {
        case id, date, link, title, excerpt, content
        case embedded = "_embedded"
    }

    var titleText: String { CVText.plain(title?.rendered) ?? "Sin título" }
    var coverURL: URL? { embedded?.featuredMedia?.first?.sourceUrl.flatMap { URL(string: $0) } }
    var year: String? { date.map { String($0.prefix(4)) } }

    var dateText: String? {
        guard let date, date.count >= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(date.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "es_AR")
        out.dateFormat = "d 'de' MMMM 'de' yyyy"
        return out.string(from: d)
    }
}

/// Un link encontrado en una publicación.
struct WPLink: Identifiable, Hashable {
    enum Kind { case downloadable, external }
    let original: String
    /// Link para descargar (solo si se puede descargar desde la app).
    let download: String?
    let label: String
    var id: String { original }
    var kind: Kind { download == nil ? .external : .downloadable }
}

enum WordPressClient {
    /// Dirección base de la página: "misitio.com" → "https://misitio.com".
    static func normalized(_ site: String) -> URL? {
        var s = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// Publicaciones de la página (de a 20). Devuelve también cuántas páginas hay.
    static func posts(site: URL, page: Int, search: String) async throws -> (posts: [WPPost], totalPages: Int) {
        var components = URLComponents(url: site.appendingPathComponent("wp-json/wp/v2/posts"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "_embed", value: "1"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(URLQueryItem(name: "search", value: q)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("ComicUnlimited/0.20 (app personal)", forHTTPHeaderField: "User-Agent")
        let fetched: (Data, URLResponse)
        do {
            fetched = try await URLSession(configuration: .ephemeral).data(for: request)
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
        let (data, response) = fetched
        let http = response as? HTTPURLResponse
        // WordPress responde 400 cuando se pide una página que no existe (después de la última).
        if http?.statusCode == 400 { return ([], page - 1) }
        if let code = http?.statusCode, !(200..<300).contains(code) {
            throw SourceError.server(code)
        }
        let total = Int(http?.value(forHTTPHeaderField: "X-WP-TotalPages") ?? "") ?? page
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let posts = try? decoder.decode([WPPost].self, from: data) else {
            throw SourceError.badFormat("no parece una página WordPress (no se encontró /wp-json/wp/v2/posts)")
        }
        return (posts, total)
    }

    /// Busca los links de una publicación y arma el link de descarga cuando se puede.
    static func links(in html: String?) -> [WPLink] {
        guard let html, let regex = try? NSRegularExpression(pattern: "href=[\"']([^\"']+)[\"']", options: [.caseInsensitive])
        else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        var result: [WPLink] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard raw.lowercased().hasPrefix("https://"), seen.insert(raw).inserted,
                  let url = URL(string: raw), let host = url.host?.lowercased() else { continue }
            result.append(classify(raw, url: url, host: host))
        }
        // Primero los que se pueden descargar.
        return result.filter { $0.kind == .downloadable } + result.filter { $0.kind == .external }
    }

    private static func classify(_ raw: String, url: URL, host: String) -> WPLink {
        let ext = url.pathExtension.lowercased()
        let file = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if ComicFile.fileExtensions.contains(ext) || ["rar", "7z", "tar"].contains(ext) {
            return WPLink(original: raw, download: raw, label: file)
        }
        let parts = url.pathComponents
        // Pixeldrain: https://pixeldrain.com/u/ID → link oficial de descarga
        if host.hasSuffix("pixeldrain.com"), let i = parts.firstIndex(of: "u"), i + 1 < parts.count {
            return WPLink(original: raw, download: "https://pixeldrain.com/api/file/\(parts[i + 1])?download",
                          label: "Pixeldrain")
        }
        // Google Drive: /file/d/ID/... o ?id=ID
        if host == "drive.google.com" {
            var id: String?
            if let i = parts.firstIndex(of: "d"), i + 1 < parts.count { id = parts[i + 1] }
            if id == nil {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "id" })?.value
            }
            if let id {
                return WPLink(original: raw, download: "https://drive.google.com/uc?export=download&id=\(id)",
                              label: "Google Drive")
            }
        }
        // Dropbox: dl=0 → dl=1
        if host.hasSuffix("dropbox.com") {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = (c?.queryItems ?? []).filter { $0.name != "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            c?.queryItems = items
            if let link = c?.url?.absoluteString {
                return WPLink(original: raw, download: link, label: "Dropbox")
            }
        }
        return WPLink(original: raw, download: nil, label: host)
    }
}

// MARK: - Publicaciones de tu página

struct WordPressView: View {
    @AppStorage(WordPressSettings.siteKey) private var site = ""
    @State private var posts: [WPPost] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var loading = false
    @State private var errorText: String?
    @State private var query = ""
    @State private var activeQuery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(WordPressClient.normalized(site)?.host ?? "Mi página")
                    .font(.system(size: 26, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                    TextField("Buscar en tu página", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await reload() } }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 14)

                if let errorText {
                    Text(errorText).font(.subheadline).foregroundStyle(Theme.magenta).padding(.top, 14)
                }

                ForEach(posts) { post in
                    NavigationLink {
                        WordPressPostView(post: post)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteCover(url: post.coverURL).frame(width: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(post.titleText)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let date = post.dateText {
                                    Text(date).font(.caption).foregroundStyle(Theme.ink2)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if page < totalPages && !posts.isEmpty {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("Ver más publicaciones")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                } else if posts.isEmpty && errorText == nil {
                    Text("No hay publicaciones.").font(.subheadline).foregroundStyle(Theme.ink2).padding(.top, 16)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Mi página")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if posts.isEmpty { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        posts = []
        page = 0
        totalPages = 1
        activeQuery = query
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, let url = WordPressClient.normalized(site) else {
            if WordPressClient.normalized(site) == nil { errorText = "Configurá la dirección de tu página en Fuentes." }
            return
        }
        loading = true
        errorText = nil
        do {
            let result = try await WordPressClient.posts(site: url, page: page + 1, search: activeQuery)
            let known = Set(posts.map(\.id))
            posts += result.posts.filter { !known.contains($0.id) }
            page += 1
            totalPages = max(result.totalPages, 0)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Una publicación

struct WordPressPostView: View {
    let post: WPPost
    @State private var expanded = false
    private var store: SourceStore { SourceStore.shared }
    @Environment(\.openURL) private var openURL

    var body: some View {
        let links = WordPressClient.links(in: post.content?.rendered)
        let text = CVText.plain(post.content?.rendered)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    if post.coverURL != nil {
                        RemoteCover(url: post.coverURL).frame(width: 120)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.titleText)
                            .font(.system(size: 22, weight: .black).width(.expanded))
                            .foregroundStyle(Theme.ink)
                        if let date = post.dateText {
                            Text(date).font(.subheadline).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .padding(.top, 8)

                let downloadable = links.filter { $0.kind == .downloadable }
                let external = links.filter { $0.kind == .external }

                SectionTitle("Descargar")
                if downloadable.isEmpty {
                    Text("Esta publicación no tiene archivos que la app pueda descargar.")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
                ForEach(downloadable) { link in
                    downloadRow(link)
                }

                if !external.isEmpty {
                    SectionTitle("Otros links")
                    ForEach(external) { link in
                        Button {
                            if let url = URL(string: link.original) { openURL(url) }
                        } label: {
                            HStack {
                                Image(systemName: "safari").foregroundStyle(Theme.ink2)
                                Text(link.label).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Text("Abrir en Safari").font(.caption).foregroundStyle(Theme.magenta)
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let text {
                    SectionTitle("Publicación")
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(expanded ? nil : 8)
                    if text.count > 400 {
                        Button(expanded ? "Leer menos" : "Leer más") { withAnimation { expanded.toggle() } }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.magenta)
                            .padding(.top, 6)
                    }
                }

                if let link = post.link.flatMap({ URL(string: $0) }) {
                    Link("Ver la publicación en tu página", destination: link)
                        .font(.footnote)
                        .foregroundStyle(Theme.magenta)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(post.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func downloadRow(_ link: WPLink) -> some View {
        let comic = SourceComic(title: post.titleText, download: link.download ?? link.original,
                                year: post.year, cover: post.coverURL?.absoluteString)
        let key = comic.download
        return HStack(spacing: 12) {
            Image(systemName: "doc.zipper").font(.title3).foregroundStyle(Theme.magenta)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if let failure = store.failures[key] {
                    Text(failure).font(.caption2).foregroundStyle(Theme.magenta).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if let value = store.progress[key] {
                Text("\(Int(value * 100))%").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            } else if store.downloaded.contains(key) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.magenta)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Ya está en tu Biblioteca")
            } else {
                Button {
                    Task { await store.download(comic) }
                } label: {
                    Image(systemName: store.failures[key] == nil ? "arrow.down.circle" : "arrow.clockwise.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.magenta)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descargar a la Biblioteca")
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Configurar la página

/// Tarjeta en Fuentes para escribir la dirección de tu página y entrar a ella.
struct WordPressSiteCard: View {
    @AppStorage(WordPressSettings.siteKey) private var site = ""
    @State private var draft = ""
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mi página WordPress").font(.headline).foregroundStyle(Theme.ink)
            if let url = WordPressClient.normalized(site), !editing {
                NavigationLink {
                    WordPressView()
                } label: {
                    HStack {
                        Image(systemName: "globe").foregroundStyle(Theme.magenta)
                        Text(url.host ?? site).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Ver publicaciones").font(.caption.weight(.bold)).foregroundStyle(Theme.magenta)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.ink2)
                    }
                }
                .buttonStyle(.plain)
                Button("Cambiar dirección") {
                    draft = site
                    editing = true
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
            } else {
                Text("Escribí la dirección de tu página (por ejemplo, misitio.com). La app va a leer sus publicaciones y descargar tus archivos.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                TextField("misitio.com", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(10)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                HStack {
                    Button("Guardar") {
                        site = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        editing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .disabled(WordPressClient.normalized(draft) == nil)
                    if editing {
                        Button("Cancelar") { editing = false }.buttonStyle(.bordered)
                    }
                    if !site.isEmpty && editing {
                        Button("Quitar", role: .destructive) {
                            site = ""
                            editing = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}
