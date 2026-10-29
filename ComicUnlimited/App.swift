import SwiftUI

// Punto de partida de la app.
@main
struct ComicUnlimitedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ReadingStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

/// Lo que necesita el lector para abrirse: qué cómic y en qué página.
struct ReaderSession: Identifiable {
    let comic: Comic
    let startPage: Int
    var id: String { comic.id }
}

/// Lo que necesita el lector de archivos para abrirse.
struct LocalSession: Identifiable {
    let comic: LocalComic
    let startPage: Int
    var id: String { comic.id }
}

// Las cinco pestañas de abajo: Inicio, Biblioteca, Rutas (guía de lectura), Comunidad (con Próximos) y Perfil.
struct RootView: View {
    @Environment(ReadingStore.self) private var store
    @State private var session: ReaderSession?
    /// Archivo de la Biblioteca abierto en el lector (y en qué página arranca).
    @State private var localSession: LocalSession?
    /// Menú de los cómics de tu Biblioteca (compartido por todas las pestañas).
    @State private var libraryActions = LibraryActions(onRead: { _ in })

    var body: some View {
        TabView {
            HomeView(onRead: openReader, onReadLocal: openLocal)
                .tabItem { Label("Inicio", systemImage: "house") }
            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
            NavigationStack {
                StartGuideView(asTab: true)
                    .appDestinations()
                    .onAppear { BrowsingContext.current = nil }
            }
            .tabItem { Label("Rutas", systemImage: "map") }
            CommunityView()
                .tabItem { Label("Comunidad", systemImage: "bubble.left") }
            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
        .tint(Theme.magenta)
        .modifier(LibraryActionsHost(actions: libraryActions))
        .onAppear { libraryActions.onRead = openLocal }
        .fullScreenCover(item: $session) { session in
            ReaderView(comic: session.comic, startPage: session.startPage)
                .environment(store)
        }
        .background {
            // Un segundo lector, para tus archivos. Va en otra vista para no chocar con el primero.
            Color.clear.fullScreenCover(item: $localSession) { session in
                LocalReaderView(comic: session.comic, startPage: session.startPage) { next in
                    // "Siguiente número": se abre el otro, en el mismo arco o serie.
                    let previous = LocalLibrary.shared.item(session.comic.id)
                    let context = previous?.lastContext
                    // El que terminaste sale de "Seguir leyendo" (queda el que empezás ahora).
                    if previous?.isFinished == true { LocalLibrary.shared.hideFromContinue(session.comic.id) }
                    localSession = LocalSession(comic: next, startPage: LocalLibrary.shared.open(next, context: context))
                }
                // Cada cómic es un lector nuevo (si no, quedaban las páginas y la posición del anterior).
                .id(session.id)
            }
        }
    }

    private func openLocal(_ comic: LocalComic) {
        localSession = LocalSession(comic: comic, startPage: LocalLibrary.shared.open(comic))
    }

    private func openReader(_ comic: Comic) {
        session = ReaderSession(comic: comic, startPage: store.open(comic))
    }
}

/// Pantalla provisoria para las pestañas que todavía no están hechas.
struct ComingSoonView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 32, weight: .black).width(.expanded))
                .foregroundStyle(Theme.ink)
                .misprint(0.7)
                .padding(.top, 20)
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.magenta)
                Text("Próximamente")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
