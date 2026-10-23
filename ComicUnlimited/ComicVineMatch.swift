import SwiftUI

// Une un archivo de tu Biblioteca con su ficha de Comic Vine.
// 1) Lee el nombre del archivo: "Avengers 500 (2004) (digital).cbr" → serie "Avengers", número 500, año 2004.
// 2) Busca la serie en Comic Vine y, dentro de ella, ese número.
// Si no lo encuentra (o elige mal), se puede elegir a mano.

/// Lo que se puede sacar del nombre de un archivo.
struct FileNameInfo {
    var series: String
    let number: String?
    /// Año del archivo; si no tiene, puede venir del nombre del paquete de donde salió.
    var year: Int?

    init(_ raw: String) {
        var s = raw.replacingOccurrences(of: "_", with: " ")

        // Año entre paréntesis, por ejemplo (2004).
        var year: Int?
        if let r = s.range(of: #"\((19|20)\d{2}\)"#, options: .regularExpression) {
            year = Int(s[r].dropFirst().dropLast())
        }
        self.year = year

        // Sacamos todo lo que está entre paréntesis o corchetes: (digital), [grupo], etc.
        s = s.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let tokens = s.split(separator: " ").map(String.init)

        // El número es la última "palabra" que es solo un número (con # o decimales).
        let isNumber: (String) -> Bool = { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil
        }
        if let index = tokens.lastIndex(where: isNumber), index > 0 {
            number = Self.cleanNumber(tokens[index])
            series = Self.cleanSeries(tokens[..<index].joined(separator: " "))
        } else {
            number = nil
            series = Self.cleanSeries(tokens.joined(separator: " "))
        }
    }

    /// "#001" → "1", "000" → "0", "0.5" → "0.5"
    private static func cleanNumber(_ token: String) -> String {
        let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let parts = t.split(separator: ".", maxSplits: 1).map(String.init)
        var whole = String(parts[0].drop { $0 == "0" })
        if whole.isEmpty { whole = "0" }
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }

    private static func cleanSeries(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " -#:,."))
    }
}

enum ComicVineMatcher {
    /// Busca automáticamente la ficha del archivo. Devuelve nil si no está seguro.
    static func find(for info: FileNameInfo) async throws -> (series: CVVolumeSummary, issue: CVIssueSummary)? {
        if let found = try await findExact(for: info) { return found }
        // "34 Fantastic Four 519": el primer número suele ser el orden de lectura del paquete.
        // Si no encontró nada, prueba sin ese número.
        let words = info.series.split(separator: " ")
        if words.count > 1, words[0].allSatisfy(\.isNumber) {
            var shorter = info
            shorter.series = words.dropFirst().joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -#:,."))
            return try await findExact(for: shorter)
        }
        return nil
    }

    private static func findExact(for info: FileNameInfo) async throws -> (series: CVVolumeSummary, issue: CVIssueSummary)? {
        guard !info.series.isEmpty, let number = info.number else { return nil }
        let client = ComicVineKey.client
        let results = try await client.searchSeries(info.series)
        let target = normalize(info.series)

        func score(_ v: CVVolumeSummary) -> Double {
            var s = 0.0
            let name = normalize(v.name ?? "")
            if name == target { s += 10 } else if name.contains(target) || target.contains(name) { s += 4 }
            if let year = info.year, let start = Int(v.startYear ?? "") {
                if start == year { s += 6 } else if start < year && year - start <= 15 { s += 2 } else if start > year { s -= 3 }
            }
            if let n = Double(number), let count = v.countOfIssues, n > Double(count) { s -= 2 }
            return s
        }

        // Probamos las 3 series que mejor coinciden, hasta encontrar el número.
        let candidates = results.map { ($0, score($0)) }
            .filter { $0.1 > 3 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
        for (series, _) in candidates {
            if let issue = try await client.findIssue(seriesID: series.id, number: number) {
                // Si sabemos el año, el número tiene que ser de esa época (evita unirlo a una serie
                // vieja con el mismo nombre, por ejemplo Spectacular Spider-Man de 1976 en vez de 2003).
                if let year = info.year, let issueYear = Int((issue.coverDate ?? "").prefix(4)),
                   abs(issueYear - year) > 2 {
                    continue
                }
                return (series, issue)
            }
        }
        return nil
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "the ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Elegir la ficha a mano

/// Pantalla para buscar y elegir la ficha de Comic Vine de un archivo.
struct LinkPickerView: View {
    let comic: LocalComic
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var results: [CVVolumeSummary]?
    @State private var loading = false
    @State private var errorText: String?

    init(comic: LocalComic) {
        self.comic = comic
        _query = State(initialValue: FileNameInfo(comic.title).series)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nombre de la serie", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        Button("Buscar") { Task { await search() } }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Archivo: \(comic.title)")
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorText {
                    Text(errorText).foregroundStyle(Theme.ink2)
                } else if let results {
                    Section("Elegí la serie") {
                        if results.isEmpty {
                            Text("No encontré series con ese nombre.").foregroundStyle(Theme.ink2)
                        }
                        ForEach(results) { series in
                            NavigationLink {
                                PickIssueView(comic: comic, series: series) { dismiss() }
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteCover(url: series.image?.small).frame(width: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(series.name ?? "Serie").font(.subheadline.weight(.bold))
                                        Text(CVText.join([series.publisher?.name, series.startYear,
                                                          series.countOfIssues.map { "\($0) números" }]))
                                            .font(.caption).foregroundStyle(Theme.ink2)
                                    }
                                }
                            }
                        }
                    }
                }

                if comic.cvIssueID != nil {
                    Section {
                        Button("Quitar la unión con Comic Vine", role: .destructive) {
                            LocalLibrary.shared.unlink(comic.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Ficha de Comic Vine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task { if results == nil && !query.isEmpty { await search() } }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
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

/// Lista de números de una serie para elegir cuál es el archivo.
private struct PickIssueView: View {
    let comic: LocalComic
    let series: CVVolumeSummary
    let onDone: () -> Void

    @State private var issues: [CVIssueSummary] = []
    @State private var total = 0
    @State private var number: String
    @State private var loading = true
    @State private var errorText: String?
    /// Elegiste un número que ya tenés en otro archivo.
    @State private var repeated: (issue: CVIssueSummary, other: LocalComic)?

    init(comic: LocalComic, series: CVVolumeSummary, onDone: @escaping () -> Void) {
        self.comic = comic
        self.series = series
        self.onDone = onDone
        _number = State(initialValue: FileNameInfo(comic.title).number ?? "")
    }

    private var filtered: [CVIssueSummary] {
        let n = number.trimmingCharacters(in: CharacterSet(charactersIn: " #"))
        guard !n.isEmpty else { return issues }
        return issues.filter { ($0.issueNumber ?? "") == n || ($0.issueNumber ?? "").hasPrefix(n) }
    }

    var body: some View {
        List {
            Section {
                TextField("Número (por ejemplo 500)", text: $number)
                    .keyboardType(.numbersAndPunctuation)
            } footer: {
                Text("Escribí el número para encontrarlo más rápido.")
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let errorText {
                Text(errorText).foregroundStyle(Theme.ink2)
            } else {
                Section("Elegí el número") {
                    ForEach(filtered) { issue in
                        Button {
                            if let other = LocalLibrary.shared.owner(ofIssue: issue.id, except: comic.id) {
                                repeated = (issue, other)
                            } else {
                                LocalLibrary.shared.link(comic.id, series: series, issue: issue, reviewed: true)
                                onDone()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                RemoteCover(url: issue.image?.small).frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.issueNumber.map { "#\($0)" } ?? "Sin número")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                    if let name = issue.name, !name.isEmpty {
                                        Text(name).font(.caption).foregroundStyle(Theme.ink2)
                                    }
                                }
                            }
                        }
                    }
                    if issues.count < total {
                        Button("Cargar más números") { Task { await load(more: true) } }
                    }
                }
            }
        }
        .navigationTitle(series.name ?? "Serie")
        .navigationBarTitleDisplayMode(.inline)
        .task { if issues.isEmpty { await load(more: false) } }
        .alert("Ya tenés este cómic", isPresented: Binding(get: { repeated != nil },
                                                          set: { if !$0 { repeated = nil } })) {
            Button("Borrar este archivo repetido", role: .destructive) {
                LocalLibrary.shared.delete(comic)
                repeated = nil
                onDone()
            }
            Button("Cancelar", role: .cancel) { repeated = nil }
        } message: {
            Text("Está en \"\(repeated?.other.displayTitle ?? "otro archivo")\". No puede haber dos archivos del mismo cómic.")
        }
    }

    private func load(more: Bool) async {
        if !more { loading = true }
        do {
            let page = try await ComicVineKey.client.issues(ofSeries: series.id, offset: more ? issues.count : 0)
            issues = more ? issues + page.items : page.items
            total = page.total
        } catch {
            errorText = CVText.message(for: error)
        }
        loading = false
    }
}
