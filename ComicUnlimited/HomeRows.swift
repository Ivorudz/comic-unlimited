import SwiftUI

// Piezas de las filas de Inicio: título de fila con "Ver todo", la pantalla "Ver todo" (grilla)
// y el cambio de pestaña desde cualquier pantalla (por ejemplo "Ir a la Biblioteca").

// MARK: - Pestañas

enum AppTab: Hashable {
    case home, library, routes, community, profile
}

private struct SelectTabKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Cambia de pestaña (la pone RootView).
    var selectTab: (AppTab) -> Void {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }
}

// MARK: - "Ver todo"

/// Qué fila de Inicio se abre en "Ver todo".
enum HomeRoute: Hashable {
    /// "recientes" = Recién salidos; si no, el id de una categoría (De tus series, Series nuevas, editoriales).
    case issues(String)
    case genre(String)
    case forYou
}

/// Título de una fila de Inicio, con "Ver todo" a la derecha.
struct HomeRowHeader: View {
    let title: String
    var route: HomeRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            if let route {
                NavigationLink(value: route) {
                    Text("Ver todo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.magenta)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }
}

/// Título grande de Inicio ("Seguir leyendo", "Descubrir"): más grande que el de cada fila.
struct HomeSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(Theme.ink)
            .padding(.top, 30)
            .padding(.bottom, 14)
    }
}

/// Un cómic o una serie para la grilla de "Ver todo".
struct HomeCard: Identifiable {
    enum Target: Hashable {
        case issue(Int, String)
        case metron(Int)
        case series(Int, String)
    }
    let id: String
    let title: String
    let detail: String?
    let cover: URL?
    let target: Target

    static func issue(_ issue: UpcomingIssue) -> HomeCard {
        HomeCard(id: "i\(issue.id)-\(issue.metronID ?? 0)", title: issue.title,
                 detail: issue.publisher.map(ComicPublishers.displayName),
                 cover: issue.coverURL,
                 target: issue.metronID.map { .metron($0) } ?? .issue(issue.id, issue.title))
    }
}

/// Pantalla "Ver todo": todos los cómics o series de una fila, en grilla.
struct HomeGridScreen: View {
    let route: HomeRoute
    let discover: DiscoverModel
    let forYou: ForYouModel
    let genres: GenreModel

    var body: some View {
        let content = resolve()
        ScrollView {
            if content.cards.isEmpty {
                Text("No hay nada para mostrar en esta fila por ahora.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: Theme.coverColumns),
                          alignment: .leading, spacing: 18) {
                    ForEach(content.cards) { card in
                        link(card)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .background(Theme.paper)
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func resolve() -> (title: String, cards: [HomeCard]) {
        switch route {
        case .issues(let id):
            if id == "recientes" {
                return ("Recién salidos", DiscoverModel.sorted(discover.all).map(HomeCard.issue))
            }
            let category = (discover.topCategories + discover.publisherCategories).first { $0.id == id }
            return (category?.title ?? "Cómics", (category?.full ?? []).map(HomeCard.issue))
        case .genre(let id):
            let row = genres.rows.first { $0.id == id }
            let cards = (row?.all ?? []).map {
                HomeCard(id: "s\($0.id)", title: $0.name, detail: $0.detail, cover: $0.cover,
                         target: .series($0.id, $0.name))
            }
            return (row?.title ?? "Género", cards)
        case .forYou:
            guard case .loaded(let items) = forYou.state else { return ("Para vos", []) }
            return ("Para vos", items.map {
                HomeCard(id: "s\($0.id)", title: $0.name, detail: nil, cover: $0.coverURL,
                         target: .series($0.id, $0.name))
            })
        }
    }

    @ViewBuilder
    private func link(_ card: HomeCard) -> some View {
        switch card.target {
        case .issue(let id, let title):
            NavigationLink(value: CVRoute.issue(id: id, title: title)) { HomeGridCard(card: card) }
                .buttonStyle(.plain)
        case .metron(let id):
            NavigationLink(value: LibraryRoute.metronIssue(id)) { HomeGridCard(card: card) }
                .buttonStyle(.plain)
        case .series(let id, let name):
            NavigationLink(value: CVRoute.series(id: id, name: name)) { HomeGridCard(card: card) }
                .buttonStyle(.plain)
        }
    }
}

private struct HomeGridCard: View {
    let card: HomeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: card.cover)
            Text(card.title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            if let detail = card.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
        }
    }
}
