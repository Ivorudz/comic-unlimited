import SwiftUI
import Observation

// Tus cómics reales (números sueltos y series completas): en qué lista los pusiste
// (Quiero leer, Leyendo, Leído) y qué puntaje les diste.
// Se guarda solo en este iPhone, y solo texto (la portada es un enlace, no la imagen).
// "Para vos" usa esto para sugerirte cómics parecidos.

@MainActor
@Observable
final class RealLibrary {
    static let shared = RealLibrary()

    enum Status: String, Codable, CaseIterable, Identifiable {
        case wantToRead = "quiero"
        case reading = "leyendo"
        case read = "leido"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .wantToRead: return "Quiero leer"
            case .reading: return "Leyendo"
            case .read: return "Leído"
            }
        }
    }

    /// Si es un número suelto, una serie completa o un arco argumental.
    enum Kind: String, Codable {
        case issue, series, arc
    }

    struct Ref: Codable, Hashable {
        let id: Int
        let name: String
    }

    struct Entry: Codable, Identifiable {
        let id: Int
        /// Vacío en lo guardado por versiones viejas: eran todos números sueltos.
        var kind: Kind?
        var title: String
        var coverURL: String?
        var series: Ref?
        var writers: [Ref]
        var characters: [Ref]
        var status: Status?
        var rating: Int?
        var updated: Double
        /// Puntaje con manitos: -1 = 👎, 1 = 👍, 2 = 👍👍.
        var thumbs: Int? = nil
        /// Tu comentario (y cuándo lo escribiste).
        var review: String? = nil
        var reviewDate: Double? = nil
        /// En tu colección de Metron (si se mandó): para actualizar ahí las estrellas.
        var metronCollectionID: Int? = nil

        var isSeries: Bool { kind == .series }
        var isArc: Bool { kind == .arc }
        /// Un número suelto (no una serie ni un arco).
        var isIssue: Bool { !isSeries && !isArc }
        /// Clave única: un número, una serie y un arco pueden tener el mismo id en Comic Vine.
        var key: String {
            switch kind {
            case .series: return "series-\(id)"
            case .arc: return "arc-\(id)"
            default: return "issue-\(id)"
            }
        }

        /// Cuánto pesa este cómic en las sugerencias. Negativo = no te gustó.
        var weight: Double {
            // Estrellas: 5★ = 2.5 … 1★ = -1.5. Manitos: 👎 = -1.5, 👍 = 1.5, 👍👍 = 2.5.
            // Si pusiste las dos, cuenta el promedio.
            let stars = rating.map { Double($0) - 2.5 }
            let hands: Double? = thumbs.map { $0 < 0 ? -1.5 : ($0 == 1 ? 1.5 : 2.5) }
            switch (stars, hands) {
            case let (s?, h?): return (s + h) / 2
            case let (s?, nil): return s
            case let (nil, h?): return h
            default: break
            }
            switch status {
            case .reading: return 1.5
            case .wantToRead: return 1.0
            case .read: return 0.5
            case nil: return 0
            }
        }
    }

    private static let storageKey = "real.library"
    private(set) var entries: [String: Entry] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            for entry in list { entries[entry.key] = entry }
        }
    }

    func entry(_ key: String) -> Entry? { entries[key] }

    /// Cambia la lista. Tocar la misma lista de nuevo la saca.
    /// `template` tiene los datos del cómic por si todavía no estaba guardado.
    func toggleStatus(_ status: Status, for template: Entry) {
        var entry = entries[template.key] ?? template
        entry.status = entry.status == status ? nil : status
        save(entry)
        shareWithFriends(entry.key)
    }

    /// Al leer un archivo tuyo unido a Comic Vine: pasa a "Leyendo"; al terminarlo, a "Leído".
    /// Si ya estaba en "Leído", volver a abrirlo no lo cambia.
    /// Datos para guardar un archivo tuyo unido a Comic Vine (nil si no tiene ficha).
    static func makeEntry(_ comic: LocalComic) -> Entry? {
        guard let issueID = comic.cvIssueID else { return nil }
        return Entry(
            id: issueID,
            kind: .issue,
            title: comic.cvTitle ?? comic.displayTitle,
            coverURL: comic.cvCoverURL,
            series: comic.cvSeriesID.map { Ref(id: $0, name: comic.cvSeriesName ?? comic.displayTitle) },
            writers: [],
            characters: [],
            status: nil,
            rating: nil,
            updated: Date().timeIntervalSince1970
        )
    }

    func updateFromReading(_ comic: LocalComic, finished: Bool) {
        guard let template = Self.makeEntry(comic) else { return }
        var entry = entries[template.key] ?? template
        if finished {
            guard entry.status != .read else { return }
            entry.status = .read
        } else {
            guard entry.status != .read && entry.status != .reading else { return }
            entry.status = .reading
        }
        if entry.coverURL == nil { entry.coverURL = comic.cvCoverURL }
        save(entry)
        shareWithFriends(entry.key)
    }

    /// Números guardados desde una ficha de Metron (con id negativo): si Comic Vine ya los tiene,
    /// pasan a su ficha de Comic Vine, con tu lista y tu puntaje.
    private var movingMetron = false
    func moveMetronEntriesToComicVine() async {
        guard !movingMetron, let client = MetronClient.current else { return }
        movingMetron = true
        defer { movingMetron = false }
        let pending = entries.values.filter { $0.id < 0 && $0.isIssue }.prefix(10)
        for old in pending {
            guard let detail = try? await client.issueDetail(id: -old.id), let cv = detail.cvId else { continue }
            var moved = old
            moved = Entry(id: cv, kind: .issue, title: old.title, coverURL: old.coverURL, series: old.series,
                          writers: old.writers, characters: old.characters, status: old.status,
                          rating: old.rating, updated: old.updated, thumbs: old.thumbs)
            entries[old.key] = nil
            if entries[moved.key] == nil { save(moved) } else { save(entries[moved.key]!) }
        }
    }

    /// Cambia el puntaje. Tocar la misma estrella de nuevo lo borra.
    /// Puntuar un cómic lo pasa a "Leído" si no estaba en ninguna lista.
    func setRating(_ rating: Int, for template: Entry) {
        var entry = entries[template.key] ?? template
        entry.rating = entry.rating == rating ? nil : rating
        if entry.rating != nil {
            if entry.status == nil { entry.status = .read }
        }
        save(entry)
        shareWithFriends(entry.key)
        // Si ya está en tu colección de Metron, se actualizan ahí las estrellas.
        if let item = entry.metronCollectionID, let stars = entry.rating {
            Task { await MetronSync.updateRating(collectionID: item, stars: stars) }
        }
    }

    /// Guarda (o borra, si queda vacío) tu comentario.
    func setReview(_ text: String?, for template: Entry) {
        var entry = entries[template.key] ?? template
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entry.review = clean.isEmpty ? nil : clean
        entry.reviewDate = clean.isEmpty ? nil : Date().timeIntervalSince1970
        if entry.review != nil && entry.status == nil { entry.status = .read }
        save(entry)
        shareWithFriends(entry.key)
    }

    /// Si entraste a la comunidad, tu comentario y puntaje se suben (o se borran) allá.
    private func shareWithFriends(_ key: String) {
        let current = entries[key]
        Task { await Community.shared.push(current, key: key) }
    }

    /// Portadas que faltan (por ejemplo, de comentarios guardados antes de que la app guardara la portada):
    /// se piden a Comic Vine de una sola vez.
    private var fillingCovers = false
    func fillMissingCovers() async {
        guard !fillingCovers, !ComicVineKey.current.isEmpty else { return }
        let ids = entries.values.filter { $0.coverURL == nil && $0.id > 0 && $0.isIssue }.map(\.id)
        guard !ids.isEmpty else { return }
        fillingCovers = true
        defer { fillingCovers = false }
        guard let found = try? await ComicVineKey.client.issues(ids: Array(ids.prefix(100))) else { return }
        for issue in found {
            guard var entry = entries["issue-\(issue.id)"],
                  let url = issue.image?.smallUrl ?? issue.image?.thumbUrl else { continue }
            entry.coverURL = url
            entries[entry.key] = entry
        }
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Guarda en qué ítem de tu colección de Metron quedó este número.
    func setMetronCollectionID(_ id: Int, for key: String) {
        guard var entry = entries[key] else { return }
        entry.metronCollectionID = id
        save(entry)
    }

    /// Tus comentarios, el más nuevo primero.
    var reviews: [Entry] {
        entries.values.filter { $0.review != nil }.sorted { ($0.reviewDate ?? 0) > ($1.reviewDate ?? 0) }
    }

    /// Puntaje con manitos (-1, 1 o 2). Tocar la misma de nuevo lo borra. Convive con las estrellas.
    func setThumbs(_ value: Int, for template: Entry) {
        var entry = entries[template.key] ?? template
        entry.thumbs = entry.thumbs == value ? nil : value
        if entry.thumbs != nil {
            if entry.status == nil { entry.status = .read }
        }
        save(entry)
        shareWithFriends(entry.key)
    }

    /// Algo cambió en las listas o los puntajes (sirve para saber cuándo recalcular "Para vos").
    var signature: String {
        entries.values.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.status?.rawValue ?? "-"):\($0.rating ?? 0):\($0.thumbs ?? 0)" }
            .joined(separator: ",")
    }

    private func save(_ entry: Entry) {
        var entry = entry
        entry.updated = Date().timeIntervalSince1970
        if entry.status == nil && entry.rating == nil && entry.thumbs == nil && entry.review == nil {
            entries[entry.key] = nil
        } else {
            entries[entry.key] = entry
        }
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Datos para guardar un número suelto.
    static func makeEntry(_ d: CVIssueDetail) -> Entry {
        let writers = (d.personCredits ?? [])
            .filter { ($0.role ?? "").lowercased().contains("writer") }
            .compactMap { c in c.name.map { Ref(id: c.id, name: $0) } }
        let characters = (d.characterCredits ?? []).prefix(3)
            .compactMap { c in c.name.map { Ref(id: c.id, name: $0) } }
        return Entry(
            id: d.id,
            kind: .issue,
            title: CVText.issueTitle(series: d.volume?.name ?? "Cómic", number: d.issueNumber),
            coverURL: d.image?.smallUrl ?? d.image?.thumbUrl,
            series: d.volume.flatMap { v in v.name.map { Ref(id: v.id, name: $0) } },
            writers: Array(writers.prefix(3)),
            characters: Array(characters),
            status: nil,
            rating: nil,
            updated: Date().timeIntervalSince1970
        )
    }

    /// Al empezar a leer un cómic desde un arco: el arco pasa a "Leyendo"
    /// (si ya estaba en "Leyendo" o en "Leído", no cambia).
    func startedArc(id: Int, name: String) {
        let key = "arc-\(id)"
        var entry = entries[key] ?? Entry(id: id, kind: .arc, title: name, coverURL: nil, series: nil,
                                          writers: [], characters: [], status: nil, rating: nil,
                                          updated: Date().timeIntervalSince1970)
        guard entry.status != .reading && entry.status != .read else { return }
        entry.status = .reading
        save(entry)
        shareWithFriends(key)
    }

    /// Completa la portada de un arco guardado sin portada (cuando se abre su pantalla).
    func completeArc(_ template: Entry) {
        guard var entry = entries[template.key], entry.coverURL == nil, let cover = template.coverURL else { return }
        entry.coverURL = cover
        save(entry)
    }

    /// Datos para guardar un arco argumental.
    static func makeEntry(_ d: CVArcDetail) -> Entry {
        Entry(
            id: d.id,
            kind: .arc,
            title: d.name ?? "Arco",
            coverURL: d.image?.smallUrl ?? d.image?.thumbUrl,
            series: nil,
            writers: [],
            characters: [],
            status: nil,
            rating: nil,
            updated: Date().timeIntervalSince1970
        )
    }

    /// Datos para guardar una serie completa: sus autores y personajes más frecuentes.
    static func makeEntry(_ d: CVVolumeDetail) -> Entry {
        func top(_ list: [CVCountRef]?, _ n: Int) -> [Ref] {
            (list ?? []).sorted { $0.count > $1.count }.prefix(n)
                .compactMap { c in c.name.map { Ref(id: c.id, name: $0) } }
        }
        let name = d.name ?? "Serie"
        return Entry(
            id: d.id,
            kind: .series,
            title: name,
            coverURL: d.image?.smallUrl ?? d.image?.thumbUrl,
            series: Ref(id: d.id, name: name),
            writers: top(d.personCredits, 2),
            characters: top(d.characterCredits, 3),
            status: nil,
            rating: nil,
            updated: Date().timeIntervalSince1970
        )
    }
}

// MARK: - Botones en la ficha del cómic

/// Listas y estrellas que se muestran en la ficha de un cómic real o de una serie.
struct RealLibraryControls: View {
    /// Datos del cómic o la serie, por si todavía no estaba guardado.
    let template: RealLibrary.Entry
    private var library: RealLibrary { RealLibrary.shared }

    /// false = solo estrellas y manitos (al terminar un cómic).
    var showsStatus = true

    init(detail: CVIssueDetail) { template = RealLibrary.makeEntry(detail) }
    init(template: RealLibrary.Entry, showsStatus: Bool = true) {
        self.template = template
        self.showsStatus = showsStatus
    }
    init(series: CVVolumeDetail) { template = RealLibrary.makeEntry(series) }
    init(arc: CVArcDetail) { template = RealLibrary.makeEntry(arc) }

    var body: some View {
        let entry = library.entry(template.key)
        VStack(alignment: .leading, spacing: 14) {
            if showsStatus {
            HStack(spacing: 8) {
                ForEach(RealLibrary.Status.allCases) { status in
                    let on = entry?.status == status
                    Button {
                        library.toggleStatus(status, for: template)
                    } label: {
                        Text(status.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(on ? Theme.paper : Theme.ink)
                            .background(on ? Theme.ink : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tu puntaje").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                // Estrellas y manitos en la misma fila (si no entran, las manitos bajan solas).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        stars
                        Rectangle().fill(Theme.line).frame(width: 1, height: 26)
                        thumbs
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        stars
                        thumbs
                    }
                }
                Text("Podés usar estrellas y manitos a la vez. Tu puntaje y tus listas se usan para \"Para vos\" en Inicio.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.top, 16)
    }

    private var stars: some View {
        let rating = library.entry(template.key)?.rating ?? 0
        return HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { n in
                let on = rating >= n
                Button {
                    library.setRating(n, for: template)
                } label: {
                    Image(systemName: on ? "star.fill" : "star")
                        .font(.system(size: 24))
                        .foregroundStyle(on ? Theme.star : Theme.line)
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) de 5")
            }
        }
    }

    private var thumbs: some View {
        HStack(spacing: 6) {
            thumbButton(-1, icons: ["hand.thumbsdown"], label: "No me gustó")
            thumbButton(1, icons: ["hand.thumbsup"], label: "Me gustó")
            thumbButton(2, icons: ["hand.thumbsup", "hand.thumbsup"], label: "Me encantó")
        }
    }

    private func thumbButton(_ value: Int, icons: [String], label: String) -> some View {
        let on = library.entry(template.key)?.thumbs == value
        return Button {
            library.setThumbs(value, for: template)
        } label: {
            HStack(spacing: 1) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                    Image(systemName: on ? icon + ".fill" : icon)
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(on ? Theme.paper : (value < 0 ? Theme.ink2 : Theme.magenta))
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(on ? (value < 0 ? Theme.ink2 : Theme.magenta) : Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
