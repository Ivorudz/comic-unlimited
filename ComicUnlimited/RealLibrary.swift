import SwiftUI
import Observation

// Tus cómics reales: en qué lista los pusiste (Quiero leer, Leyendo, Leído) y qué puntaje les diste.
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

    struct Ref: Codable, Hashable {
        let id: Int
        let name: String
    }

    struct Entry: Codable, Identifiable {
        let id: Int
        var title: String
        var coverURL: String?
        var series: Ref?
        var writers: [Ref]
        var characters: [Ref]
        var status: Status?
        var rating: Int?
        var updated: Double

        /// Cuánto pesa este cómic en las sugerencias. Negativo = no te gustó.
        var weight: Double {
            if let rating { return Double(rating) - 2.5 }   // 5★ = 2.5 … 1★ = -1.5
            switch status {
            case .reading: return 1.5
            case .wantToRead: return 1.0
            case .read: return 0.5
            case nil: return 0
            }
        }
    }

    private static let storageKey = "real.library"
    private(set) var entries: [Int: Entry] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
    }

    func entry(_ id: Int) -> Entry? { entries[id] }

    /// Cambia la lista. Tocar la misma lista de nuevo la saca.
    func toggleStatus(_ status: Status, for detail: CVIssueDetail) {
        var entry = entries[detail.id] ?? Self.makeEntry(detail)
        entry.status = entry.status == status ? nil : status
        save(entry)
    }

    /// Cambia el puntaje. Tocar la misma estrella de nuevo lo borra.
    /// Puntuar un cómic lo pasa a "Leído" si no estaba en ninguna lista.
    func setRating(_ rating: Int, for detail: CVIssueDetail) {
        var entry = entries[detail.id] ?? Self.makeEntry(detail)
        entry.rating = entry.rating == rating ? nil : rating
        if entry.rating != nil && entry.status == nil { entry.status = .read }
        save(entry)
    }

    /// Algo cambió en las listas o los puntajes (sirve para saber cuándo recalcular "Para vos").
    var signature: String {
        entries.values.sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.status?.rawValue ?? "-"):\($0.rating ?? 0)" }
            .joined(separator: ",")
    }

    private func save(_ entry: Entry) {
        var entry = entry
        entry.updated = Date().timeIntervalSince1970
        if entry.status == nil && entry.rating == nil {
            entries[entry.id] = nil
        } else {
            entries[entry.id] = entry
        }
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func makeEntry(_ d: CVIssueDetail) -> Entry {
        let writers = (d.personCredits ?? [])
            .filter { ($0.role ?? "").lowercased().contains("writer") }
            .compactMap { c in c.name.map { Ref(id: c.id, name: $0) } }
        let characters = (d.characterCredits ?? []).prefix(3)
            .compactMap { c in c.name.map { Ref(id: c.id, name: $0) } }
        return Entry(
            id: d.id,
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
}

// MARK: - Botones en la ficha del cómic

/// Listas y estrellas que se muestran en la ficha de un cómic real.
struct RealLibraryControls: View {
    let detail: CVIssueDetail
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        let entry = library.entry(detail.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(RealLibrary.Status.allCases) { status in
                    let on = entry?.status == status
                    Button {
                        library.toggleStatus(status, for: detail)
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
                            library.setRating(n, for: detail)
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
                Text("Tu puntaje y tus listas se usan para las sugerencias de \"Para vos\" en Inicio.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.top, 16)
    }
}
