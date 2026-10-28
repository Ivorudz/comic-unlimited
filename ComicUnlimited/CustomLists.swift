import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Observation

// Mis listas (Biblioteca → Listas): listas propias con tu propio orden.
// - Se arman a mano: "Agregar a una lista" desde el menú de cada cómic o desde la ficha de cualquier número
//   (aunque no lo tengas), y se ordenan arrastrando.
// - O se suben de una lista .cbl (el formato de órdenes de lectura de las apps de cómics): un archivo,
//   un link o buscándola en la colección pública CBL-ReadingLists. La lista trae todos los números en orden:
//   los que tenés se ven a color y los que te faltan en gris, con "Descargar".
// - "Leer en orden" y "Siguiente número" siguen la lista (ReadingContext.swift).
// Se guardan solo en el iPhone (nombres, códigos de Comic Vine y links de portadas; nunca imágenes).

struct ListItem: Codable, Hashable, Identifiable {
    /// "cv:123" (un número de Comic Vine) o "file:ID" (un archivo tuyo sin ficha).
    var id: String
    var cvID: Int?
    var localID: String?
    var title: String
    /// Serie y número, para buscarlo en tus fuentes si te falta.
    var series: String?
    var number: String?
    var year: String?
    /// Link a la portada de Comic Vine (la imagen se carga al verla).
    var cover: String?

    static func comicVine(_ cvID: Int, title: String, series: String?, number: String?, year: String?, cover: String?) -> ListItem {
        ListItem(id: "cv:\(cvID)", cvID: cvID, localID: nil, title: title, series: series, number: number, year: year, cover: cover)
    }

    /// Un cómic de tu Biblioteca (con su ficha de Comic Vine si la tiene).
    static func from(_ comic: LocalComic) -> ListItem {
        if let cv = comic.cvIssueID {
            return .comicVine(cv, title: comic.displayTitle, series: comic.cvSeriesName, number: comic.cvIssueNumber,
                              year: comic.cvCoverDate.map { String($0.prefix(4)) }, cover: comic.cvCoverURL)
        }
        let info = FileNameInfo(comic.title)
        return ListItem(id: "file:\(comic.id)", cvID: nil, localID: comic.id, title: comic.displayTitle,
                        series: info.series, number: info.number, year: info.year.map { String($0) }, cover: nil)
    }
}

struct CustomList: Codable, Identifiable {
    var id: Int
    var name: String
    var items: [ListItem]
    var created: Double
    /// De dónde salió ("Lista .cbl", "Colección CBL-ReadingLists"…). nil = armada a mano.
    var origin: String?
}

@MainActor
@Observable
final class CustomListStore {
    static let shared = CustomListStore()
    private(set) var lists: [CustomList] = []

    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("mis-listas.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([CustomList].self, from: data) {
            lists = saved
        }
    }

    func list(_ id: Int) -> CustomList? { lists.first { $0.id == id } }

    @discardableResult
    func create(name: String, items: [ListItem] = [], origin: String? = nil) -> CustomList {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = CustomList(id: Int.random(in: 1...Int(Int32.max)), name: clean.isEmpty ? "Mi lista" : clean,
                              items: Self.unique(items), created: Date().timeIntervalSince1970, origin: origin)
        lists.insert(list, at: 0)
        save()
        return list
    }

    func rename(_ id: Int, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        update(id) { $0.name = clean }
    }

    func delete(_ id: Int) {
        lists.removeAll { $0.id == id }
        save()
    }

    func contains(_ item: ListItem, in id: Int) -> Bool {
        list(id)?.items.contains { $0.id == item.id } == true
    }

    /// Agrega al final (si ya estaba, no lo repite).
    func add(_ item: ListItem, to id: Int) {
        update(id) { list in
            if !list.items.contains(where: { $0.id == item.id }) { list.items.append(item) }
        }
    }

    func remove(_ item: ListItem, from id: Int) {
        update(id) { $0.items.removeAll { $0.id == item.id } }
    }

    func remove(at offsets: IndexSet, from id: Int) {
        update(id) { $0.items.remove(atOffsets: offsets) }
    }

    func move(from source: IndexSet, to destination: Int, in id: Int) {
        update(id) { $0.items.move(fromOffsets: source, toOffset: destination) }
    }

    /// Completa nombres y portadas de Comic Vine (de a 100 números por consulta).
    func fillFromComicVine(_ id: Int) async {
        guard !ComicVineKey.current.isEmpty, let list = list(id) else { return }
        let ids = list.items.filter { $0.cover == nil }.compactMap(\.cvID)
        guard !ids.isEmpty, let found = try? await ComicVineKey.client.issues(ids: ids) else { return }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        update(id) { list in
            for i in list.items.indices {
                guard let cv = list.items[i].cvID, let issue = byID[cv] else { continue }
                list.items[i].cover = issue.image?.small?.absoluteString
                if let series = issue.volume?.name {
                    list.items[i].series = series
                    list.items[i].title = CVText.issueTitle(series: series, number: issue.issueNumber)
                }
                if let number = issue.issueNumber { list.items[i].number = number }
                if let date = issue.coverDate { list.items[i].year = String(date.prefix(4)) }
            }
        }
    }

    private func update(_ id: Int, _ change: (inout CustomList) -> Void) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        change(&lists[index])
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(lists) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    private static func unique(_ items: [ListItem]) -> [ListItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    // MARK: Desde una lista .cbl

    /// Pasa una lista .cbl (ya leída) a una lista propia.
    func create(from order: SavedReadingOrder, origin: String) -> CustomList {
        var items: [ListItem] = []
        for (i, entry) in order.items.enumerated() {
            let title = CVText.issueTitle(series: entry.series, number: entry.number)
            let year = entry.coverDate.map { String($0.prefix(4)) }
            if let cv = entry.cvID {
                items.append(.comicVine(cv, title: title, series: entry.series, number: entry.number, year: year, cover: nil))
            } else {
                // Sin código de Comic Vine: igual queda en su lugar, para buscarlo en tus fuentes.
                items.append(ListItem(id: "cbl:\(i):\(title)", cvID: nil, localID: nil, title: title,
                                      series: entry.series, number: entry.number, year: year, cover: nil))
            }
        }
        return create(name: order.name, items: items, origin: origin)
    }
}

extension LocalLibrary {
    /// El cómic tuyo que corresponde a ese elemento de la lista (suelto, o adentro de un TPB).
    func owned(_ item: ListItem) -> LocalComic? {
        if let local = item.localID { return self.item(local) }
        guard let cv = item.cvID else { return nil }
        return items.first { $0.cvIssueID == cv } ?? collectedIssues[cv]
    }

    /// ¿Este cómic está en la lista? (por su ficha, por ser el archivo, o porque es un TPB que trae un número de la lista)
    func isIn(_ comic: LocalComic, _ item: ListItem) -> Bool {
        if item.localID == comic.id { return true }
        guard let cv = item.cvID else { return false }
        return comic.cvIssueID == cv || comic.contents?.contains { $0.cvID == cv } == true
    }
}

// MARK: - Biblioteca → Listas

struct CustomListsSection: View {
    private var store: CustomListStore { CustomListStore.shared }
    private var library: LocalLibrary { LocalLibrary.shared }
    @State private var naming = false
    @State private var newName = ""
    @State private var pickingFile = false
    @State private var askingLink = false
    @State private var link = ""
    @State private var searching = false
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    newName = ""
                    naming = true
                } label: {
                    Label("Nueva lista", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(11)
                        .foregroundStyle(.white)
                        .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Menu {
                    Button { pickingFile = true } label: { Label("Subir un archivo .cbl", systemImage: "doc") }
                    Button { link = ""; askingLink = true } label: { Label("Pegar el link de una lista .cbl", systemImage: "link") }
                    Button { searching = true } label: { Label("Buscar en la colección de listas", systemImage: "magnifyingglass") }
                } label: {
                    Label("Subir lista .cbl", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(11)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Armando la lista…").font(.subheadline).foregroundStyle(Theme.ink2)
                }
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.ink)
            }

            if store.lists.isEmpty {
                Text("Todavía no tenés listas. Armá una con \"Nueva lista\" y sumale cómics desde el menú de cada cómic (mantenelo apretado → Agregar a una lista) o desde la ficha de cualquier número. También podés subir una lista .cbl con un orden de lectura.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            } else {
                FolderGrid {
                    ForEach(store.lists) { list in
                        let owned = list.items.filter { library.owned($0) != nil }.count
                        NavigationLink(value: LibraryRoute.customList(list.id)) {
                            FolderCard(title: list.name,
                                       subtitle: list.items.isEmpty ? "Vacía" : "Tenés \(owned) de \(list.items.count)",
                                       cover: list.items.lazy.compactMap { library.owned($0) }.first,
                                       icon: "list.number")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 18)
        .alert("Nueva lista", isPresented: $naming) {
            TextField("Nombre (por ejemplo: Orden de Batman)", text: $newName)
            Button("Crear") { store.create(name: newName) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Link de una lista .cbl", isPresented: $askingLink) {
            TextField("https://…/lista.cbl", text: $link)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Bajar") { importCBL { try await CBLCatalog.download(link: link) } origin: { "Lista .cbl (link)" } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Sirve el link de GitHub o el link directo al archivo.")
        }
        .sheet(isPresented: $pickingFile) {
            CBLFilePicker { url in
                pickingFile = false
                guard let url else { return }
                importCBL {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let parsed = CBLParser.parse(data)
                    guard !parsed.items.isEmpty else { throw CBLError.badList }
                    let fallback = (url.lastPathComponent as NSString).deletingPathExtension
                    return SavedReadingOrder(listID: 0, name: parsed.name ?? fallback, slug: nil, source: nil,
                                             items: parsed.items, origin: "cbl")
                } origin: { "Lista .cbl" }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $searching) {
            CBLSearchSheet { entry in
                searching = false
                importCBL { try await CBLCatalog.download(entry) } origin: { "Colección CBL-ReadingLists" }
            }
        }
    }

    private func importCBL(_ load: @escaping () async throws -> SavedReadingOrder, origin: @escaping () -> String) {
        message = nil
        working = true
        Task {
            do {
                let order = try await load()
                let list = store.create(from: order, origin: origin())
                working = false
                let owned = list.items.filter { library.owned($0) != nil }.count
                message = "Se armó \"\(list.name)\": \(list.items.count) números, tenés \(owned)."
                await store.fillFromComicVine(list.id)
            } catch {
                working = false
                message = (error as? LocalizedError)?.errorDescription ?? "No se pudo leer la lista."
            }
        }
    }
}

// MARK: - Una lista

struct CustomListView: View {
    let listID: Int
    @Environment(LibraryActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    private var store: CustomListStore { CustomListStore.shared }
    private var library: LocalLibrary { LocalLibrary.shared }
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let list = store.list(listID) {
                content(list)
            } else {
                Text("Esta lista ya no existe.").foregroundStyle(Theme.ink2)
            }
        }
        .background(Theme.paper)
        .onAppear {
            if let list = store.list(listID) {
                BrowsingContext.current = ReadContext(kind: .list, id: listID, name: list.name)
            }
        }
        .task { await store.fillFromComicVine(listID) }
    }

    private func content(_ list: CustomList) -> some View {
        let owned = list.items.filter { library.owned($0) != nil }.count
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(list.items.isEmpty ? "Lista vacía" : "Tenés \(owned) de \(list.items.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let origin = list.origin {
                        Text("Salió de: \(origin)").font(.caption).foregroundStyle(Theme.ink2)
                    }
                    if let next = nextToRead(list) {
                        Button {
                            BrowsingContext.current = ReadContext(kind: .list, id: listID, name: list.name)
                            actions.onRead(next)
                        } label: {
                            Label(next.isFinished ? "Volver a leer en orden"
                                  : next.lastPage == nil ? "Leer en orden" : "Seguir leyendo en orden",
                                  systemImage: "book.fill")
                                .font(.system(size: 15, weight: .heavy))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .foregroundStyle(.white)
                                .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        Text("Abre \(next.displayTitle). Al terminar, \"Siguiente número\" sigue esta lista.")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                if !list.items.isEmpty {
                    Text("Tocá Editar para cambiar el orden (arrastrando) o sacar números. Para sumar cómics: mantené apretado un cómic de la Biblioteca → Agregar a una lista, o desde la ficha de cualquier número.")
                }
            }

            Section {
                ForEach(list.items) { item in
                    row(item, position: (list.items.firstIndex(of: item) ?? 0) + 1)
                }
                .onMove { store.move(from: $0, to: $1, in: listID) }
                .onDelete { store.remove(at: $0, from: listID) }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newName = list.name; renaming = true } label: { Label("Cambiar nombre", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Borrar lista", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Cambiar nombre", isPresented: $renaming) {
            TextField("Nombre", text: $newName)
            Button("Guardar") { store.rename(listID, to: newName) }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Borrar la lista \"\(list.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar lista", role: .destructive) {
                store.delete(listID)
                dismiss()
            }
        } message: {
            Text("Solo se borra la lista. Tus cómics siguen en la Biblioteca.")
        }
    }

    /// El primero de la lista que tenés y no terminaste (si terminaste todos, el primero que tengas).
    private func nextToRead(_ list: CustomList) -> LocalComic? {
        let mine = list.items.compactMap { library.owned($0) }
        return mine.first { !$0.isFinished } ?? mine.first
    }

    @ViewBuilder
    private func row(_ item: ListItem, position: Int) -> some View {
        let comic = library.owned(item)
        let content = HStack(spacing: 12) {
            Text("\(position)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.ink2)
                .frame(width: 26, alignment: .trailing)
            Group {
                if let comic {
                    LocalCover(comic: comic)
                } else {
                    RemoteCover(url: item.cover.flatMap { URL(string: $0) })
                }
            }
            .frame(width: 44)
            .opacity(comic == nil ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(comic == nil ? Theme.ink2 : Theme.ink)
                    .lineLimit(2)
                if let comic {
                    if comic.isFinished {
                        Text("Leído ✓").font(.caption).foregroundStyle(Theme.magenta)
                    } else if comic.isCollection && comic.cvIssueID != item.cvID {
                        Text("En TPB: \(comic.displayTitle)").font(.caption).foregroundStyle(Theme.magenta).lineLimit(1)
                    } else if let page = comic.lastPage {
                        Text("Página \(page + 1) de \(comic.pageCount)").font(.caption).foregroundStyle(Theme.ink2)
                    } else {
                        Text("Lo tenés").font(.caption).foregroundStyle(Theme.ink2)
                    }
                } else {
                    Label(item.localID != nil ? "Ya no está en tu Biblioteca" : "Te falta · Descargar",
                          systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
        if let cv = item.cvID {
            NavigationLink(value: CVRoute.issue(id: cv, title: item.title)) { content }
        } else if let comic {
            NavigationLink(value: LibraryRoute.localComic(comic.id)) { content }
        } else if let series = item.series {
            NavigationLink(value: LibraryRoute.findInSources(series: series, number: item.number)) { content }
        } else {
            content
        }
    }
}

// MARK: - Agregar a una lista

/// Botón "Agregar a una lista" (fichas). Abre la ventana para elegir la lista.
struct AddToListButton: View {
    let item: ListItem
    @State private var open = false

    var body: some View {
        let count = CustomListStore.shared.lists.filter { CustomListStore.shared.contains(item, in: $0.id) }.count
        Button { open = true } label: {
            Label(count == 0 ? "Agregar a una lista" : "En \(count) \(count == 1 ? "lista" : "listas") · Agregar a otra",
                  systemImage: "text.badge.plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.magenta)
        }
        .padding(.top, 10)
        .sheet(isPresented: $open) { AddToListSheet(item: item) }
    }
}

struct AddToListSheet: View {
    let item: ListItem
    @Environment(\.dismiss) private var dismiss
    private var store: CustomListStore { CustomListStore.shared }
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nueva lista", text: $newName)
                        Button("Crear y agregar") {
                            store.create(name: newName, items: [item])
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !store.lists.isEmpty {
                    Section("Tus listas") {
                        ForEach(store.lists) { list in
                            let inside = store.contains(item, in: list.id)
                            Button {
                                if inside { store.remove(item, from: list.id) } else { store.add(item, to: list.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.name).foregroundStyle(Theme.ink)
                                        Text("\(list.items.count) números").font(.caption).foregroundStyle(Theme.ink2)
                                    }
                                    Spacer()
                                    Image(systemName: inside ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(inside ? Theme.magenta : Theme.ink2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agregar a una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.magenta)
    }
}

// MARK: - Subir una lista .cbl

/// Selector de archivos para elegir una lista .cbl (pide una copia, para que funcione en LiveContainer).
private struct CBLFilePicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.xml, .data]
        if let cbl = UTType(filenameExtension: "cbl") { types.insert(cbl, at: 0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

/// Buscar una lista en la colección pública CBL-ReadingLists (por ejemplo "Civil War" o "Batman").
private struct CBLSearchSheet: View {
    let onChoose: (CBLEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paths: [String] = []
    @State private var results: [CBLEntry] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Buscar (por ejemplo: Civil War)", text: $query)
                        .autocorrectionDisabled()
                        .onSubmit { results = CBLCatalog.search(query, in: paths) }
                } footer: {
                    Text("Órdenes de lectura de CBRO, CMRO, League of Comic Geeks, Marvel Guides y otros, de la colección pública CBL-ReadingLists.")
                }
                if loading {
                    HStack { ProgressView(); Text("Bajando el índice de listas…").foregroundStyle(Theme.ink2) }
                }
                if let errorText { Text(errorText).foregroundStyle(Theme.ink) }
                ForEach(results) { entry in
                    Button { onChoose(entry) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).foregroundStyle(Theme.ink)
                            Text(entry.folder).font(.caption).foregroundStyle(Theme.ink2)
                            if let source = ReadingSource.name(entry.source) {
                                Text(source).font(.caption).foregroundStyle(Theme.magenta)
                            }
                        }
                    }
                }
                if !loading && !query.isEmpty && results.isEmpty && errorText == nil {
                    Text("No encontré listas con ese nombre. Probá con menos palabras.").foregroundStyle(Theme.ink2)
                }
            }
            .navigationTitle("Buscar una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .onChange(of: query) { _, text in
                if text.count >= 3 { results = CBLCatalog.search(text, in: paths) } else if text.isEmpty { results = [] }
            }
            .task {
                do { paths = try await CBLCatalog.paths() } catch {
                    errorText = (error as? LocalizedError)?.errorDescription ?? "No se pudo bajar el índice de listas."
                }
                loading = false
            }
        }
        .tint(Theme.magenta)
    }
}
