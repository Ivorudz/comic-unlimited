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

    /// Si es un número suelto o una serie completa.
    enum Kind: String, Codable {
        case issue, series
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
        /// Puntaje con manitos: -1 = 👎, 1 = 👍, 2 = 👍👍. Se usa en lugar de las estrellas.
        var thumbs: Int? = nil

        var isSeries: Bool { kind == .series }
        /// Clave única: un número y una serie pueden tener el mismo id en Comic Vine.
        var key: String { "\(isSeries ? "series" : "issue")-\(id)" }

        /// Cuánto pesa este cómic en las sugerencias. Negativo = no te gustó.
        var weight: Double {
            if let rating { return Double(rating) - 2.5 }   // 5★ = 2.5 … 1★ = -1.5
            if let thumbs {                                   // 👎 = 1★, 👍 = 4★, 👍👍 = 5★
                switch thumbs {
                case ..<0: return -1.5
                case 1: return 1.5
                default: return 2.5
                }
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
    }

    /// Cambia el puntaje. Tocar la misma estrella de nuevo lo borra.
    /// Puntuar un cómic lo pasa a "Leído" si no estaba en ninguna lista.
    func setRating(_ rating: Int, for template: Entry) {
        var entry = entries[template.key] ?? template
        entry.rating = entry.rating == rating ? nil : rating
        if entry.rating != nil {
            entry.thumbs = nil   // un solo puntaje por cómic
            if entry.status == nil { entry.status = .read }
        }
        save(entry)
    }

    /// Puntaje con manitos (-1, 1 o 2). Tocar la misma de nuevo lo borra; borra las estrellas.
    func setThumbs(_ value: Int, for template: Entry) {
        var entry = entries[template.key] ?? template
        entry.thumbs = entry.thumbs == value ? nil : value
        if entry.thumbs != nil {
            entry.rating = nil
            if entry.status == nil { entry.status = .read }
        }
        save(entry)
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
        if entry.status == nil && entry.rating == nil && entry.thumbs == nil {
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

    init(detail: CVIssueDetail) { template = RealLibrary.makeEntry(detail) }
    init(series: CVVolumeDetail) { template = RealLibrary.makeEntry(series) }

    var body: some View {
        let entry = library.entry(template.key)
        VStack(alignment: .leading, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Tu puntaje").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { n in
                        let on = (entry?.rating ?? 0) >= n
                        Button {
                            library.setRating(n, for: template)
                        } label: {
                            Image(systemName: on ? "star.fill" : "star")
                                .font(.system(size: 28))
                                .foregroundStyle(on ? Theme.star : Theme.line)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n) de 5")
                    }
                }
                HStack(spacing: 8) {
                    Text("o con manitos:").font(.subheadline).foregroundStyle(Theme.ink2)
                    thumbButton(-1, icons: ["hand.thumbsdown"], label: "No me gustó")
                    thumbButton(1, icons: ["hand.thumbsup"], label: "Me gustó")
                    thumbButton(2, icons: ["hand.thumbsup", "hand.thumbsup"], label: "Me encantó")
                }
                .padding(.top, 4)
                Text("Usá estrellas o manitos: si elegís uno, el otro se borra. Tu puntaje y tus listas se usan para \"Para vos\" en Inicio.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.top, 16)
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
            .font(.system(size: 20))
            .foregroundStyle(on ? Theme.paper : (value < 0 ? Theme.ink2 : Theme.magenta))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(on ? (value < 0 ? Theme.ink2 : Theme.magenta) : Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
