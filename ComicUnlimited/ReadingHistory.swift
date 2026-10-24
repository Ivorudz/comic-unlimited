import SwiftUI
import Observation

// Historial de lectura: cada vez que leés un cómic de tu biblioteca se anota cuándo,
// de qué página a qué página y cuánto tiempo. Se ve en Perfil → Historial de lectura.
// Queda guardado solo en el iPhone.

struct ReadingSession: Codable, Identifiable, Hashable {
    var id = UUID()
    let comicID: String
    var title: String
    /// Cuándo empezó y terminó (segundos desde 1970).
    let start: Double
    var end: Double
    /// Primera y última página que viste (la primera es 0).
    var fromPage: Int
    var toPage: Int
    /// Cuántas páginas distintas viste.
    var pages: Int
    /// Llegaste al final del cómic.
    var finished: Bool

    var seconds: Double { max(0, end - start) }
}

@MainActor
@Observable
final class ReadingHistory {
    static let shared = ReadingHistory()
    /// Como mucho se guardan estas lecturas (las más viejas se borran).
    private static let limit = 3000

    /// Lo más nuevo primero.
    private(set) var sessions: [ReadingSession]

    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("historial.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([ReadingSession].self, from: data) {
            sessions = saved
        } else {
            sessions = []
        }
    }

    /// Anota una lectura. Si es el mismo cómic que la anterior y la retomaste enseguida
    /// (menos de 10 minutos después), se suma a esa en vez de crear otra.
    func record(_ session: ReadingSession) {
        if var last = sessions.first, last.comicID == session.comicID, session.start - last.end < 600 {
            last.end = session.end
            last.fromPage = min(last.fromPage, session.fromPage)
            last.toPage = max(last.toPage, session.toPage)
            last.pages += session.pages
            last.finished = last.finished || session.finished
            last.title = session.title
            sessions[0] = last
        } else {
            sessions.insert(session, at: 0)
            if sessions.count > Self.limit { sessions.removeLast(sessions.count - Self.limit) }
        }
        save()
    }

    func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func clear() {
        sessions = []
        save()
    }

    /// Lecturas desde `date`.
    func since(_ date: Date) -> [ReadingSession] {
        let limit = date.timeIntervalSince1970
        return sessions.filter { $0.start >= limit }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    // MARK: Textos

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "menos de 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "Esta semana: 3 cómics, 120 páginas, 2 h 10 min"
    static func summary(_ list: [ReadingSession]) -> String {
        guard !list.isEmpty else { return "Todavía no leíste nada." }
        let comics = Set(list.map(\.comicID)).count
        let pages = list.reduce(0) { $0 + $1.pages }
        let time = list.reduce(0) { $0 + $1.seconds }
        return "\(comics) \(comics == 1 ? "cómic" : "cómics"), \(pages) \(pages == 1 ? "página" : "páginas"), \(duration(time))"
    }

    static var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }
}

// MARK: - Pantalla del historial

struct ReadingHistoryView: View {
    private var history: ReadingHistory { ReadingHistory.shared }
    @State private var confirmClear = false

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return f
    }()

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.timeStyle = .short
        return f
    }()

    private struct Day: Identifiable {
        let id: Date
        let sessions: [ReadingSession]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.sessions) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: $0.start))
        }
        return grouped.keys.sorted(by: >).map { Day(id: $0, sessions: grouped[$0] ?? []) }
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        return Self.dayFormat.string(from: day).capitalized(with: Locale(identifier: "es"))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Últimos 7 días").font(.caption.weight(.bold)).foregroundStyle(Theme.ink2)
                    Text(ReadingHistory.summary(history.since(ReadingHistory.weekStart)))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 2)
            }

            if history.sessions.isEmpty {
                Section {
                    Text("Cuando leas un cómic de tu biblioteca, aparece acá: cuándo, qué páginas y cuánto tiempo.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
            }

            ForEach(days) { day in
                Section(title(for: day.id)) {
                    ForEach(day.sessions) { session in
                        row(session)
                            .swipeActions {
                                Button(role: .destructive) { history.remove(session.id) } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Historial de lectura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.sessions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Borrar todo", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) { history.clear() }
        } message: {
            Text("Solo se borra la lista de lecturas. Tus cómics, por dónde vas y tus listas no cambian.")
        }
    }

    @ViewBuilder
    private func row(_ session: ReadingSession) -> some View {
        let comic = LocalLibrary.shared.item(session.comicID)
        let content = HStack(spacing: 12) {
            if let comic {
                LocalCover(comic: comic).frame(width: 42)
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 42, height: 63)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(comic?.displayTitle ?? session.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text("\(Self.timeFormat.string(from: Date(timeIntervalSince1970: session.start))) · "
                     + "págs. \(session.fromPage + 1)–\(session.toPage + 1) · \(ReadingHistory.duration(session.seconds))")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                if session.finished {
                    Label("Lo terminaste", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.magenta)
                } else if comic == nil {
                    Text("Ya no está en tu biblioteca").font(.caption).foregroundStyle(Theme.ink2)
                }
            }
        }
        if let comic, let issueID = comic.cvIssueID {
            NavigationLink(value: CVRoute.issue(id: issueID, title: comic.displayTitle)) { content }
        } else if let comic {
            NavigationLink(value: LibraryRoute.localComic(comic.id)) { content }
        } else {
            content
        }
    }
}
