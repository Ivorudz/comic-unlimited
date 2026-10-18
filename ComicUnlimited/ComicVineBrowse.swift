import SwiftUI

// Buscador de cómics reales con Comic Vine: series, sus números y la ficha de cada número.
// Datos y portadas: Comic Vine. Las portadas se cargan al momento y no se guardan.

/// A qué pantalla de Comic Vine ir.
enum CVRoute: Hashable {
    case search
    case series(id: Int, name: String)
    case issue(id: Int, title: String)
    case arc(id: Int, name: String)
}

/// La clave de Comic Vine guardada en este iPhone (se carga en la pestaña Próximos).
enum ComicVineKey {
    static let storageKey = "comicvine.apiKey"
    static var current: String { UserDefaults.standard.string(forKey: storageKey) ?? "" }
    static var client: ComicVineClient { ComicVineClient(apiKey: current) }
}

/// Elige la pantalla según la ruta.
struct CVDestination: View {
    let route: CVRoute

    var body: some View {
        switch route {
        case .search:
            SeriesSearchView()
        case .series(let id, let name):
            SeriesView(id: id, name: name)
        case .issue(let id, let title):
            IssueView(id: id, title: title)
        case .arc(let id, let name):
            ArcFolderView(arcID: id, name: name)
        }
    }
}

// MARK: - Buscador

struct SeriesSearchView: View {
    @State private var query = ""
    @State private var results: [CVVolumeSummary]?
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if ComicVineKey.current.isEmpty {
                    NoKeyNotice()
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                        TextField("Nombre de la serie, por ejemplo Batman", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($focused)
                            .onSubmit { Task { await search() } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))

                    Text("Escribí y tocá Buscar en el teclado.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 6)

                    if loading {
                        LoadingRow(text: "Buscando en Comic Vine…")
                    } else if let errorText {
                        ErrorNotice(text: errorText) { Task { await search() } }
                    } else if let results {
                        if results.isEmpty {
                            Text("No encontré series con ese nombre. Probá en inglés o con menos palabras.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(results) { series in
                                NavigationLink(value: CVRoute.series(id: series.id, name: series.name ?? "Serie")) {
                                    SeriesRow(series: series)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                AttributionFooter(link: nil)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Cómics reales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { if results == nil { focused = true } }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        focused = false
        loading = true
        errorText = nil
        do {
            results = try await ComicVineKey.client.searchSeries(q)
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }
}

private struct SeriesRow: View {
    let series: CVVolumeSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteCover(url: series.image?.small).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(series.name ?? "Sin título")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(CVText.join([
                    series.publisher?.name,
                    series.startYear,
                    series.countOfIssues.map { "\($0) \($0 == 1 ? "número" : "números")" },
                ]))
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

// MARK: - Ficha de una serie

struct SeriesView: View {
    let id: Int
    let name: String

    @State private var detail: CVVolumeDetail?
    @State private var issues: [CVIssueSummary] = []
    @State private var total = 0
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let detail {
                    header(detail)
                    RealLibraryControls(series: detail)
                    if let text = CVText.plain(detail.description) ?? CVText.plain(detail.deck) {
                        ComicVineText(text: text).padding(.top, 16)
                    }
                    SectionTitle("Números")
                    if issues.isEmpty {
                        Text("Comic Vine no tiene números cargados para esta serie.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    ForEach(issues) { issue in
                        NavigationLink(value: CVRoute.issue(id: issue.id, title: CVText.issueTitle(series: detail.name ?? name, number: issue.issueNumber))) {
                            IssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                    }
                    if issues.count < total {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Text(loadingMore ? "Cargando…" : "Ver más números (\(total - issues.count) más)")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingMore)
                        .padding(.top, 14)
                    }
                    AttributionFooter(link: detail.siteDetailUrl.flatMap { URL(string: $0) })
                } else if loading {
                    LoadingRow(text: "Cargando la serie…")
                } else if let errorText {
                    ErrorNotice(text: errorText) { Task { await load() } }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if detail == nil { await load() } }
    }

    private func header(_ d: CVVolumeDetail) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            RemoteCover(url: d.image?.medium).frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(d.name ?? name)
                    .font(.system(size: 24, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                if let publisher = d.publisher?.name {
                    Text(publisher).font(.subheadline).foregroundStyle(Theme.ink2)
                }
                Text(CVText.join([
                    d.startYear.map { "Desde \($0)" },
                    d.countOfIssues.map { "\($0) \($0 == 1 ? "número" : "números")" },
                ]))
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
            }
        }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            let client = ComicVineKey.client
            detail = try await client.series(id: id)
            let page = try await client.issues(ofSeries: id, offset: 0)
            issues = page.items
            total = page.total
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }

    private func loadMore() async {
        loadingMore = true
        if let page = try? await ComicVineKey.client.issues(ofSeries: id, offset: issues.count) {
            let known = Set(issues.map(\.id))
            issues += page.items.filter { !known.contains($0.id) }
            total = page.total
            if page.items.isEmpty { total = issues.count }
        }
        loadingMore = false
    }
}

private struct IssueRow: View {
    let issue: CVIssueSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteCover(url: issue.image?.small).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.issueNumber.map { "#\($0)" } ?? "Sin número")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let name = issue.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    Text(name)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let date = CVText.monthYear(issue.coverDate) {
                    Text(date).font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

// MARK: - Ficha de un número

struct IssueView: View {
    let id: Int
    let title: String

    @State private var detail: CVIssueDetail?
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let detail {
                    content(detail)
                } else if loading {
                    LoadingRow(text: "Cargando el cómic…")
                } else if let errorText {
                    ErrorNotice(text: errorText) { Task { await load() } }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if detail == nil { await load() } }
    }

    @ViewBuilder
    private func content(_ d: CVIssueDetail) -> some View {
        RemoteCover(url: d.image?.medium)
            .frame(width: 200)
            .frame(maxWidth: .infinity)

        Text(CVText.issueTitle(series: d.volume?.name ?? title, number: d.issueNumber))
            .font(.system(size: 26, weight: .black).width(.expanded))
            .foregroundStyle(Theme.ink)
            .misprint(0.7)
            .padding(.top, 16)
        if let name = d.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            Text(name).font(.headline).foregroundStyle(Theme.ink).padding(.top, 4)
        }

        VStack(alignment: .leading, spacing: 4) {
            if let store = CVText.fullDate(d.storeDate) {
                Text("Salida en comiquerías: \(store)")
            }
            if let cover = CVText.monthYear(d.coverDate) {
                Text("Fecha de tapa: \(cover)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.ink2)
        .padding(.top, 8)

        if let volume = d.volume {
            NavigationLink(value: CVRoute.series(id: volume.id, name: volume.name ?? "Serie")) {
                Label("Ver toda la serie", systemImage: "books.vertical")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.magenta)
            }
            .padding(.top, 10)
        }

        RealLibraryControls(detail: d)

        if let text = CVText.plain(d.description) ?? CVText.plain(d.deck) {
            SectionTitle("De qué se trata")
            ComicVineText(text: text)
        }

        let credits = CVText.groupCredits(d.personCredits ?? [])
        if !credits.isEmpty {
            SectionTitle("Autores")
            ForEach(credits) { credit in
                HStack(alignment: .firstTextBaseline) {
                    Text(credit.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(credit.roles).font(.footnote).foregroundStyle(Theme.ink2).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }

        let characters = d.characterCredits ?? []
        if !characters.isEmpty {
            SectionTitle("Personajes")
            CharacterStrip(refs: characters)
        }

        let arcs = d.storyArcCredits ?? []
        if !arcs.isEmpty {
            SectionTitle("Forma parte de")
            ArcStrip(refs: arcs)
        }

        AttributionFooter(link: d.siteDetailUrl.flatMap { URL(string: $0) })
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            detail = try await ComicVineKey.client.issue(id: id)
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }
}

// MARK: - Piezas compartidas



private struct LoadingRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct ErrorNotice: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
            Button("Probar de nuevo", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.magenta)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .padding(.top, 16)
    }
}

private struct NoKeyNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Falta tu clave de Comic Vine")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Andá a la pestaña Próximos, pegá tu clave y tocá Guardar. Después volvé acá.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

/// Aviso de dónde salen los datos, con enlace a la ficha en Comic Vine.
private struct AttributionFooter: View {
    let link: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Datos y portadas: Comic Vine. Las portadas pertenecen a sus editoriales.")
            if let link {
                Link("Ver esta ficha en Comic Vine", destination: link)
                    .foregroundStyle(Theme.magenta)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink2)
        .padding(.top, 28)
    }
}

// MARK: - Textos

enum CVText {
    static func message(for error: Error) -> String {
        (error as? ComicVineError)?.errorDescription ?? error.localizedDescription
    }

    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func issueTitle(series: String, number: String?) -> String {
        guard let number, !number.isEmpty else { return series }
        return "\(series) #\(number)"
    }

    private static let apiDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func spanish(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = format
        return f
    }

    private static let monthYearFormatter = spanish("MMMM 'de' yyyy")
    private static let fullFormatter = spanish("d 'de' MMMM 'de' yyyy")

    static func monthYear(_ text: String?) -> String? {
        guard let text, let date = apiDate.date(from: text) else { return nil }
        let s = monthYearFormatter.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func fullDate(_ text: String?) -> String? {
        guard let text, let date = apiDate.date(from: text) else { return nil }
        return fullFormatter.string(from: date)
    }

    /// Comic Vine manda los textos con formato de página web (HTML). Esto les saca las etiquetas.
    static func plain(_ html: String?) -> String? {
        guard var s = html, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(p|h[1-6]|li|div|tr)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#039;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (code, char) in entities { s = s.replacingOccurrences(of: code, with: char) }
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Junta los roles de cada persona y los pasa a español.
    struct CreditLine: Identifiable {
        let name: String
        let roles: String
        var id: String { name }
    }

    static func groupCredits(_ credits: [CVCredit]) -> [CreditLine] {
        let names: [String: String] = [
            "writer": "Guion", "artist": "Dibujo", "penciler": "Lápices", "penciller": "Lápices",
            "inker": "Tintas", "colorist": "Color", "letterer": "Rotulación", "cover": "Portada",
            "editor": "Edición", "other": "Otros",
        ]
        var order: [String] = []
        var roles: [String: [String]] = [:]
        for credit in credits {
            guard let name = credit.name else { continue }
            if roles[name] == nil { order.append(name); roles[name] = [] }
            let parts = (credit.role ?? "").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            for part in parts where !part.isEmpty {
                let label = names[part] ?? part.capitalized
                if !(roles[name]?.contains(label) ?? false) { roles[name]?.append(label) }
            }
        }
        return order.map { CreditLine(name: $0, roles: (roles[$0] ?? []).joined(separator: ", ")) }
    }
}
