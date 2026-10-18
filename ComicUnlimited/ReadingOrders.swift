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

// MARK: - Elegir una lista de Metron

struct ReadingOrderPicker: View {
    let arcID: Int
    let arcName: String
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var results: [MetronReadingList]?
    @State private var loading = false
    @State private var saving: Int?
    @State private var errorText: String?

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
                    Text("Listas de lectura de Metron. Cada una dice de qué sitio sale su orden.")
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorText {
                    Text(errorText).foregroundStyle(Theme.ink2)
                } else if let results {
                    Section("Elegí una lista") {
                        if results.isEmpty {
                            Text("No encontré listas con ese nombre. Probá con menos palabras (por ejemplo, solo \"Disassembled\").")
                                .foregroundStyle(Theme.ink2)
                        }
                        ForEach(results) { list in
                            Button {
                                Task { await choose(list) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(list.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.ink)
                                        Text(CVText.join([
                                            ReadingSource.name(list.attributionSource).map { "Fuente: \($0)" },
                                            list.user?.username.map { "por \($0)" },
                                        ]))
                                        .font(.caption)
                                        .foregroundStyle(Theme.ink2)
                                    }
                                    Spacer(minLength: 0)
                                    if saving == list.id { ProgressView() }
                                }
                            }
                            .disabled(saving != nil)
                        }
                    }
                }
            }
            .navigationTitle("Orden de lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task { if results == nil { await search() } }
        }
    }

    private func search() async {
        guard let client = MetronClient.current else {
            errorText = "Para usar los órdenes de lectura, cargá tu usuario y contraseña de Metron (en Próximos)."
            return
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        errorText = nil
        do {
            results = try await client.readingLists(name: q)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func choose(_ list: MetronReadingList) async {
        guard let client = MetronClient.current else { return }
        saving = list.id
        defer { saving = nil }
        do {
            let items = try await client.readingListItems(id: list.id)
            let saved = SavedReadingOrder(
                listID: list.id,
                name: list.name,
                slug: list.slug,
                source: list.attributionSource,
                items: items.map {
                    SavedReadingOrder.Item(cvID: $0.issue.cvId,
                                           series: $0.issue.series?.name ?? "Serie",
                                           number: $0.issue.number,
                                           coverDate: $0.issue.coverDate)
                }
            )
            guard !saved.items.isEmpty else {
                errorText = "Esa lista está vacía en Metron. Probá con otra."
                return
            }
            ReadingOrderStore.shared.save(saved, forArc: arcID)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
