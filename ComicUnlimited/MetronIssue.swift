import SwiftUI

// Ficha de un número que viene de Metron (Próximos).
// Si Metron sabe su código de Comic Vine, se abre la ficha de Comic Vine (con todo lo de siempre).
// Si no (lo más común con lo que todavía no salió), se arma una ficha con los datos de Metron.
// Las portadas se cargan al verlas; nunca se guardan.

struct MetronIssueView: View {
    let metronID: Int

    @State private var detail: MetronIssueDetail?
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        Group {
            if let cv = detail?.cvId {
                IssueView(id: cv, title: title)
            } else if let detail {
                ScrollView { content(detail) }
                    .background(Theme.paper)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            } else {
                VStack(spacing: 12) {
                    if let errorText {
                        Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                        Button("Probar de nuevo") { Task { await load() } }
                            .foregroundStyle(Theme.magenta)
                    } else {
                        ProgressView()
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
                .toolbar(.visible, for: .navigationBar)
            }
        }
        .task { if detail == nil { await load() } }
    }

    private var title: String {
        guard let detail else { return "Cómic" }
        return CVText.issueTitle(series: detail.series?.name ?? "Cómic", number: detail.number)
    }

    private func load() async {
        guard let client = MetronClient.current else {
            errorText = "Cargá tu usuario de Metron (en Próximos) para ver esta ficha."
            return
        }
        loading = true
        errorText = nil
        do {
            detail = try await client.issueDetail(id: metronID)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Para guardar en tus listas (con número negativo: todavía no está en Comic Vine).
    private func template(_ d: MetronIssueDetail) -> RealLibrary.Entry {
        let writers = (d.credits ?? []).filter { credit in
            (credit.role ?? []).contains { ($0.name ?? "").lowercased().contains("writer") }
        }
        .compactMap(\.creator)
        .prefix(3)
        .enumerated()
        .map { RealLibrary.Ref(id: -($0.offset + 1), name: $0.element) }
        return RealLibrary.Entry(id: -d.id, kind: .issue, title: title, coverURL: d.image, series: nil,
                                 writers: Array(writers), characters: [], status: nil, rating: nil,
                                 updated: Date().timeIntervalSince1970)
    }

    @ViewBuilder
    private func content(_ d: MetronIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                RemoteCover(url: d.image.flatMap { URL(string: $0) }).frame(width: 130)
                VStack(alignment: .leading, spacing: 6) {
                    if let publisher = d.publisher?.name {
                        Text(publisher.uppercased())
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.magenta)
                    }
                    Text(title)
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                    if let names = d.name?.filter({ !$0.isEmpty }), !names.isEmpty {
                        Text(names.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    if let date = CVText.fullDate(d.storeDate) {
                        Label("Sale el \(date)", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(CVText.join([
                        d.price.map { $0.text }.flatMap { $0.isEmpty ? nil : "\(d.priceCurrency ?? "USD") \($0)" },
                        d.page.map { "\($0) páginas" },
                        d.series?.yearBegan.map { "Serie de \($0)" },
                    ]))
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 10)

            RealLibraryControls(template: template(d))
                .padding(.top, 16)

            if let desc = d.desc?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                SectionTitle("De qué se trata")
                ComicVineSummary(deck: desc, description: nil)
            }

            let credits = Self.groupedCredits(d.credits ?? [])
            if !credits.isEmpty {
                SectionTitle("Autores")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(credits) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.role)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 92, alignment: .leading)
                            Text(group.names.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }

            Text("Comic Vine todavía no tiene este número. Cuando lo cargue, esta ficha pasa sola a la de Comic Vine (y lo que guardaste en tus listas también).")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 20)
            Text("Datos y portadas: Metron. Las portadas pertenecen a sus editoriales.")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
    }

    /// "Writer" → "Guion", etc., con los nombres de cada uno.
    struct CreditGroup: Identifiable {
        let role: String
        let names: [String]
        var id: String { role }
    }

    private static func groupedCredits(_ credits: [MetronIssueDetail.Credit]) -> [CreditGroup] {
        let order = ["Guion", "Dibujo", "Tinta", "Color", "Rotulado", "Portada", "Edición"]
        func spanish(_ role: String) -> String {
            let r = role.lowercased()
            if r.contains("writer") || r.contains("script") || r.contains("plot") { return "Guion" }
            if r.contains("cover") { return "Portada" }
            if r.contains("pencil") || r.contains("artist") { return "Dibujo" }
            if r.contains("ink") { return "Tinta" }
            if r.contains("color") { return "Color" }
            if r.contains("letter") { return "Rotulado" }
            if r.contains("editor") { return "Edición" }
            return role
        }
        var groups: [String: [String]] = [:]
        for credit in credits {
            guard let name = credit.creator else { continue }
            for role in credit.role ?? [] {
                let key = spanish(role.name ?? "")
                if !(groups[key] ?? []).contains(name) { groups[key, default: []].append(name) }
            }
        }
        return groups.map { CreditGroup(role: $0.key, names: $0.value) }
            .sorted { (order.firstIndex(of: $0.role) ?? 99, $0.role) < (order.firstIndex(of: $1.role) ?? 99, $1.role) }
    }
}
