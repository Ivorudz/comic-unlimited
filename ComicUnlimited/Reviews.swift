import SwiftUI

// Comentarios y puntaje.
// - Al terminar un cómic: "¿Qué te pareció?" (estrellas, manitos y comentario).
// - En cada ficha: "Tu comentario". En Perfil y en Comunidad: "Mis comentarios".
// - Metron: al terminar un cómic se marca como leído en tu colección de Metron (con tus estrellas)
//   y en cada ficha se ve el promedio de la comunidad de Metron.
// Por ahora todo queda en este iPhone; los amigos llegan con la base de datos (0.29).

// MARK: - Tu comentario (en la ficha)

struct ReviewSection: View {
    let template: RealLibrary.Entry
    @State private var editing = false
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        let entry = library.entry(template.key)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Tu comentario")
            if let review = entry?.review {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if let date = entry?.reviewDate {
                        Text(Date(timeIntervalSince1970: date).formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Button("Editar") { editing = true }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            } else {
                Button {
                    editing = true
                } label: {
                    Label("Escribir un comentario", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $editing) {
            ReviewEditor(template: template)
        }
    }
}

struct ReviewEditor: View {
    let template: RealLibrary.Entry
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(template.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                TextEditor(text: $text)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 180)
                Text("Tu opinión sobre este cómic. Por ahora queda guardada en tu iPhone (más adelante la vas a poder compartir con tus amigos).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                if library.entry(template.key)?.review != nil {
                    Button("Borrar comentario", role: .destructive) {
                        library.setReview(nil, for: template)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                }
                Spacer()
            }
            .padding(18)
            .background(Theme.paper)
            .navigationTitle("Tu comentario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        library.setReview(text, for: template)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = library.entry(template.key)?.review ?? "" }
        }
    }
}

// MARK: - Al terminar un cómic

/// "¿Qué te pareció?": estrellas, manitos y comentario, al final del lector.
struct RateCard: View {
    let comic: LocalComic
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Qué te pareció?")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let template = RealLibrary.makeEntry(comic) {
                RealLibraryControls(template: template, showsStatus: false)
                Button {
                    editing = true
                } label: {
                    Label(RealLibrary.shared.entry(template.key)?.review == nil ? "Escribir un comentario" : "Editar tu comentario",
                          systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $editing) { ReviewEditor(template: template) }
            } else {
                Text("Para puntuarlo y comentarlo, elegile su ficha de Comic Vine (en la Biblioteca: mantené apretado el cómic → Elegir ficha).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Mis comentarios (Perfil y Comunidad)

struct ReviewRow: View {
    let entry: RealLibrary.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteCover(url: entry.coverURL.flatMap { URL(string: $0) }).frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    if let rating = entry.rating {
                        (Text(String(repeating: "★", count: rating)).foregroundStyle(Theme.star)
                            + Text(String(repeating: "★", count: 5 - rating)).foregroundStyle(Theme.line))
                    }
                    if let thumbs = entry.thumbs {
                        Text(thumbs < 0 ? "👎" : thumbs == 1 ? "👍" : "👍👍")
                    }
                    if let date = entry.reviewDate {
                        Text(Date(timeIntervalSince1970: date).formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .font(.caption)
                if let review = entry.review {
                    Text(review)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// Lleva a la ficha del cómic o la serie de un comentario.
struct EntryLink<Label: View>: View {
    let entry: RealLibrary.Entry
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            if entry.id < 0 {
                NavigationLink(value: LibraryRoute.metronIssue(-entry.id)) { label() }
            } else if entry.isSeries {
                NavigationLink(value: CVRoute.series(id: entry.id, name: entry.title)) { label() }
            } else {
                NavigationLink(value: CVRoute.issue(id: entry.id, title: entry.title)) { label() }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Comunidad

struct CommunityView: View {
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Comunidad")
                        .font(.system(size: 32, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 8)
                    Text("Muy pronto: los comentarios y puntajes de tus amigos. Por ahora, acá están los tuyos.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 4)

                    SectionTitle("Mis comentarios")
                    let reviews = library.reviews
                    if reviews.isEmpty {
                        Text("Todavía no comentaste ningún cómic. Al terminar uno, en el lector aparece \"¿Qué te pareció?\". También podés comentar desde la ficha de cualquier cómic.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    ForEach(reviews, id: \.key) { entry in
                        EntryLink(entry: entry) { ReviewRow(entry: entry) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .appDestinations()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { BrowsingContext.current = nil }
        }
    }
}

// MARK: - Metron: "leído" con tus estrellas, y promedio de la comunidad

@MainActor
enum MetronSync {
    static let enabledKey = "settings.metronSync"
    /// Mandar a tu colección de Metron lo que terminás de leer (y tus estrellas). Prendido salvo que lo apagues.
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static var metronIDs: [Int: Int] = [:]
    private static var ratings: [Int: (average: Double, count: Int)] = [:]

    private struct IssueRef: Decodable { let id: Int }

    /// El número de Metron que corresponde a un número de Comic Vine.
    static func metronID(forComicVine cv: Int) async -> Int? {
        if let known = metronIDs[cv] { return known }
        guard let client = MetronClient.current,
              let url = URL(string: "https://metron.cloud/api/issue/?cv_id=\(cv)"),
              let page: MetronList<IssueRef> = try? await client.get(url) else { return nil }
        // Por las dudas: si Metron no entendió el filtro, devuelve muchísimos; solo sirve si es uno.
        guard (page.count ?? page.results.count) == 1, let id = page.results.first?.id else { return nil }
        metronIDs[cv] = id
        return id
    }

    /// Marca como leído en tu colección de Metron (con tus estrellas, si pusiste).
    static func markRead(cvID: Int) async {
        guard enabled, let client = MetronClient.current, let issue = await metronID(forComicVine: cvID) else { return }
        let key = "issue-\(cvID)"
        var body: [String: Any] = ["issue_id": issue]
        if let stars = RealLibrary.shared.entry(key)?.rating { body["rating"] = stars }
        struct Scrobbled: Decodable { let id: Int }
        guard let url = URL(string: "https://metron.cloud/api/collection/scrobble/"),
              let result: Scrobbled = try? await client.send("POST", url, body: body) else { return }
        RealLibrary.shared.setMetronCollectionID(result.id, for: key)
    }

    /// Cambiaste las estrellas de algo que ya está en tu colección de Metron.
    static func updateRating(collectionID: Int, stars: Int) async {
        guard enabled, let client = MetronClient.current,
              let url = URL(string: "https://metron.cloud/api/collection/\(collectionID)/") else { return }
        struct Updated: Decodable { let id: Int }
        let _: Updated? = try? await client.send("PATCH", url, body: ["rating": stars])
    }

    /// Promedio de la comunidad de Metron para un número de Comic Vine.
    static func communityRating(cvID: Int) async -> (average: Double, count: Int)? {
        if let known = ratings[cvID] { return known }
        guard let client = MetronClient.current, let id = await metronID(forComicVine: cvID),
              let detail = try? await client.issueDetail(id: id),
              let result = Self.rating(of: detail) else { return nil }
        ratings[cvID] = result
        return result
    }

    static func rating(of detail: MetronIssueDetail) -> (average: Double, count: Int)? {
        guard let text = detail.averageRating?.text, let average = Double(text), average > 0,
              let count = detail.ratingCount, count > 0 else { return nil }
        return (average, count)
    }
}

/// "Comunidad de Metron: ★ 4.2 (35 votos)" en la ficha de un número.
struct MetronCommunityRating: View {
    let cvID: Int?
    var known: (average: Double, count: Int)? = nil
    @State private var rating: (average: Double, count: Int)?

    var body: some View {
        Group {
            if let rating = known ?? rating {
                Label {
                    Text("Comunidad de Metron: ") + Text(String(format: "★ %.1f", rating.average)).bold()
                        + Text(" (\(rating.count) \(rating.count == 1 ? "voto" : "votos"))")
                } icon: {
                    Image(systemName: "person.3.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 10)
            }
        }
        .task(id: cvID) {
            guard known == nil, let cvID, MetronAccount.isSet else { return }
            rating = await MetronSync.communityRating(cvID: cvID)
        }
    }
}
