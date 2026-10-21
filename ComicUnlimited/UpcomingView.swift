import SwiftUI
import UIKit
import Observation

// Pestaña Próximos: qué cómics salen en las próximas semanas, día por día.
// Semanas que vienen: Metron primero. Semanas pasadas ("Recién salidos"): Comic Vine primero.

/// De dónde salieron los datos que se muestran.
enum UpcomingSource: String {
    case metron = "Metron"
    case comicVine = "Comic Vine"
}

@MainActor
@Observable
final class UpcomingModel {
    enum LoadState {
        case idle
        case loading
        case loaded([UpcomingIssue], UpcomingSource)
        /// `badLogin` dice qué cuenta hay que revisar, si el problema es el usuario o la clave.
        case failed(String, badLogin: UpcomingSource?)
    }

    /// Cuántas semanas hacia adelante se pueden mirar.
    static let maxWeek = 7
    /// Cuántas semanas hacia atrás ("Recién salidos").
    static let minWeek = -2
    /// Cuántos meses hacia adelante y hacia atrás.
    static let maxMonth = 3
    static let minMonth = -2

    /// Ver de a una semana o de a un mes.
    enum Period: String, CaseIterable, Identifiable {
        case week = "Por semana"
        case month = "Por mes"
        var id: String { rawValue }
    }

    var period: Period = .week
    /// 0 = esta semana (o este mes); 1 = la que viene; -1 = la pasada.
    var weekIndex = 0
    var monthIndex = 0

    var index: Int { period == .week ? weekIndex : monthIndex }
    var canGoBack: Bool { index > (period == .week ? Self.minWeek : Self.minMonth) }
    var canGoForward: Bool { index < (period == .week ? Self.maxWeek : Self.maxMonth) }

    func step(_ delta: Int) {
        if period == .week { weekIndex += delta } else { monthIndex += delta }
    }
    /// Editorial elegida ("Todas" o el texto de un botón).
    var publisherFilter = "Todas"
    private(set) var state: LoadState = .idle
    /// true mientras ya se muestran algunos cómics pero siguen llegando más.
    private(set) var loadingMore = false
    /// Cambia cada vez que se guardan o se borran cuentas, para volver a cargar.
    private(set) var accountsVersion = 0
    /// Semanas ya cargadas, para no volver a pedirlas mientras la app está abierta.
    private var cache: [String: ([UpcomingIssue], UpcomingSource)] = [:]

    var hasMetron: Bool { _ = accountsVersion; return MetronAccount.isSet }
    var hasComicVine: Bool { _ = accountsVersion; return !ComicVineKey.current.isEmpty }
    var hasAnySource: Bool { hasMetron || hasComicVine }

    func saveMetron(user: String, password: String) {
        MetronAccount.save(user: user, password: password)
        accountsChanged()
    }

    func forgetMetron() {
        MetronAccount.forget()
        accountsChanged()
    }

    func saveComicVineKey(_ key: String) {
        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: ComicVineKey.storageKey)
        accountsChanged()
    }

    func forgetComicVineKey() {
        UserDefaults.standard.removeObject(forKey: ComicVineKey.storageKey)
        accountsChanged()
    }

    private func accountsChanged() {
        cache = [:]
        state = .idle
        accountsVersion += 1
    }

    /// Identifica lo que hay que mostrar: semana, editorial y cuentas.
    var loadKey: String { "\(accountsVersion)|\(period.rawValue)|\(index)|\(publisherFilter)" }

    /// Primer y último día de lo elegido. La semana empieza hoy; el mes, el día 1.
    var range: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch period {
        case .week:
            let start = calendar.date(byAdding: .day, value: 7 * weekIndex, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return (start, end)
        case .month:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let start = calendar.date(byAdding: .month, value: monthIndex, to: thisMonth) ?? thisMonth
            let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
            return (start, end)
        }
    }

    func load(force: Bool = false) async {
        guard hasAnySource else { return }
        let key = loadKey
        loadingMore = false
        if !force, let cached = cache[key] {
            state = .loaded(cached.0, cached.1)
            return
        }
        state = .loading
        defer { if key == loadKey { loadingMore = false } }
        let range = self.range
        let filter = publisherFilter
        let isPast = index < 0
        let maxPages = period == .month ? 20 : 6
        // Para semanas que ya pasaron, Comic Vine primero (siempre las tiene).
        // Para las que vienen, Metron primero (Comic Vine no tiene cómics futuros).
        let order: [UpcomingSource] = (isPast ? [.comicVine, .metron] : [.metron, .comicVine])
            .filter { $0 == .metron ? hasMetron : hasComicVine }
        var problems: [String] = []
        var badLogin: UpcomingSource?

        for source in order {
            do {
                let issues = try await fetch(source, range: range, filter: filter, maxPages: maxPages, key: key)
                if source == .comicVine && !isPast && issues.isEmpty && !problems.isEmpty {
                    problems.append("Comic Vine solo tiene cómics que ya salieron, así que no puede mostrar los próximos. Probá más tarde, o tocá la flecha ← para ver lo que ya salió.")
                    break
                }
                finish(issues, source, key: key)
                return
            } catch {
                if let e = error as? MetronError, case .badLogin = e { badLogin = .metron }
                if let e = error as? ComicVineError, case .invalidKey = e { badLogin = .comicVine }
                var message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if source == .metron, let e = error as? MetronError, case .network = e {
                    message = "Metron no responde (se agotó el tiempo de espera). Puede estar caído o muy lento."
                }
                problems.append(message)
            }
        }
        if key == loadKey { state = .failed(problems.joined(separator: "\n\n"), badLogin: badLogin) }
    }

    private func fetch(_ source: UpcomingSource, range: (start: Date, end: Date), filter: String,
                       maxPages: Int, key: String) async throws -> [UpcomingIssue] {
        let publisher = source == .metron ? MetronClient.publishers.first(where: { $0.label == filter }) : nil
        // Muestra lo que va llegando, sin esperar a que termine todo.
        let show: @MainActor ([UpcomingIssue]) -> Void = { [weak self] partial in
            guard let self, key == self.loadKey, !partial.isEmpty else { return }
            var list = partial
            if let publisher { for i in list.indices { list[i].publisher = publisher.label } }
            self.state = .loaded(Self.sorted(list), source)
            self.loadingMore = true
        }
        switch source {
        case .metron:
            var issues = try await MetronClient(user: MetronAccount.user, password: MetronAccount.password)
                .issues(from: range.start, to: range.end, publisher: publisher?.query, maxPages: maxPages, onProgress: show)
            if let publisher {
                for i in issues.indices { issues[i].publisher = publisher.label }
            }
            return issues
        case .comicVine:
            let client = ComicVineKey.client
            // Con Comic Vine no mostramos nada hasta saber la editorial de cada uno: así no se cuelan mangas
            // ni ediciones de otros países.
            var issues = try await client.issues(from: range.start, to: range.end)
            let publishers = await client.publishers(volumeIDs: issues.compactMap(\.volumeID))
            for i in issues.indices {
                if let volume = issues[i].volumeID { issues[i].publisher = publishers[volume] }
            }
            return ComicPublishers.onlyComics(issues)
        }
    }

    private static func sorted(_ issues: [UpcomingIssue]) -> [UpcomingIssue] {
        issues.sorted { ($0.date, $0.title) < ($1.date, $1.title) }
    }

    private func finish(_ issues: [UpcomingIssue], _ source: UpcomingSource, key: String) {
        let sorted = Self.sorted(issues)
        cache[key] = (sorted, source)
        // Si mientras cargaba se cambió de semana o de editorial, no pisamos la pantalla nueva.
        if key == loadKey { state = .loaded(sorted, source) }
    }
}

struct UpcomingView: View {
    @State private var model = UpcomingModel()
    @State private var query = ""
    @State private var showAccounts = false
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Próximos")
                    .font(.system(size: 32, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.7)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if model.hasAnySource {
                    content
                } else {
                    Text("Para ver qué cómics salen, la app necesita una cuenta de Metron o una clave de Comic Vine. Con una alcanza.")
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .padding(.bottom, 12)
                    AccountsForm(model: model)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .task(id: model.loadKey) {
            await model.load()
        }
        .refreshable {
            await model.load(force: true)
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                DiagnosticsView()
                    .navigationTitle("Revisar conexión")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { showDiagnostics = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAccounts) {
            NavigationStack {
                ScrollView {
                    AccountsForm(model: model).padding(18)
                }
                .background(Theme.paper)
                .navigationTitle("Metron y Comic Vine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { showAccounts = false }
                    }
                }
            }
        }
    }

    // MARK: Contenido con alguna cuenta cargada

    @ViewBuilder
    private var content: some View {
        Text("Cómics que salen en comiquerías de Estados Unidos, día por día.")
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)
        periodPicker
        if model.hasMetron {
            // Con Metron, la editorial se elige antes de pedir los datos.
            publisherChips(["Todas"] + MetronClient.publishers.map { $0.label })
        }
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Buscando lanzamientos…").foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .failed(let message, let badLogin):
            failure(message, badLogin: badLogin)
        case .loaded(let issues, let source):
            list(issues, source: source)
            if model.loadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Buscando más…").font(.subheadline).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            footer(source)
        }
        Button {
            showAccounts = true
        } label: {
            Label("Cuentas de Metron y Comic Vine", systemImage: "person.badge.key")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.ink2)
        .padding(.top, 14)
        Button {
            showDiagnostics = true
        } label: {
            Label("Revisar conexión", systemImage: "stethoscope")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.ink2)
        .padding(.top, 8)
    }

    private var periodPicker: some View {
        let range = model.range
        let label: String
        let detail: String
        switch model.period {
        case .week:
            switch model.weekIndex {
            case 0: label = "Esta semana"
            case -1: label = "Semana pasada"
            case ..<(-1): label = "Hace \(-model.weekIndex) semanas"
            default: label = "Semana del \(Self.shortDay.string(from: range.start))"
            }
            detail = "\(Self.shortDay.string(from: range.start)) al \(Self.shortDay.string(from: range.end))"
        case .month:
            let name = Self.monthName.string(from: range.start)
            label = name.prefix(1).uppercased() + name.dropFirst()
            switch model.monthIndex {
            case 0: detail = "Este mes"
            case -1: detail = "Mes pasado"
            case ..<(-1): detail = "Hace \(-model.monthIndex) meses"
            case 1: detail = "El mes que viene"
            default: detail = "En \(model.monthIndex) meses"
            }
        }
        let unit = model.period == .week ? "Semana" : "Mes"
        return VStack(spacing: 10) {
            Picker("Ver", selection: Binding(get: { model.period }, set: { model.period = $0 })) {
                ForEach(UpcomingModel.Period.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    model.step(-1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 40)
                }
                .disabled(!model.canGoBack)
                .accessibilityLabel("\(unit) anterior")
                Spacer()
                VStack(spacing: 2) {
                    Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(detail).font(.caption).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button {
                    model.step(1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 40, height: 40)
                }
                .disabled(!model.canGoForward)
                .accessibilityLabel("\(unit) siguiente")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.magenta)
            .padding(6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        }
        .padding(.top, 14)
    }

    private func publisherChips(_ options: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button { model.publisherFilter = option } label: {
                        Text(option)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(model.publisherFilter == option ? Theme.paper : Theme.ink)
                            .background(model.publisherFilter == option ? Theme.ink : Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func list(_ issues: [UpcomingIssue], source: UpcomingSource) -> some View {
        let filterHere = source == .comicVine
        // Con Comic Vine, los botones de editorial salen de lo que vino esta semana.
        let counts = Dictionary(grouping: issues.compactMap(\.publisher), by: { $0 }).mapValues(\.count)
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6).map(\.key)
        let q = Self.normalize(query)
        let filtered = issues.filter { issue in
            (!filterHere || model.publisherFilter == "Todas" || issue.publisher == model.publisherFilter)
                && (q.isEmpty || Self.normalize("\(issue.title) \(issue.issueName ?? "") \(issue.publisher ?? "")").contains(q))
        }
        let days = Dictionary(grouping: filtered, by: \.date).sorted { $0.key < $1.key }

        if filterHere && !model.hasMetron && !top.isEmpty {
            publisherChips(["Todas"] + top)
        }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
            TextField("Buscar serie", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 14)

        if days.isEmpty {
            Text(issues.isEmpty
                 ? (source == .comicVine && model.index >= 0
                    ? "Comic Vine solo tiene cómics que ya salieron. Para ver los próximos hace falta Metron. Con la flecha ← podés ver lo que ya salió."
                    : "\(source.rawValue) todavía no tiene lanzamientos cargados para estas fechas.")
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

    private func failure(_ message: String, badLogin: UpcomingSource?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Button("Probar de nuevo") {
                    Task { await model.load(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.magenta)
                if badLogin != nil {
                    Button("Revisar cuentas") { showAccounts = true }
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

    private func footer(_ source: UpcomingSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Las fechas pueden cambiar. Datos y portadas: \(source.rawValue). Las portadas pertenecen a sus editoriales.")
            if source == .comicVine {
                Link("Abrir Comic Vine", destination: URL(string: "https://comicvine.gamespot.com")!)
                    .foregroundStyle(Theme.magenta)
            } else {
                Link("Abrir Metron", destination: URL(string: "https://metron.cloud")!)
                    .foregroundStyle(Theme.magenta)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink2)
        .padding(.top, 24)
    }

    // MARK: Utilidades

    static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "MMMM 'de' yyyy"
        return f
    }()

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

/// Un cómic de la lista. Al tocarlo se abre su ficha dentro de la app (si viene de Comic Vine).
private struct UpcomingRow: View {
    @Environment(\.openURL) private var openURL
    let issue: UpcomingIssue

    /// Los de Comic Vine traen su link de Comic Vine; con eso sabemos que `id` es el número en Comic Vine.
    private var isComicVine: Bool { issue.link?.host?.contains("comicvine") == true }

    var body: some View {
        if isComicVine {
            NavigationLink(value: CVRoute.issue(id: issue.id, title: issue.title)) { row(showsArrow: false) }
                .buttonStyle(.plain)
        } else {
            Button {
                if let link = issue.link { openURL(link) }
            } label: { row(showsArrow: issue.link != nil) }
            .buttonStyle(.plain)
        }
    }

    private func row(showsArrow: Bool) -> some View {
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
                Image(systemName: showsArrow ? "arrow.up.right" : "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .contentShape(Rectangle())
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

// MARK: - Cuentas de Metron y Comic Vine

private struct AccountsForm: View {
    let model: UpcomingModel
    @State private var metronUser = ""
    @State private var metronPassword = ""
    @State private var comicVineKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                Text("Metron").font(.headline).foregroundStyle(Theme.ink)
                Text("Recomendado para Próximos: muestra lo que sale cada semana y se puede filtrar por editorial.")
                    .font(.subheadline).foregroundStyle(Theme.ink2)
                if model.hasMetron {
                    Text("Conectado como \(MetronAccount.user)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Button("Quitar cuenta de Metron", role: .destructive) { model.forgetMetron() }
                        .font(.subheadline)
                } else {
                    Link("Crear cuenta en metron.cloud", destination: URL(string: "https://metron.cloud")!)
                        .font(.subheadline).foregroundStyle(Theme.magenta)
                    field(TextField("Usuario de Metron", text: $metronUser))
                    field(SecureField("Contraseña de Metron", text: $metronPassword))
                    saveButton(disabled: metronUser.trimmingCharacters(in: .whitespaces).isEmpty || metronPassword.isEmpty) {
                        model.saveMetron(user: metronUser, password: metronPassword)
                        metronPassword = ""
                    }
                }
            }

            card {
                Text("Comic Vine").font(.headline).foregroundStyle(Theme.ink)
                Text("Se usa en el buscador de cómics reales, y en Próximos si Metron no anda.")
                    .font(.subheadline).foregroundStyle(Theme.ink2)
                if model.hasComicVine {
                    Text("Clave guardada").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Button("Quitar clave de Comic Vine", role: .destructive) { model.forgetComicVineKey() }
                        .font(.subheadline)
                } else {
                    Link("Conseguir clave en comicvine.gamespot.com/api", destination: URL(string: "https://comicvine.gamespot.com/api/")!)
                        .font(.subheadline).foregroundStyle(Theme.magenta)
                    field(TextField("Pegá tu clave acá", text: $comicVineKey).font(.system(.body, design: .monospaced)))
                    saveButton(disabled: comicVineKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        model.saveComicVineKey(comicVineKey)
                        comicVineKey = ""
                    }
                }
            }

            Text("Los datos de las cuentas quedan guardados solo en este iPhone. No se suben a ningún lado. Para Metron conviene usar una contraseña que no uses en otros sitios.")
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func field<F: View>(_ input: F) -> some View {
        input
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func saveButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Guardar")
                .font(.system(size: 16, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(12)
                .foregroundStyle(Theme.paper)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
