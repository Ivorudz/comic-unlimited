import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Pestaña Biblioteca: los cómics que tenés en archivos (.cbz, .zip, .cbr, .cb7, .cbt o PDF).
// Arriba se elige cómo verlos: Todos, por Series o por Estado de lectura (carpetas).
// Tocar un cómic abre su ficha (ahí está "Leer"). Mantenerlo apretado muestra más opciones.

struct LibraryView: View {
    /// Formas de ver la Biblioteca (los botones de arriba).
    enum Mode: String, CaseIterable, Identifiable {
        case all = "Todos"
        case series = "Series"
        case arcs = "Arcos"
        case publishers = "Editoriales"
        case status = "Estado"
        case lists = "Listas"
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
    @AppStorage("library.mode") private var mode: Mode = .all
    @AppStorage("library.sort") private var sort: Sort = .recent
    @State private var query = ""
    @State private var showImporter = false
    @State private var problems: [String] = []
    @State private var notices: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if library.items.isEmpty && !library.importing {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Todavía no tenés cómics. Importalos desde la app Archivos (iCloud Drive, Descargas…): .cbz, .cbr, .cb7, .cbt, .zip o PDF.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                            Button { showImporter = true } label: {
                                Label("Importar cómics", systemImage: "plus")
                                    .font(.subheadline.weight(.bold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.magenta)
                        }
                        .padding(.top, 18)
                    } else {
                        modePicker
                        switch mode {
                        case .all: allView
                        case .series: seriesView
                        case .arcs: arcsView
                        case .publishers: publishersView
                        case .status: statusView
                        case .lists: CustomListsSection()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .scrollDismissesKeyboard(.interactively)
            .appDestinations()
            .navigationTitle("Biblioteca")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { BrowsingContext.current = nil }
        }
        .task { await library.completeSeriesInfo() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                showImporter = false
                guard !urls.isEmpty else { return }
                Task {
                    problems = []
                    notices = []
                    problems = await library.importFiles(urls)
                    notices = library.importNotices
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Arriba

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Biblioteca")
                    .font(.system(.largeTitle, weight: .black).width(Theme.titleWidth))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .misprint(0.7)
                Spacer(minLength: 8)
                // Importar: botón redondo al lado del título.
                Button { showImporter = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.magenta, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(library.importing)
                .opacity(library.importing ? 0.5 : 1)
                .accessibilityLabel("Importar cómics")
            }
            .padding(.top, 20)

            ReviewLinksCard()

            // Fuentes y Ver en la compu, chiquitos y en una sola fila.
            HStack(spacing: 10) {
                shortcut(LibraryRoute.sources, title: "Fuentes", icon: "antenna.radiowaves.left.and.right",
                         highlighted: false)
                shortcut(LibraryRoute.webShare, title: WebShare.shared.isOn ? "Compartiendo" : "Ver en la compu",
                         icon: "desktopcomputer", highlighted: WebShare.shared.isOn)
            }
            .padding(.top, 12)

            if library.importing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importando…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.top, 14)
            } else if !notices.isEmpty || !problems.isEmpty {
                importResult
            }
        }
    }

    private func shortcut(_ route: LibraryRoute, title: String, icon: String, highlighted: Bool) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.magenta : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? Theme.magenta : Theme.line))
        }
        .buttonStyle(.plain)
    }

    /// Resultado del último importe: queda a la vista hasta que lo cerrás.
    private var importResult: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(problems.isEmpty ? Theme.ink : Theme.magenta)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notices, id: \.self) { Text($0) }
                ForEach(problems, id: \.self) { Text($0).foregroundStyle(Theme.magenta) }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            Button {
                notices = []
                problems = []
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.ink2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 14)
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

    private var arcsView: some View {
        let groups = LibraryGrouping.arcs(library.items)
        let unlinked = library.items.filter { $0.cvIssueID == nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            if library.arcsPending > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Buscando arcos… faltan \(library.arcsPending)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
            }
            if groups.isEmpty && library.arcsPending == 0 {
                Text("Ninguno de tus cómics tiene un arco cargado en Comic Vine todavía.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            } else {
                FolderGrid {
                    ForEach(groups) { group in
                        NavigationLink(value: LibraryRoute.arc(id: group.arc.id, name: group.arc.name)) {
                            FolderCard(title: group.arc.name, subtitle: countText(group.comics.count),
                                       cover: group.comics.first, icon: "point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if unlinked > 0 {
                Text(unlinked == 1 ? "1 cómic sin ficha no aparece acá." : "\(unlinked) cómics sin ficha no aparecen acá.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.top, 18)
    }

    private var publishersView: some View {
        let groups = LibraryGrouping.publishers(library.items)
        return FolderGrid {
            ForEach(groups, id: \.name) { group in
                NavigationLink(value: LibraryRoute.publisher(group.name)) {
                    FolderCard(title: group.name, subtitle: countText(group.comics.count),
                               cover: group.comics.first, icon: "building.2")
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
        for ext in ["cbz", "cbr", "cb7", "cbt", "rar", "7z", "tar"] {
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
