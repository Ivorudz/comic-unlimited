import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Pestaña Biblioteca: los cómics que tenés en archivos (.cbz, .zip, .cbr o PDF).
// Arriba se elige cómo verlos: Todos, por Series o por Estado de lectura (carpetas).
// Tocar un cómic lo abre en el lector. Mantenerlo apretado muestra más opciones.

struct LibraryView: View {
    /// Formas de ver la Biblioteca (los botones de arriba).
    enum Mode: String, CaseIterable, Identifiable {
        case all = "Todos"
        case series = "Series"
        case status = "Estado"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recientes"
        case az = "A–Z"
        case newest = "Más nuevos"
        case oldest = "Más viejos"
        var id: String { rawValue }

        /// Texto más largo para el menú.
        var menuLabel: String {
            switch self {
            case .recent: return "Leídos o agregados recientemente"
            case .az: return "A–Z"
            case .newest: return "Más nuevos (fecha de publicación)"
            case .oldest: return "Más viejos (fecha de publicación)"
            }
        }
    }

    private var library: LocalLibrary { LocalLibrary.shared }
    @State private var actions: LibraryActions
    @AppStorage("library.mode") private var mode: Mode = .all
    @AppStorage("library.sort") private var sort: Sort = .recent
    @State private var query = ""
    @State private var showImporter = false
    @State private var problems: [String] = []
    @State private var showProblems = false
    @State private var renameText = ""

    init(onRead: @escaping (LocalComic) -> Void) {
        _actions = State(initialValue: LibraryActions(onRead: onRead))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if library.items.isEmpty && !library.importing {
                        Text("Todavía no importaste cómics. Tocá el botón de arriba y elegí un archivo desde la app Archivos (por ejemplo, de iCloud Drive o Descargas).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 18)
                    } else {
                        modePicker
                        switch mode {
                        case .all: allView
                        case .series: seriesView
                        case .status: statusView
                        }
                        Text("Tocá un cómic para leerlo. Mantenelo apretado para ver su ficha, cambiarle el nombre, elegir otra ficha de Comic Vine o borrarlo.")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: CVRoute.self) { route in
                CVDestination(route: route)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .series(let id): SeriesFolderView(seriesID: id)
                case .status(let state): StatusFolderView(state: state)
                }
            }
            .navigationTitle("Biblioteca")
            .toolbar(.hidden, for: .navigationBar)
        }
        .environment(actions)
        .task { await library.completeSeriesInfo() }
        .sheet(item: $actions.linking) { comic in
            LinkPickerView(comic: comic)
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                showImporter = false
                guard !urls.isEmpty else { return }
                Task {
                    problems = await library.importFiles(urls)
                    showProblems = !problems.isEmpty
                }
            }
            .ignoresSafeArea()
        }
        .alert("Algunos archivos no se pudieron importar", isPresented: $showProblems) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problems.joined(separator: "\n\n"))
        }
        .alert("Cambiar nombre",
               isPresented: Binding(get: { actions.renaming != nil }, set: { if !$0 { actions.renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                if let comic = actions.renaming { library.rename(comic.id, to: renameText) }
                actions.renaming = nil
            }
            if actions.renaming?.customTitle != nil {
                Button("Volver al nombre original") {
                    if let comic = actions.renaming { library.rename(comic.id, to: nil) }
                    actions.renaming = nil
                }
            }
            Button("Cancelar", role: .cancel) { actions.renaming = nil }
        } message: {
            Text("Es solo el nombre que se ve en la app. El archivo no cambia.")
        }
        .onChange(of: actions.renaming) { _, comic in
            renameText = comic?.displayTitle ?? ""
        }
        .confirmationDialog("¿Borrar este cómic de la Biblioteca?",
                            isPresented: Binding(get: { actions.toDelete != nil },
                                                 set: { if !$0 { actions.toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let comic = actions.toDelete { library.delete(comic) }
                actions.toDelete = nil
            }
            Button("Cancelar", role: .cancel) { actions.toDelete = nil }
        } message: {
            Text("Se borra la copia guardada en la app. El archivo original sigue en la app Archivos.")
        }
    }

    // MARK: Arriba

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Biblioteca")
                .font(.system(size: 32, weight: .black).width(.expanded))
                .foregroundStyle(Theme.ink)
                .misprint(0.7)
                .padding(.top, 20)

            Text("Tus cómics en archivo. Se guardan solo en este iPhone.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)

            Button {
                showImporter = true
            } label: {
                Label("Importar cómic (.cbz, .zip, .cbr o PDF)", systemImage: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .foregroundStyle(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6])))
            }
            .buttonStyle(.plain)
            .disabled(library.importing)
            .padding(.top, 16)

            if library.importing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importando… los archivos grandes (y los .cbr, que se convierten a .cbz) pueden tardar un poco.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.top, 14)
            }
        }
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { option in
                    Button { mode = option } label: {
                        Text(option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundStyle(mode == option ? Theme.paper : Theme.ink)
                            .background(mode == option ? Theme.ink : Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
        .padding(.top, 20)
    }

    // MARK: Todos

    private var allView: some View {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        let filtered = library.items.filter { comic in
            q.isEmpty || "\(comic.displayTitle) \(comic.title) \(comic.cvIssueName ?? "")"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(q)
        }
        let sorted: [LocalComic]
        switch sort {
        case .recent:
            sorted = filtered.sorted { ($0.lastOpened ?? $0.added) > ($1.lastOpened ?? $1.added) }
        case .az:
            sorted = filtered.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .newest, .oldest:
            // Los que no tienen fecha (sin ficha de Comic Vine) van al final, por nombre.
            let newestFirst = sort == .newest
            sorted = filtered.sorted { a, b in
                switch (a.publicationDate, b.publicationDate) {
                case let (x?, y?) where x != y: return newestFirst ? x > y : x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if a.cvSeriesID == b.cvSeriesID, a.cvSeriesID != nil {
                        return newestFirst ? LibraryGrouping.byNumber(b, a) : LibraryGrouping.byNumber(a, b)
                    }
                    return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
                }
            }
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                    TextField("Buscar por nombre", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))

                Menu {
                    Picker("Ordenar", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.menuLabel).tag($0) }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if sorted.isEmpty {
                Text("No hay cómics que coincidan con la búsqueda.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            } else {
                ComicGrid(comics: sorted)
            }
        }
        .padding(.top, 16)
    }

    // MARK: Series y Estado

    private var seriesView: some View {
        let groups = LibraryGrouping.series(library.items)
        return FolderGrid {
            ForEach(groups) { group in
                NavigationLink(value: LibraryRoute.series(group.seriesID)) {
                    FolderCard(title: group.name, subtitle: countText(group.comics.count),
                               cover: group.comics.first, icon: "questionmark.folder")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }

    private var statusView: some View {
        FolderGrid {
            ForEach(ReadState.allCases) { state in
                let comics = LibraryGrouping.comics(in: state, library.items)
                NavigationLink(value: LibraryRoute.status(state)) {
                    FolderCard(title: state.label, subtitle: countText(comics.count),
                               cover: comics.first, icon: state.icon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }
}

/// Selector de archivos del iPhone. Pide una COPIA de cada archivo elegido:
/// así funciona también dentro de LiveContainer, donde leer el original puede fallar.
private struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.pdf, .zip, .data]
        for ext in ["cbz", "cbr"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}
