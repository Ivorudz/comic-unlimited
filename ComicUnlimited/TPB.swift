import SwiftUI

// TPB (tomos recopilatorios): un solo archivo que trae varios números.
// Cada TPB guarda qué números trae (por su código de Comic Vine). Así, en arcos, series y órdenes de lectura,
// esos números cuentan como tuyos ("en TPB") aunque no tengas los sueltos.
// Para proponer los números, la app lee el texto "Collects Avengers #500-503…" de la ficha de Comic Vine del TPB.

/// Un número que viene dentro de un TPB.
struct ContainedIssue: Codable, Hashable {
    let cvID: Int
    let title: String
    let coverDate: String?
    let cover: String?
}

extension LocalComic {
    /// Es un TPB con números elegidos.
    var isCollection: Bool { !(contents ?? []).isEmpty }
}

extension LocalLibrary {
    /// Tus TPB que traen ese número.
    func collections(containing cvID: Int) -> [LocalComic] {
        items.filter { $0.contents?.contains { $0.cvID == cvID } == true }
    }

    /// Número de Comic Vine → TPB tuyo que lo trae (para mostrarlo "en TPB").
    var collectedIssues: [Int: LocalComic] {
        var map: [Int: LocalComic] = [:]
        for comic in items {
            for issue in comic.contents ?? [] where map[issue.cvID] == nil { map[issue.cvID] = comic }
        }
        return map
    }
}

// MARK: - Tarjeta "en TPB"

/// Un número que no tenés suelto pero sí dentro de un TPB: a color, con la marca "En TPB".
/// Tocarlo abre la ficha del TPB (ahí está "Leer").
struct CollectedIssueCard: View {
    let title: String
    let subtitle: String?
    let cover: URL?
    let tpb: LocalComic

    var body: some View {
        TPBLink(tpb: tpb) {
            VStack(alignment: .leading, spacing: 2) {
                RemoteCover(url: cover)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 6)
                if let subtitle = subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Label("En TPB: \(tpb.displayTitle)", systemImage: "books.vertical.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.magenta)
                    .lineLimit(2)
            }
        }
    }
}

/// Lleva a la ficha de un TPB (la de Comic Vine si tiene; si no, la ficha simple).
struct TPBLink<Label: View>: View {
    let tpb: LocalComic
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            if let issueID = tpb.cvIssueID {
                NavigationLink(value: CVRoute.issue(id: issueID, title: tpb.displayTitle)) { label() }
            } else {
                NavigationLink(value: LibraryRoute.localComic(tpb.id)) { label() }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Botón "¿Qué números trae?" para la ficha de un cómic tuyo.
struct TPBContentsButton: View {
    let comic: LocalComic
    @State private var editing = false

    var body: some View {
        Button {
            editing = true
        } label: {
            Label(comic.isCollection
                  ? "TPB: trae \(comic.contents?.count ?? 0) números · Editar"
                  : "¿Es un TPB? Elegí qué números trae",
                  systemImage: "books.vertical")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.magenta)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            TPBContentsEditor(comicID: comic.id)
        }
    }
}

// MARK: - Leer "Collects …"

enum TPBParser {
    struct Group: Hashable {
        let series: String
        let year: Int?
        let numbers: [String]
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        regex(pattern)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// "Collects Avengers #500-503 and Avengers Finale #1." → [Avengers: 500…503, Avengers Finale: 1]
    static func parse(_ text: String) -> [Group] {
        guard let start = firstMatch(#"(?i)\b(collect(s|ing|ed)?|reprint(s|ing)?)\b[:\s]*"#, in: text),
              let afterRange = Range(start.range, in: text) else { return [] }
        var body = String(text[afterRange.upperBound...].prefix(400))
        body = body.replacingOccurrences(of: #"(?i)\b(vol|no)\.\s*"#, with: "$1 ", options: .regularExpression)
        if let end = firstMatch(#"\.\s+(?=[A-Z])|\.$|\n"#, in: body), let r = Range(end.range, in: body) {
            body = String(body[..<r.lowerBound])
        }

        var groups: [Group] = []
        let segment = regex(#"([A-Za-z0-9][^#]*?)\s*#\s*([0-9][0-9.,\-–&\s#and]*)"#)
        for m in segment?.matches(in: body, range: NSRange(body.startIndex..., in: body)) ?? [] {
            guard let sr = Range(m.range(at: 1), in: body), let nr = Range(m.range(at: 2), in: body) else { continue }
            var series = String(body[sr]).trimmingCharacters(in: .whitespaces)
            series = series.replacingOccurrences(of: #"^(?i:(and|&|,|;|plus|issues?|material from)\s+)+"#,
                                                 with: "", options: .regularExpression)
            var year: Int?
            if let y = firstMatch(#"\((\d{4})\)"#, in: series), let yr = Range(y.range(at: 1), in: series),
               let whole = Range(y.range, in: series) {
                year = Int(series[yr])
                series.removeSubrange(whole)
            }
            series = series.replacingOccurrences(of: #"(?i)\bvol\s*\d+\b"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;&-"))
            let numbers = parseNumbers(String(body[nr]))
            if !series.isEmpty && !numbers.isEmpty { groups.append(Group(series: series, year: year, numbers: numbers)) }
        }
        return groups
    }

    /// "500-503, 505 & 507" → ["500", "501", "502", "503", "505", "507"]
    static func parseNumbers(_ text: String) -> [String] {
        let tokens = text.replacingOccurrences(of: #"\band\b"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: ",&# \t"))
        var numbers: [String] = []
        for token in tokens where !token.isEmpty {
            let parts = token.components(separatedBy: CharacterSet(charactersIn: "-–"))
            if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), b >= a, b - a <= 60 {
                numbers += (a...b).map(String.init)
            } else if token.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
                numbers.append(token)
            }
        }
        return numbers
    }
}

// MARK: - Elegir qué números trae

struct TPBContentsEditor: View {
    let comicID: String
    @Environment(\.dismiss) private var dismiss

    struct Candidate: Identifiable, Hashable {
        let cvID: Int
        let series: String
        let number: String?
        let coverDate: String?
        let cover: String?
        var id: Int { cvID }
        var title: String { CVText.issueTitle(series: series, number: number) }
    }

    @State private var candidates: [Candidate] = []
    @State private var selected: Set<Int> = []
    @State private var loading = false
    @State private var status: String?
    @State private var manualSeries = ""
    @State private var manualNumbers = ""
    @State private var adding = false
    @State private var tpbYear: Int?

    private var library: LocalLibrary { LocalLibrary.shared }
    private var client: ComicVineClient { ComicVineKey.client }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Marcá los números que vienen dentro de este tomo. Después van a aparecer a color en los arcos, las series y los órdenes de lectura, con la marca \"En TPB\".")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                    if let status {
                        Text(status).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                }

                if loading {
                    ProgressView("Buscando en Comic Vine…").frame(maxWidth: .infinity)
                }

                if !candidates.isEmpty {
                    Section("Números (\(selected.count) marcados)") {
                        ForEach(candidates) { c in
                            Button {
                                if selected.contains(c.cvID) { selected.remove(c.cvID) } else { selected.insert(c.cvID) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(c.cvID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(c.cvID) ? Theme.magenta : Theme.ink2)
                                    RemoteCover(url: c.cover.flatMap { URL(string: $0) }).frame(width: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                        if let date = CVText.monthYear(c.coverDate) {
                                            Text(date).font(.caption).foregroundStyle(Theme.ink2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Serie (por ejemplo Avengers)", text: $manualSeries)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Números (por ejemplo 500-503, 505)", text: $manualNumbers)
                        .keyboardType(.numbersAndPunctuation)
                    Button {
                        Task { await addManual() }
                    } label: {
                        if adding { ProgressView() } else { Text("Agregar estos números") }
                    }
                    .disabled(adding || manualSeries.trimmingCharacters(in: .whitespaces).isEmpty
                              || TPBParser.parseNumbers(manualNumbers).isEmpty)
                } header: {
                    Text("Agregar a mano")
                }

                if library.item(comicID)?.isCollection == true {
                    Section {
                        Button("No es un TPB (quitar todos)", role: .destructive) {
                            library.setContents(comicID, [])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(library.item(comicID)?.displayTitle ?? "TPB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(loading)
                }
            }
            .task { if candidates.isEmpty { await load() } }
        }
    }

    private func add(_ list: [Candidate], select: Bool) {
        let known = Set(candidates.map(\.cvID))
        candidates += list.filter { !known.contains($0.cvID) }
        if select { selected.formUnion(list.map(\.cvID)) }
    }

    private func save() {
        let list = candidates.filter { selected.contains($0.cvID) }.map {
            ContainedIssue(cvID: $0.cvID, title: $0.title, coverDate: $0.coverDate, cover: $0.cover)
        }
        library.setContents(comicID, list)
        dismiss()
    }

    private func load() async {
        guard let comic = library.item(comicID) else { return }
        // Lo que ya tenía guardado.
        add((comic.contents ?? []).map {
            Candidate(cvID: $0.cvID, series: $0.title, number: nil, coverDate: $0.coverDate, cover: $0.cover)
        }, select: true)

        guard !ComicVineKey.current.isEmpty else {
            status = "Cargá tu clave de Comic Vine (en Próximos) para que la app te proponga los números."
            return
        }
        guard let tpbID = comic.cvIssueID else {
            status = "Este archivo no tiene ficha de Comic Vine: agregá los números a mano (abajo)."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let detail = try await client.issue(id: tpbID)
            tpbYear = Int((detail.coverDate ?? "").prefix(4))
            let text = [detail.deck, CVText.plain(detail.description)].compactMap { $0 }.joined(separator: "\n")
            let groups = TPBParser.parse(text)

            // Candidatos: los números de los arcos del TPB.
            var arcIssueIDs: [Int] = []
            for arc in (detail.storyArcCredits ?? []).prefix(3) {
                if let full = try? await client.storyArc(id: arc.id) {
                    arcIssueIDs += (full.issues ?? []).map(\.id)
                }
                arcIssueIDs += ReadingOrderStore.shared.orders[arc.id]?.items.compactMap(\.cvID) ?? []
            }
            var seen = Set<Int>([tpbID])
            let ids = Array(arcIssueIDs.filter { seen.insert($0).inserted }.prefix(200))
            let found = ids.isEmpty ? [] : ((try? await client.issues(ids: ids)) ?? [])
            let fromArcs = found.map {
                Candidate(cvID: $0.id, series: $0.volume?.name ?? "Serie", number: $0.issueNumber,
                          coverDate: $0.coverDate, cover: $0.image?.smallUrl ?? $0.image?.thumbUrl)
            }
            .sorted { ($0.coverDate ?? "9999", $0.title) < ($1.coverDate ?? "9999", $1.title) }

            // Los que dice "Collects …" quedan marcados.
            var pending: [TPBParser.Group] = []
            var marked: [Candidate] = []
            for group in groups {
                let target = ComicVineMatcher.normalize(group.series)
                let hits = fromArcs.filter { c in
                    ComicVineMatcher.normalize(c.series) == target && group.numbers.contains(Self.clean(c.number))
                }
                marked += hits
                let foundNumbers = Set(hits.map { Self.clean($0.number) })
                let missing = group.numbers.filter { !foundNumbers.contains($0) }
                if !missing.isEmpty { pending.append(TPBParser.Group(series: group.series, year: group.year, numbers: missing)) }
            }
            add(fromArcs, select: false)
            add(marked, select: true)
            // Los que no estaban en los arcos: se buscan por serie y número.
            for group in pending.prefix(4) {
                add(try await resolve(group), select: true)
            }

            if groups.isEmpty {
                status = fromArcs.isEmpty
                    ? "Comic Vine no dice qué números trae. Agregalos a mano (abajo)."
                    : "Comic Vine no dice qué números trae. Marcá los que correspondan, o agregalos a mano."
            } else {
                status = "Comic Vine dice que trae: " + groups.map { "\($0.series) #\(Self.range($0.numbers))" }
                    .joined(separator: ", ") + ". Revisá que esté bien."
            }
        } catch {
            status = CVText.message(for: error)
        }
    }

    private func addManual() async {
        let group = TPBParser.Group(series: manualSeries.trimmingCharacters(in: .whitespaces), year: nil,
                                    numbers: TPBParser.parseNumbers(manualNumbers))
        guard !ComicVineKey.current.isEmpty else {
            status = "Cargá tu clave de Comic Vine (en Próximos) para buscar los números."
            return
        }
        adding = true
        defer { adding = false }
        do {
            let found = try await resolve(group)
            if found.isEmpty {
                status = "No encontré \(group.series) con esos números en Comic Vine."
            } else {
                add(found, select: true)
                manualNumbers = ""
                status = "Agregados \(found.count) números de \(found.first?.series ?? group.series)."
            }
        } catch {
            status = CVText.message(for: error)
        }
    }

    /// Busca la serie en Comic Vine (la de la época del TPB) y sus números.
    private func resolve(_ group: TPBParser.Group) async throws -> [Candidate] {
        let results = try await client.searchSeries(group.series)
        let target = ComicVineMatcher.normalize(group.series)
        let year = group.year ?? tpbYear
        let named = results.filter { ComicVineMatcher.normalize($0.name ?? "") == target }
        let pool = named.isEmpty ? results : named
        // La serie que empezó en ese año (o la más cercana antes del TPB).
        let series = pool.min { a, b in
            func distance(_ v: CVVolumeSummary) -> Int {
                guard let year, let start = Int(v.startYear ?? "") else { return 500 }
                if group.year != nil { return abs(start - year) }
                return start <= year ? year - start : 100 + (start - year)
            }
            return distance(a) < distance(b)
        }
        guard let series else { return [] }

        var issues: [CVIssueSummary] = []
        if group.numbers.count <= 6 {
            for number in group.numbers {
                if let issue = try await client.findIssue(seriesID: series.id, number: number) { issues.append(issue) }
            }
        } else {
            var offset = 0
            let wanted = Set(group.numbers)
            while offset < 300 {
                let page = try await client.issues(ofSeries: series.id, offset: offset, ascending: true)
                issues += page.items.filter { wanted.contains(Self.clean($0.issueNumber)) }
                offset += page.items.count
                if page.items.isEmpty || offset >= page.total || Set(issues.map { Self.clean($0.issueNumber) }) == wanted { break }
            }
        }
        return issues.map {
            Candidate(cvID: $0.id, series: series.name ?? group.series, number: $0.issueNumber,
                      coverDate: $0.coverDate, cover: $0.image?.smallUrl ?? $0.image?.thumbUrl)
        }
        .sorted { (Double(Self.clean($0.number)) ?? 0) < (Double(Self.clean($1.number)) ?? 0) }
    }

    private static func clean(_ number: String?) -> String {
        let n = (number ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " #"))
        let trimmed = String(n.drop { $0 == "0" })
        return trimmed.isEmpty || trimmed.hasPrefix(".") ? "0" + trimmed : trimmed
    }

    /// ["500","501","502","503"] → "500-503"
    private static func range(_ numbers: [String]) -> String {
        guard let first = numbers.first, let last = numbers.last else { return "" }
        let ints = numbers.compactMap(Int.init)
        if ints.count == numbers.count, ints.count > 1, let a = ints.first, let b = ints.last, a <= b,
           ints == Array(a...b) {
            return "\(first)-\(last)"
        }
        return numbers.joined(separator: ", ")
    }
}
