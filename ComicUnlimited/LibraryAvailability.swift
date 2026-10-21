import SwiftUI

// "En biblioteca" / "Descargar" en la ficha de cada cómic real.
// - Si ya tenés ese número (un archivo unido a esa ficha de Comic Vine): "Leer" y "Ver en la Biblioteca".
// - Si no: "Descargar", que lo busca en tus fuentes (catálogos JSON y tu página WordPress).

/// Pantallas a las que se puede ir desde cualquier pestaña (fichas de Comic Vine y carpetas de la Biblioteca).
struct AppDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: CVRoute.self) { route in
                CVDestination(route: route)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .series(let id): SeriesFolderView(seriesID: id)
                case .status(let state): StatusFolderView(state: state)
                case .arc(let id, let name): ArcFolderView(arcID: id, name: name)
                case .publisher(let name): PublisherFolderView(name: name)
                case .sources: SourcesView()
                case .source(let url): SourceDetailView(url: url)
                case .findInSources(let series, let number):
                    FindInSourcesView(series: series, number: number)
                case .reviewLinks: ReviewLinksView()
                case .localComic(let id): LocalComicDetailView(comicID: id)
                case .metronIssue(let id): MetronIssueView(metronID: id)
                }
            }
    }
}

extension View {
    func appDestinations() -> some View { modifier(AppDestinations()) }
}

// MARK: - Botón en la ficha

struct LibraryAvailability: View {
    let detail: CVIssueDetail
    @Environment(LibraryActions.self) private var actions: LibraryActions?
    @State private var choosingFile = false
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let mine = library.items.first { $0.cvIssueID == detail.id }
        // TPB tuyos que traen este número.
        let inTPB = library.collections(containing: detail.id)
        Group {
            if let mine {
                HStack(spacing: 10) {
                    Button {
                        actions?.onRead(mine)
                    } label: {
                        Label(mine.isFinished ? "Volver a leer" : mine.hasStarted ? "Seguir leyendo" : "Leer", systemImage: "book.fill")
                            .font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(Theme.paper)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: LibraryRoute.series(mine.cvSeriesID)) {
                        Label("Ver en la Biblioteca", systemImage: "books.vertical")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(Theme.ink)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Label("En biblioteca", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.magenta)
                    .padding(.top, 6)
                if !inTPB.isEmpty {
                    Text("También lo tenés en: \(inTPB.map(\.displayTitle).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 2)
                }
                TPBContentsButton(comic: mine)
                    .padding(.top, 10)
            } else if let tpb = inTPB.first {
                // Si marcaste en qué página del TPB empieza este número, se abre ahí.
                let start = tpb.contents?.first { $0.cvID == detail.id }?.startPage
                HStack(spacing: 10) {
                    Button {
                        if let start { library.setPage(start, for: tpb.id) }
                        actions?.onRead(tpb)
                    } label: {
                        Label(start == nil ? "Leer el TPB" : "Leer este número", systemImage: "book.fill")
                            .font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(Theme.paper)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    TPBLink(tpb: tpb) {
                        Label("Ver el TPB", systemImage: "books.vertical")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(Theme.ink)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Label("En biblioteca, dentro de: \(tpb.displayTitle)", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.magenta)
                    .padding(.top, 6)
            } else {
                NavigationLink(value: LibraryRoute.findInSources(series: detail.volume?.name ?? "",
                                                                 number: detail.issueNumber)) {
                    Label("Descargar", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(13)
                        .foregroundStyle(.white)
                        .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Text("Lo busca en tus fuentes (catálogos y tu página WordPress).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)
                if detail.volume != nil && !library.items.isEmpty {
                    Button {
                        choosingFile = true
                    } label: {
                        Label("¿Ya lo tenés? Elegí el archivo", systemImage: "link")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.magenta)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
            }
        }
        .padding(.top, 14)
        .sheet(isPresented: $choosingFile) {
            PickLocalFileView(detail: detail)
        }
    }
}

// MARK: - Buscar en tus fuentes

struct SourceMatch: Identifiable {
    let source: SavedSource
    let comic: SourceComic
    var id: String { source.url + "|" + comic.download }
}

struct FindInSourcesView: View {
    let series: String
    let number: String?

    @AppStorage(WordPressSettings.siteKey) private var site = ""
    @State private var query: String
    @State private var catalogMatches: [SourceMatch] = []
    @State private var posts: [WPPost] = []
    @State private var searching = false
    @State private var wpError: String?
    @State private var searched = false

    private var store: SourceStore { SourceStore.shared }

    init(series: String, number: String?) {
        self.series = series
        self.number = number
        let n = number.map { " \($0)" } ?? ""
        _query = State(initialValue: series + n)
    }

    private var hasSources: Bool { !store.sources.isEmpty || WordPressClient.normalized(site) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Buscar en tus fuentes")
                    .font(.system(size: 24, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                    TextField("Serie y número", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 14)

                if !hasSources {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Todavía no tenés fuentes configuradas.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        NavigationLink(value: LibraryRoute.sources) {
                            Text("Ir a Fuentes").font(.subheadline.weight(.bold)).foregroundStyle(Theme.magenta)
                        }
                    }
                    .padding(.top, 16)
                } else if searching {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    if !store.sources.isEmpty {
                        SectionTitle("En tus catálogos")
                        if catalogMatches.isEmpty {
                            Text(searched ? "No está en tus catálogos." : "").font(.subheadline).foregroundStyle(Theme.ink2)
                        }
                        ForEach(catalogMatches) { match in
                            VStack(alignment: .leading, spacing: 2) {
                                SourceComicRow(comic: match.comic)
                                NavigationLink(value: LibraryRoute.source(match.source.url)) {
                                    Text("Ver en \"\(match.source.manifest.name)\"")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.magenta)
                                }
                            }
                        }
                    }
                    if WordPressClient.normalized(site) != nil {
                        SectionTitle("En tu página")
                        if let wpError {
                            Text(wpError).font(.subheadline).foregroundStyle(Theme.ink2)
                        } else if posts.isEmpty {
                            Text(searched ? "No está en tu página." : "").font(.subheadline).foregroundStyle(Theme.ink2)
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
                                    Text("Ir a descargar").font(.caption.weight(.bold)).foregroundStyle(Theme.magenta)
                                }
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Si no aparece, probá buscar con otras palabras (por ejemplo, solo el nombre de la serie).")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Descargar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if !searched { await search() } }
    }

    private func search() async {
        guard hasSources else { return }
        searching = true
        wpError = nil
        catalogMatches = Self.matches(query: query, series: series, number: number, in: store.sources)
        if let url = WordPressClient.normalized(site) {
            do {
                posts = try await WordPressClient.posts(site: url, page: 1, search: query).posts
            } catch {
                posts = []
                wpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        searched = true
        searching = false
    }

    // MARK: Coincidencias en catálogos JSON

    private static func clean(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "#", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func cleanNumber(_ n: String?) -> String? {
        guard let n = n?.trimmingCharacters(in: CharacterSet(charactersIn: " #")), !n.isEmpty else { return nil }
        let trimmed = String(n.drop { $0 == "0" })
        return trimmed.isEmpty || trimmed.hasPrefix(".") ? "0" + trimmed : trimmed
    }

    static func matches(query: String, series: String, number: String?,
                        in sources: [SavedSource]) -> [SourceMatch] {
        let wantedSeries = clean(series)
        let wantedNumber = cleanNumber(number)
        let words = clean(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        var result: [SourceMatch] = []
        for source in sources {
            for comic in source.manifest.comics {
                // 1) Misma serie y mismo número.
                if let s = comic.series, clean(s) == wantedSeries,
                   cleanNumber(comic.number) == wantedNumber {
                    result.append(SourceMatch(source: source, comic: comic))
                    continue
                }
                // 2) Todas las palabras buscadas aparecen en el título o la serie.
                let haystack = clean("\(comic.title) \(comic.series ?? "") \(comic.number ?? "")")
                if !words.isEmpty, words.allSatisfy({ haystack.contains($0) }) {
                    result.append(SourceMatch(source: source, comic: comic))
                }
            }
        }
        return result
    }
}
