import SwiftUI
import UIKit

// Pestaña Inicio: barra para buscar cómics, "Seguir leyendo" y "Descubrir" (Recién salidos, Para vos, géneros y editoriales).
struct HomeView: View {
    @Environment(ReadingStore.self) private var store
    /// Se usa para abrir el lector desde cualquier pantalla.
    let onRead: (Comic) -> Void
    /// Abre un cómic de tu Biblioteca (archivo).
    let onReadLocal: (LocalComic) -> Void

    @State private var discover = DiscoverModel()
    @State private var forYou = ForYouModel()
    @State private var genres = GenreModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectTab) private var selectTab
    private var appearance: AppearanceSettings { AppearanceSettings.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    searchBar
                    // Las partes de Inicio en el orden elegido en Personalizar (las apagadas no se ven).
                    let sections = appearance.visibleHomeSections
                    let firstDiscover = sections.first { $0 != .continueReading }
                    ForEach(sections) { section in
                        if section == firstDiscover { HomeSectionTitle("Descubrir") }
                        homeSection(section)
                    }
                    Text("Datos y portadas: Comic Vine y Metron. Las portadas pertenecen a sus editoriales.")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            // Deslizar hacia abajo: actualiza Recién salidos (y Para vos si cambiaron tus listas).
            .refreshable {
                await discover.retry()
                await forYou.loadIfNeeded()
            }
            .appDestinations()
            .navigationDestination(for: HomeRoute.self) { route in
                HomeGridScreen(route: route, discover: discover, forYou: forYou, genres: genres)
            }
            .navigationDestination(for: Comic.self) { comic in
                DetailView(comic: comic, onRead: onRead)
            }
            .navigationTitle("Inicio")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                BrowsingContext.current = nil
                if appearance.isVisible(.genres) { genres.start() }
            }
            // Recién salidos alimenta también De tus series, Series nuevas y Editoriales.
            .task { await discover.load() }
            // Al volver a la app después de un rato, se actualiza lo guardado.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await discover.refreshIfStale()
                    await forYou.loadIfNeeded()
                }
            }
        }
    }

    // MARK: Partes de la pantalla

    private var header: some View {
        Text("Cómic Unlimited")
            .font(.system(.title, weight: .black).width(Theme.titleWidth))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .misprint()
            .padding(.top, 10)
    }

    /// Barra para buscar cómics (abre el buscador de Comic Vine).
    /// Forma de cápsula con borde de tinta y una sombra magenta corrida, como un globo de historieta.
    private var searchBar: some View {
        NavigationLink(value: CVRoute.search) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.paper)
                    .frame(width: 36, height: 36)
                    .background(Theme.magenta, in: Circle())
                Text("Buscar cómics")
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
            .background(Capsule().fill(Theme.magenta).offset(x: 4, y: 4))
            .contentShape(Capsule())
        }
        .buttonStyle(SearchBarPressStyle())
        .padding(.top, 20)
        .padding(.trailing, 4)
        .accessibilityLabel("Buscar cómics: series, números, autores o personajes")
    }

    /// Una sola fila con lo último que leíste (cómics de la app y tus archivos), lo más reciente primero.
    @ViewBuilder
    private var continueReading: some View {
        // Solo tus archivos de la Biblioteca (los cómics de prueba ya no se muestran en Inicio).
        let recent = LocalLibrary.shared.recentlyRead.map { RecentItem.local($0) }
        HomeSectionTitle("Seguir leyendo")
        if recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Todavía no empezaste ningún cómic. Importá uno en la Biblioteca y abrilo: va a aparecer acá.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                Button { selectTab(.library) } label: {
                    Label("Ir a la Biblioteca", systemImage: "books.vertical")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recent) { item in
                        switch item {
                        case .sample(let comic, _):
                            if store.isFinished(comic) {
                                NavigationLink(value: comic) {
                                    ContinueCard(comic: comic, page: store.savedPage(for: comic), finished: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button { onRead(comic) } label: {
                                    ContinueCard(comic: comic, page: store.savedPage(for: comic), finished: false)
                                }
                                .buttonStyle(.plain)
                            }
                        case .local(let comic):
                            Button { onReadLocal(comic) } label: {
                                LocalContinueCard(comic: comic)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { onReadLocal(comic) } label: {
                                    Label(comic.isFinished ? "Volver a leer" : "Seguir leyendo", systemImage: "book")
                                }
                                if let issueID = comic.cvIssueID {
                                    NavigationLink(value: CVRoute.issue(id: issueID, title: comic.displayTitle)) {
                                        Label("Ver el cómic", systemImage: "info.circle")
                                    }
                                } else {
                                    NavigationLink(value: LibraryRoute.localComic(comic.id)) {
                                        Label("Ver el cómic", systemImage: "info.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    LocalLibrary.shared.hideFromContinue(comic.id)
                                } label: {
                                    Label("Quitar de Seguir leyendo", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
        }
    }

    /// Una parte de Inicio.
    @ViewBuilder
    private func homeSection(_ section: AppearanceSettings.HomeSection) -> some View {
        switch section {
        case .continueReading:
            continueReading
        case .recent:
            HomeRowHeader(title: "Recién salidos", route: discover.all.isEmpty ? nil : .issues("recientes"))
            RecentReleasesRow(model: discover)
                .padding(.bottom, 22)
        case .forYou:
            HomeRowHeader(title: "Para vos", route: forYouHasItems ? .forYou : nil)
            ForYouRow(model: forYou)
                .padding(.bottom, 22)
        case .mySeries:
            if let category = discover.topCategories.first(where: { $0.id == "mias" }) {
                CategoryRow(category: category)
            }
        case .newSeries:
            if let category = discover.topCategories.first(where: { $0.id == "nuevas" }) {
                CategoryRow(category: category)
            }
        case .genres:
            GenreRows(model: genres)
        case .publishers:
            ForEach(discover.publisherCategories) { CategoryRow(category: $0) }
        }
    }
}

extension HomeView {
    fileprivate var forYouHasItems: Bool {
        if case .loaded(let items) = forYou.state { return !items.isEmpty }
        return false
    }
}

/// Algo que empezaste a leer: un cómic de la app o un archivo tuyo.
private enum RecentItem: Identifiable {
    case sample(Comic, Double)
    case local(LocalComic)

    var id: String {
        switch self {
        case .sample(let c, _): return "app-\(c.id)"
        case .local(let c): return "file-\(c.id)"
        }
    }

    var time: Double {
        switch self {
        case .sample(_, let t): return t
        case .local(let c): return c.lastOpened ?? 0
        }
    }
}

/// Tarjeta de "Seguir leyendo" para un archivo de tu Biblioteca.
private struct LocalContinueCard: View {
    let comic: LocalComic
    @State private var cover: UIImage?

    var body: some View {
        let progress = comic.isFinished ? 1 : Double((comic.lastPage ?? 0) + 1) / Double(max(comic.pageCount, 1))
        HStack(spacing: 12) {
            ZStack {
                Theme.chip
                if let cover { Image(uiImage: cover).resizable().scaledToFill() }
            }
            .frame(width: 62, height: 93)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(comic.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                // De qué arco, serie, lista o ruta venías (si venías de alguno).
                if let context = comic.lastContext {
                    Text(context.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.magenta)
                        .lineLimit(1)
                }
                Text(pagesLeft)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                ProgressBar(value: progress).padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 290)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .task(id: comic.id) {
            cover = UIImage(contentsOfFile: LocalLibrary.shared.coverURL(comic).path)
        }
    }

    /// El avance, como lo elegiste en Personalizar: páginas que quedan, página actual o porcentaje.
    private var pagesLeft: String {
        if comic.isFinished { return "Terminado" }
        let current = (comic.lastPage ?? 0) + 1
        let total = max(comic.pageCount, 1)
        switch AppearanceSettings.shared.progressText {
        case .left:
            let left = max(total - current, 0)
            switch left {
            case 0: return "Última página"
            case 1: return "Queda 1 página"
            default: return "Quedan \(left) páginas"
            }
        case .page:
            return "Página \(min(current, total)) de \(total)"
        case .percent:
            return "\(min(100, current * 100 / total)) % leído"
        }
    }
}

// MARK: - Piezas reutilizables

/// Al apretar la barra de búsqueda, se achica un poquito (como un botón de verdad).
private struct SearchBarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.heavy))
            .foregroundStyle(Theme.ink)
            .padding(.top, 28)
            .padding(.bottom, 12)
    }
}

struct SourceBadge: View {
    let source: Comic.Source

    var body: some View {
        Text(source.label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(source == .editorial ? Color(hex: 0x00A3D9) : Color(hex: 0xD1006C),
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

struct CatalogCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CoverArt(comic: comic)
                .overlay(alignment: .topLeading) {
                    SourceBadge(source: comic.source).padding(6)
                }
            Text(comic.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            Text(comic.author)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
            (Text("★ ").foregroundStyle(Theme.star) + Text(String(format: "%.1f", comic.rating)))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
        }
    }
}

struct ContinueCard: View {
    let comic: Comic
    let page: Int
    var finished = false

    var body: some View {
        let progress = finished ? 1 : Double(page + 1) / Double(comic.pageCount)
        HStack(spacing: 12) {
            CoverArt(comic: comic).frame(width: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(comic.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(finished ? "Terminado" : "Página \(page + 1) de \(comic.pageCount)")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                ProgressBar(value: progress).padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 290)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chip)
                Capsule().fill(Theme.magenta).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
