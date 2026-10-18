import SwiftUI
import UIKit
import Observation

// Pestaña Próximos: qué cómics salen en las próximas semanas, día por día.
// Datos y portadas: Comic Vine.

@MainActor
@Observable
final class UpcomingModel {
    enum LoadState {
        case idle
        case loading
        case loaded([UpcomingIssue])
        case failed(ComicVineError)
    }

    private static let keyStorage = "comicvine.apiKey"
    /// Cuántas semanas hacia adelante se pueden mirar.
    static let maxWeek = 7

    /// La clave de Comic Vine. Queda guardada solo en este iPhone.
    private(set) var apiKey: String
    var weekIndex = 0
    private(set) var state: LoadState = .idle
    /// Semanas ya cargadas, para no volver a pedirlas mientras la app está abierta.
    private var cache: [Int: [UpcomingIssue]] = [:]

    init() {
        apiKey = UserDefaults.standard.string(forKey: Self.keyStorage) ?? ""
    }

    var hasKey: Bool { !apiKey.isEmpty }

    func saveKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(apiKey, forKey: Self.keyStorage)
        cache = [:]
        state = .idle
    }

    func forgetKey() {
        saveKey("")
    }

    /// Primer y último día de la semana elegida (empieza hoy).
    var weekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: 7 * weekIndex, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return (start, end)
    }

    func load(force: Bool = false) async {
        guard hasKey else { return }
        let week = weekIndex
        if !force, let cached = cache[week] {
            state = .loaded(cached)
            return
        }
        state = .loading
        let client = ComicVineClient(apiKey: apiKey)
        let range = weekRange
        do {
            var issues = try await client.issues(from: range.start, to: range.end)
            let publishers = await client.publishers(volumeIDs: issues.compactMap(\.volumeID))
            for i in issues.indices {
                if let volume = issues[i].volumeID { issues[i].publisher = publishers[volume] }
            }
            issues.sort { ($0.date, $0.title) < ($1.date, $1.title) }
            cache[week] = issues
            // Si mientras cargaba se cambió de semana, no pisamos la pantalla nueva.
            if week == weekIndex { state = .loaded(issues) }
        } catch let error as ComicVineError {
            if week == weekIndex { state = .failed(error) }
        } catch {
            if week == weekIndex { state = .failed(.network(error.localizedDescription)) }
        }
    }
}

struct UpcomingView: View {
    @State private var model = UpcomingModel()
    @State private var publisherFilter = "Todas"
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Próximos")
                    .font(.system(size: 32, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.7)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if model.hasKey {
                    content
                } else {
                    KeySetupView { model.saveKey($0) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(model.apiKey)|\(model.weekIndex)") {
            await model.load()
        }
        .refreshable {
            await model.load(force: true)
        }
    }

    // MARK: Contenido con la clave cargada

    @ViewBuilder
    private var content: some View {
        Text("Cómics que salen en comiquerías de Estados Unidos, día por día.")
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)
        weekPicker
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Buscando en Comic Vine…").foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .failed(let error):
            failure(error)
        case .loaded(let issues):
            list(issues)
        }
        footer
    }

    private var weekPicker: some View {
        let range = model.weekRange
        let label = model.weekIndex == 0 ? "Esta semana" : "Semana del \(Self.shortDay.string(from: range.start))"
        return HStack {
            Button {
                model.weekIndex -= 1
            } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            .disabled(model.weekIndex == 0)
            .accessibilityLabel("Semana anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(Self.shortDay.string(from: range.start)) al \(Self.shortDay.string(from: range.end))")
                    .font(.caption).foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button {
                model.weekIndex += 1
            } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .disabled(model.weekIndex >= UpcomingModel.maxWeek)
            .accessibilityLabel("Semana siguiente")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.magenta)
        .padding(6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .padding(.top, 14)
    }

    @ViewBuilder
    private func list(_ issues: [UpcomingIssue]) -> some View {
        // Botones de editorial: "Todas" y las que más cómics tienen esta semana.
        let counts = Dictionary(grouping: issues.compactMap(\.publisher), by: { $0 }).mapValues(\.count)
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6).map(\.key)
        let options = ["Todas"] + top
        let q = Self.normalize(query)
        let filtered = issues.filter { issue in
            (publisherFilter == "Todas" || issue.publisher == publisherFilter)
                && (q.isEmpty || Self.normalize("\(issue.title) \(issue.issueName ?? "") \(issue.publisher ?? "")").contains(q))
        }
        let days = Dictionary(grouping: filtered, by: \.date).sorted { $0.key < $1.key }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
            TextField("Buscar serie o editorial", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 14)

        if options.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button { publisherFilter = option } label: {
                            Text(option)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(publisherFilter == option ? Theme.paper : Theme.ink)
                                .background(publisherFilter == option ? Theme.ink : Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
            .padding(.top, 12)
        }

        if days.isEmpty {
            Text(issues.isEmpty
                 ? "Comic Vine todavía no tiene lanzamientos cargados para estas fechas."
                 : "No hay cómics que coincidan con la búsqueda.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
                .padding(.vertical, 20)
        } else {
            Text("\(filtered.count) \(filtered.count == 1 ? "cómic" : "cómics")")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 10)
            ForEach(days, id: \.key) { entry in
                DayHeader(date: entry.key)
                ForEach(entry.value) { issue in
                    UpcomingRow(issue: issue)
                }
            }
        }
    }

    private func failure(_ error: ComicVineError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error.errorDescription ?? "Algo salió mal.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Button("Probar de nuevo") {
                    Task { await model.load(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.magenta)
                if case .invalidKey = error {
                    Button("Cambiar la clave") { model.forgetKey() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .padding(.top, 16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Las fechas pueden cambiar. Datos y portadas: Comic Vine. Las portadas pertenecen a sus editoriales.")
            Link("Abrir Comic Vine", destination: URL(string: "https://comicvine.gamespot.com")!)
                .foregroundStyle(Theme.magenta)
            Button("Cambiar la clave de Comic Vine") { model.forgetKey() }
                .foregroundStyle(Theme.ink2)
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink2)
        .padding(.top, 24)
    }

    // MARK: Utilidades

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d 'de' MMMM"
        return f
    }()

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Piezas

/// Título de cada día, por ejemplo "Miércoles 21 de octubre · en 3 días".
private struct DayHeader: View {
    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f
    }()

    private var title: String {
        let s = Self.formatter.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var when: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: date).day ?? 0
        switch days {
        case ..<0: return "ya salió"
        case 0: return "hoy"
        case 1: return "mañana"
        default: return "en \(days) días"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(when)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.magenta)
        }
        .padding(.top, 26)
        .padding(.bottom, 4)
    }
}

/// Un cómic de la lista. Al tocarlo se abre su ficha en Comic Vine.
private struct UpcomingRow: View {
    @Environment(\.openURL) private var openURL
    let issue: UpcomingIssue

    var body: some View {
        Button {
            if let link = issue.link { openURL(link) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteCover(url: issue.coverURL)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 4) {
                    if let publisher = issue.publisher {
                        PublisherLabel(name: publisher)
                    }
                    Text(issue.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let name = issue.issueName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if issue.link != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Etiqueta de color con la editorial, como en el prototipo.
private struct PublisherLabel: View {
    let name: String

    private var colors: (Color, Color) {
        let n = name.lowercased()
        if n.hasPrefix("marvel") { return (Color(hex: 0xD1006C), .white) }
        if n.hasPrefix("dc") { return (Color(hex: 0x00A3D9), .white) }
        if n.hasPrefix("image") { return (Color(hex: 0xFFD400), Color(hex: 0x14161B)) }
        return (Theme.chip, Theme.ink2)
    }

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(colors.1)
            .background(colors.0, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Portada cargada desde Comic Vine en el momento. Mientras carga, muestra un recuadro gris.
struct RemoteCover: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.chip
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(Theme.ink2)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
        .task(id: url) {
            guard let url else { return }
            image = await CoverLoader.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pantalla para cargar la clave

private struct KeySetupView: View {
    let onSave: (String) -> Void
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Para ver qué cómics salen, la app usa Comic Vine. Necesita tu clave (un código que te identifica, como una contraseña).")
                .font(.body)
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Copiá tu clave desde la página de Comic Vine.")
                Link("Abrir comicvine.gamespot.com/api", destination: URL(string: "https://comicvine.gamespot.com/api/")!)
                    .foregroundStyle(Theme.magenta)
                Text("2. Pegala acá abajo y tocá Guardar.")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)

            TextField("Pegá tu clave acá", text: $key)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

            Button {
                onSave(key)
            } label: {
                Text("Guardar")
                    .font(.system(size: 17, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .foregroundStyle(Theme.paper)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("La clave queda guardada solo en este iPhone. No se sube a ningún lado.")
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 8)
    }
}
