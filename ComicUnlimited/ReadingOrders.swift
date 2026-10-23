import SwiftUI
import Observation

// Órdenes de lectura desde Metron (metron.cloud).
// Metron tiene listas de lectura armadas con datos de sitios de referencia
// (Comic Book Reading Orders, Complete Marvel Reading Orders, Comic Book Herald…).
// Cada número de la lista trae su código de Comic Vine, así sabemos exactamente cuáles de tus archivos son.
// La lista elegida para un arco se guarda en este iPhone (solo números y nombres, nada de imágenes).

// MARK: - Datos de Metron

struct MetronList<T: Decodable>: Decodable {
    let count: Int?
    let next: String?
    let results: [T]
}

struct MetronReadingList: Decodable, Identifiable {
    struct Owner: Decodable { let username: String? }
    let id: Int
    let name: String
    let slug: String?
    let user: Owner?
    let listType: String?
    let attributionSource: String?
}

struct MetronReadingListItem: Decodable {
    struct Issue: Decodable {
        struct Series: Decodable {
            let name: String?
            let volume: Int?
            let yearBegan: Int?
        }
        let id: Int
        let series: Series?
        let number: String?
        let coverDate: String?
        let cvId: Int?
    }
    let id: Int
    let issue: Issue
    let order: Int?
}

extension MetronClient {
    /// Listas de lectura públicas con ese nombre.
    func readingLists(name: String) async throws -> [MetronReadingList] {
        var components = URLComponents(string: "https://metron.cloud/api/reading_list/")!
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        var next: URL? = components.url
        var all: [MetronReadingList] = []
        var pages = 0
        while let url = next, pages < 2 {        // cuidamos el límite de Metron
            let page: MetronList<MetronReadingList> = try await get(url)
            all += page.results
            next = page.next.flatMap { URL(string: $0) }
            pages += 1
        }
        return all
    }

    /// Todos los números de una lista, en orden.
    func readingListItems(id: Int) async throws -> [MetronReadingListItem] {
        var next = URL(string: "https://metron.cloud/api/reading_list/\(id)/items/")
        var all: [MetronReadingListItem] = []
        var pages = 0
        while let url = next, pages < 15 {
            let page: MetronList<MetronReadingListItem> = try await get(url)
            all += page.results
            next = page.next.flatMap { URL(string: $0) }
            pages += 1
        }
        // Metron trae el orden de cada número; si falta, queda el orden en que vinieron.
        return all.enumerated()
            .sorted { ($0.element.order ?? $0.offset) < ($1.element.order ?? $1.offset) }
            .map(\.element)
    }

    static var current: MetronClient? {
        MetronAccount.isSet ? MetronClient(user: MetronAccount.user, password: MetronAccount.password) : nil
    }
}

enum ReadingSource {
    static func name(_ code: String?) -> String? {
        switch code?.uppercased() {
        case "CBRO": return "Comic Book Reading Orders"
        case "CMRO": return "Complete Marvel Reading Orders"
        case "CBH": return "Comic Book Herald"
        case "CBT": return "Comic Book Treasury"
        case "MG": return "Marvel Guides"
        case "HTLC": return "How To Love Comics"
        case "LOCG": return "League of Comic Geeks"
        case "OTHER": return "Otra fuente"
        case "OFFICIAL": return "Marvel (oficial)"
        case "COMMUNITY": return "Comunidad"
        default: return nil
        }
    }
}

// MARK: - Guardado en el iPhone

struct SavedReadingOrder: Codable {
    struct Item: Codable, Hashable {
        let cvID: Int?
        let series: String
        let number: String?
        let coverDate: String?
    }
    let listID: Int
    let name: String
    let slug: String?
    let source: String?
    let items: [Item]
    /// De dónde salió: "metron" o "cbl" (colección pública de listas .cbl). nil = Metron (versiones viejas).
    var origin: String? = nil
}

@MainActor
@Observable
final class ReadingOrderStore {
    static let shared = ReadingOrderStore()
    private static let key = "readingOrders"
    private static let modeKey = "readingOrders.useOrder"

    /// Lista elegida para cada arco (por el código del arco en Comic Vine).
    private(set) var orders: [Int: SavedReadingOrder] = [:]
    /// Arcos que se ven por fecha aunque tengan lista (los demás, en orden de lectura).
    private(set) var byDate: Set<Int> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Int: SavedReadingOrder].self, from: data) {
            orders = saved
        }
        byDate = Set(UserDefaults.standard.array(forKey: Self.modeKey) as? [Int] ?? [])
    }

    func save(_ order: SavedReadingOrder, forArc arcID: Int) {
        orders[arcID] = order
        byDate.remove(arcID)
        persist()
    }

    func remove(arc arcID: Int) {
        orders[arcID] = nil
        persist()
    }

    func useReadingOrder(_ on: Bool, arc arcID: Int) {
        if on { byDate.remove(arcID) } else { byDate.insert(arcID) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(orders) { UserDefaults.standard.set(data, forKey: Self.key) }
        UserDefaults.standard.set(Array(byDate), forKey: Self.modeKey)
    }
}

// MARK: - Colección pública de listas .cbl

/// Listas de lectura en formato .cbl (el formato que usan las apps de cómics), de la colección pública
/// github.com/DieselTech/CBL-ReadingLists: órdenes de CBRO, CMRO, League of Comic Geeks, Marvel Guides…
/// armados para usar en apps, con el código de Comic Vine de cada número.
/// La app baja el índice (solo los nombres de las listas) una vez por semana y cada lista cuando la elegís.
struct CBLEntry: Identifiable {
    let path: String
    var id: String { path }

    /// Nombre del archivo, sin ".cbl".
    var title: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// Carpetas donde está, por ejemplo "Marvel › Events › CBRO".
    var folder: String {
        (path as NSString).deletingLastPathComponent.split(separator: "/").joined(separator: " › ")
    }

    /// Sitio del que sale el orden (si se puede saber por el nombre o la carpeta).
    var source: String? {
        let text = path.uppercased()
        if text.contains("CBRO") { return "CBRO" }
        if text.contains("CMRO") { return "CMRO" }
        if text.contains("LOCG") { return "LOCG" }
        if text.contains("(MG)") || text.contains("MARVEL GUIDES") { return "MG" }
        if text.contains("CBH") { return "CBH" }
        if text.contains("CBT") { return "CBT" }
        if text.contains("HTLC") { return "HTLC" }
        if text.contains("/OFFICIAL/") { return "OFFICIAL" }
        if text.contains("COMMUNITY") || text.contains("REDDIT") { return "COMMUNITY" }
        return nil
    }
}

enum CBLError: LocalizedError {
    case github(Int)
    case network(String)
    case badList

    var errorDescription: String? {
        switch self {
        case .github(403), .github(429):
            return "GitHub limitó las consultas por un rato. Probá de nuevo en unos minutos."
        case .github(let code): return "GitHub respondió con un error (código \(code))."
        case .network(let why): return "No se pudo conectar. (\(why))"
        case .badList: return "Ese archivo no parece una lista de lectura .cbl."
        }
    }
}

enum CBLCatalog {
    private static let repo = "DieselTech/CBL-ReadingLists"
    private static let branch = "main"
    private static let session = URLSession(configuration: .ephemeral)

    private struct Index: Codable {
        let fetched: Double
        let paths: [String]
    }

    private static var indexURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("listas-cbl.json")
    }

    /// Nombres de todas las listas (se guardan en el iPhone y se renuevan una vez por semana).
    static func paths() async throws -> [String] {
        let cached = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
        if let cached, Date().timeIntervalSince1970 - cached.fetched < 7 * 24 * 3600 {
            return cached.paths
        }
        do {
            let url = URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1")!
            let data = try await get(url, accept: "application/vnd.github+json")
            struct Tree: Decodable {
                struct Node: Decodable { let path: String; let type: String }
                let tree: [Node]
            }
            let paths = try JSONDecoder().decode(Tree.self, from: data).tree
                .filter { $0.type == "blob" && $0.path.lowercased().hasSuffix(".cbl") }
                .map(\.path)
            if let data = try? JSONEncoder().encode(Index(fetched: Date().timeIntervalSince1970, paths: paths)) {
                try? data.write(to: indexURL)
            }
            return paths
        } catch {
            // Sin conexión o con GitHub limitado: usamos el índice viejo si hay.
            if let cached { return cached.paths }
            throw error
        }
    }

    private static func clean(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    /// Listas cuyo nombre tiene todas las palabras buscadas. Primero las de CBRO y CMRO.
    static func search(_ query: String, in paths: [String]) -> [CBLEntry] {
        let words = clean(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let priority = ["CBRO", "CMRO", "LOCG", "CBH", "MG", "OFFICIAL", "CBT", "HTLC", "COMMUNITY"]
        return paths.map(CBLEntry.init)
            .filter { entry in
                let name = " " + clean(entry.title) + " "
                // Palabras cortas ("of", "m") tienen que estar enteras; las largas pueden ser el comienzo de una palabra.
                return words.allSatisfy { $0.count <= 2 ? name.contains(" \($0) ") : name.contains(" \($0)") }
            }
            .sorted { a, b in
                let pa = priority.firstIndex(of: a.source ?? "") ?? priority.count
                let pb = priority.firstIndex(of: b.source ?? "") ?? priority.count
                return pa != pb ? pa < pb : a.title.count < b.title.count
            }
            .prefix(40)
            .map { $0 }
    }

    /// Baja y lee una lista de la colección.
    static func download(_ entry: CBLEntry) async throws -> SavedReadingOrder {
        let encoded = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? String($0) }
            .joined(separator: "/")
        let url = URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/\(encoded)")!
        return try await download(url, fallbackName: entry.title, source: entry.source, id: entry.path)
    }

    /// Baja y lee una lista desde un link (acepta el link normal de GitHub).
    static func download(link: String) async throws -> SavedReadingOrder {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        // github.com/usuario/repo/blob/rama/archivo.cbl → raw.githubusercontent.com/usuario/repo/rama/archivo.cbl
        if text.contains("github.com/"), text.contains("/blob/") {
            text = text.replacingOccurrences(of: "://github.com/", with: "://raw.githubusercontent.com/")
                .replacingOccurrences(of: "/blob/", with: "/")
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else { throw CBLError.badList }
        let name = ((url.lastPathComponent as NSString).deletingPathExtension).removingPercentEncoding ?? "Lista"
        return try await download(url, fallbackName: name, source: CBLEntry(path: name).source, id: text)
    }

    private static func download(_ url: URL, fallbackName: String, source: String?, id: String) async throws -> SavedReadingOrder {
        let data = try await get(url, accept: "*/*")
        let parsed = CBLParser.parse(data)
        guard !parsed.items.isEmpty else { throw CBLError.badList }
        return SavedReadingOrder(listID: stableID(id),
                                 name: parsed.name ?? fallbackName,
                                 slug: nil,
                                 source: source,
                                 items: parsed.items,
                                 origin: "cbl")
    }

    private static func get(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("ComicUnlimited (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")
        let fetched: (Data, URLResponse)
        do {
            fetched = try await session.data(for: request)
        } catch {
            throw CBLError.network(error.localizedDescription)
        }
        let code = (fetched.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw CBLError.github(code) }
        return fetched.0
    }

    /// Un número fijo para cada lista (el mismo cada vez que se abre la app).
    private static func stableID(_ text: String) -> Int {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash & 0x7FFF_FFFF_FFFF)
    }
}

/// Lee un archivo .cbl: <ReadingList><Name>…</Name><Books><Book Series="" Number="" Year="">
/// <Database Name="cv" Issue="123"/></Book>…
final class CBLParser: NSObject, XMLParserDelegate {
    private var name: String?
    private var items: [SavedReadingOrder.Item] = []
    private var text = ""
    private var book: (series: String, number: String?, year: String?)?
    private var cvID: Int?

    static func parse(_ data: Data) -> (name: String?, items: [SavedReadingOrder.Item]) {
        let delegate = CBLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (delegate.name, delegate.items)
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch element {
        case "Book":
            book = (attributes["Series"] ?? "Serie", attributes["Number"], attributes["Year"])
            cvID = nil
        case "Database":
            if attributes["Name"]?.lowercased() == "cv", let issue = attributes["Issue"].flatMap(Int.init) {
                cvID = issue
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "Name" where name == nil && book == nil:
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { name = value }
        case "Book":
            if let book {
                items.append(SavedReadingOrder.Item(cvID: cvID, series: book.series, number: book.number,
                                                    coverDate: book.year))
            }
            book = nil
        default: break
        }
    }
}

// MARK: - Elegir una lista

struct ReadingOrderPicker: View {
    let arcID: Int
    let arcName: String
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var cbl: [CBLEntry]?
    @State private var cblError: String?
    @State private var metron: [MetronReadingList]?
    @State private var metronError: String?
    @State private var loading = false
    @State private var saving: String?
    @State private var errorText: String?
    @State private var link = ""

    init(arcID: Int, arcName: String) {
        self.arcID = arcID
        self.arcName = arcName
        _query = State(initialValue: arcName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nombre del arco o evento", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button("Buscar") { Task { await search() } }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                    }
                } footer: {
                    Text("Busca órdenes de lectura armados por sitios como Comic Book Reading Orders (CBRO), Complete Marvel Reading Orders (CMRO) y League of Comic Geeks.")
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.magenta) }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Section("Listas de lectura") {
                        if let cblError {
                            Text(cblError).foregroundStyle(Theme.ink2)
                        } else if let cbl, cbl.isEmpty {
                            Text("No encontré listas con ese nombre. Probá con menos palabras (por ejemplo, solo \"Disassembled\").")
                                .foregroundStyle(Theme.ink2)
                        }
                        ForEach(cbl ?? []) { entry in
                            pickRow(id: entry.id, title: entry.title,
                                    detail: CVText.join([ReadingSource.name(entry.source), entry.folder])) {
                                try await CBLCatalog.download(entry)
                            }
                        }
                    }

                    if MetronAccount.isSet {
                        Section("Metron") {
                            if let metronError {
                                Text(metronError).foregroundStyle(Theme.ink2)
                            } else if let metron, metron.isEmpty {
                                Text("Sin listas con ese nombre en Metron.").foregroundStyle(Theme.ink2)
                            }
                            ForEach(metron ?? []) { list in
                                pickRow(id: "metron-\(list.id)", title: list.name,
                                        detail: CVText.join([ReadingSource.name(list.attributionSource),
                                                             list.user?.username.map { "por \($0)" }])) {
                                    try await metronOrder(list)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("https://…/lista.cbl", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Usar este link") {
                        let text = link
                        Task { await choose(id: "link") { try await CBLCatalog.download(link: text) } }
                    }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || saving != nil)
                } header: {
                    Text("¿Tenés el link de una lista .cbl?")
                }
            }
            .navigationTitle("Orden de lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task { if cbl == nil { await search() } }
        }
    }

    private func pickRow(id: String, title: String, detail: String,
                         load: @escaping () async throws -> SavedReadingOrder) -> some View {
        Button {
            Task { await choose(id: id, load: load) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                if saving == id { ProgressView() }
            }
        }
        .disabled(saving != nil)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        errorText = nil
        cblError = nil
        metronError = nil
        do {
            let paths = try await CBLCatalog.paths()
            cbl = CBLCatalog.search(q, in: paths)
        } catch {
            cbl = []
            cblError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        // Metron va aparte (puede tardar o estar caído): no frena las otras listas.
        if let client = MetronClient.current {
            do {
                metron = try await client.readingLists(name: q)
            } catch {
                metron = []
                metronError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func metronOrder(_ list: MetronReadingList) async throws -> SavedReadingOrder {
        guard let client = MetronClient.current else { throw MetronError.badLogin }
        let items = try await client.readingListItems(id: list.id)
        return SavedReadingOrder(
            listID: list.id,
            name: list.name,
            slug: list.slug,
            source: list.attributionSource,
            items: items.map {
                SavedReadingOrder.Item(cvID: $0.issue.cvId,
                                       series: $0.issue.series?.name ?? "Serie",
                                       number: $0.issue.number,
                                       coverDate: $0.issue.coverDate)
            },
            origin: "metron"
        )
    }

    private func choose(id: String, load: () async throws -> SavedReadingOrder) async {
        saving = id
        errorText = nil
        defer { saving = nil }
        do {
            let order = try await load()
            guard !order.items.isEmpty else {
                errorText = "Esa lista está vacía. Probá con otra."
                return
            }
            ReadingOrderStore.shared.save(order, forArc: arcID)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
