import SwiftUI
import Observation

// Personalizar (Perfil → Configuración → Personalizar): color principal, modo claro u oscuro,
// letra de los títulos y qué filas se ven en Inicio (y en qué orden). Se guarda en el iPhone.
// `Theme.magenta` es el color principal elegido (se llama así porque el de fábrica es magenta).

@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    enum Accent: String, CaseIterable, Identifiable {
        case magenta, azul, verde, naranja, violeta, rojo, amarillo
        var id: String { rawValue }

        var name: String {
            switch self {
            case .magenta: return "Magenta"
            case .azul: return "Azul"
            case .verde: return "Verde"
            case .naranja: return "Naranja"
            case .violeta: return "Violeta"
            case .rojo: return "Rojo"
            case .amarillo: return "Amarillo"
            }
        }

        var color: Color { Self.colors[self] ?? Self.fallback }

        private static let fallback = Color(light: 0xD1006C, dark: 0xFF4FA3)
        /// Cada color tiene una versión para modo claro (más oscura, para que se lea) y otra para modo oscuro.
        private static let colors: [Accent: Color] = [
            .magenta: Color(light: 0xD1006C, dark: 0xFF4FA3),
            .azul: Color(light: 0x1F63D6, dark: 0x5AA2FF),
            .verde: Color(light: 0x0B7F45, dark: 0x3DD68C),
            .naranja: Color(light: 0xC2500A, dark: 0xFF9A4D),
            .violeta: Color(light: 0x6E36D9, dark: 0xB18CFF),
            .rojo: Color(light: 0xC81E34, dark: 0xFF5C6E),
            .amarillo: Color(light: 0x9A6B00, dark: 0xFFD400),
        ]
    }

    enum Scheme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var name: String {
            switch self {
            case .system: return "Automático"
            case .light: return "Claro"
            case .dark: return "Oscuro"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum TitleStyle: String, CaseIterable, Identifiable {
        case comic, classic
        var id: String { rawValue }
        var name: String { self == .comic ? "Cómic" : "Clásica" }
    }

    /// Tamaño de las portadas en Inicio y en las grillas de la Biblioteca.
    enum CoverSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var name: String {
            switch self {
            case .small: return "Chicas"
            case .medium: return "Medianas"
            case .large: return "Grandes"
            }
        }
        /// Ancho de cada tarjeta en las filas de Inicio.
        var rowWidth: CGFloat {
            switch self {
            case .small: return 88
            case .medium: return 110
            case .large: return 140
            }
        }
        /// Columnas de las grillas (Biblioteca y "Ver todo").
        var columns: Int {
            switch self {
            case .small: return 4
            case .medium: return 3
            case .large: return 2
            }
        }
    }

    /// Cómo se cuenta el avance en "Seguir leyendo".
    enum ProgressText: String, CaseIterable, Identifiable {
        case left, page, percent
        var id: String { rawValue }
        var name: String {
            switch self {
            case .left: return "Quedan"
            case .page: return "Página"
            case .percent: return "%"
            }
        }
        /// Ejemplo para la pantalla Personalizar.
        var example: String {
            switch self {
            case .left: return "Quedan 17 páginas"
            case .page: return "Página 5 de 22"
            case .percent: return "23 % leído"
            }
        }
    }

    /// Las partes de Inicio que se pueden prender, apagar y ordenar.
    enum HomeSection: String, CaseIterable, Identifiable {
        case continueReading, recent, forYou, mySeries, newSeries, genres, publishers
        var id: String { rawValue }
        var name: String {
            switch self {
            case .continueReading: return "Seguir leyendo"
            case .recent: return "Recién salidos"
            case .forYou: return "Para vos"
            case .mySeries: return "De tus series"
            case .newSeries: return "Series nuevas"
            case .genres: return "Géneros"
            case .publishers: return "Editoriales"
            }
        }
        var icon: String {
            switch self {
            case .continueReading: return "book"
            case .recent: return "sparkles"
            case .forYou: return "heart"
            case .mySeries: return "star"
            case .newSeries: return "1.circle"
            case .genres: return "theatermasks"
            case .publishers: return "building.2"
            }
        }
    }

    private(set) var accent: Accent
    private(set) var scheme: Scheme
    private(set) var titleStyle: TitleStyle
    private(set) var coverSize: CoverSize
    private(set) var progressText: ProgressText
    private(set) var homeOrder: [HomeSection]
    private(set) var homeHidden: Set<HomeSection>

    private enum Key {
        static let accent = "appearance.accent"
        static let scheme = "appearance.scheme"
        static let titleStyle = "appearance.titleStyle"
        static let coverSize = "appearance.coverSize"
        static let progressText = "appearance.progressText"
        static let homeOrder = "appearance.homeOrder"
        static let homeHidden = "appearance.homeHidden"
    }

    private init() {
        let d = UserDefaults.standard
        accent = d.string(forKey: Key.accent).flatMap(Accent.init(rawValue:)) ?? .magenta
        scheme = d.string(forKey: Key.scheme).flatMap(Scheme.init(rawValue:)) ?? .system
        titleStyle = d.string(forKey: Key.titleStyle).flatMap(TitleStyle.init(rawValue:)) ?? .comic
        coverSize = d.string(forKey: Key.coverSize).flatMap(CoverSize.init(rawValue:)) ?? .medium
        progressText = d.string(forKey: Key.progressText).flatMap(ProgressText.init(rawValue:)) ?? .left
        var order = (d.stringArray(forKey: Key.homeOrder) ?? []).compactMap(HomeSection.init(rawValue:))
        // Si se agregan partes nuevas en otra versión, van al final.
        for section in HomeSection.allCases where !order.contains(section) { order.append(section) }
        homeOrder = order
        homeHidden = Set((d.stringArray(forKey: Key.homeHidden) ?? []).compactMap(HomeSection.init(rawValue:)))
    }

    func setAccent(_ value: Accent) {
        accent = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.accent)
    }

    func setScheme(_ value: Scheme) {
        scheme = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.scheme)
    }

    func setTitleStyle(_ value: TitleStyle) {
        titleStyle = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.titleStyle)
    }

    func setProgressText(_ value: ProgressText) {
        progressText = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.progressText)
    }

    func setCoverSize(_ value: CoverSize) {
        coverSize = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.coverSize)
    }

    func isVisible(_ section: HomeSection) -> Bool { !homeHidden.contains(section) }

    /// Las partes de Inicio que se ven, en orden.
    var visibleHomeSections: [HomeSection] { homeOrder.filter { !homeHidden.contains($0) } }

    func setVisible(_ section: HomeSection, _ visible: Bool) {
        if visible { homeHidden.remove(section) } else { homeHidden.insert(section) }
        saveHome()
    }

    func moveHome(from source: IndexSet, to destination: Int) {
        homeOrder.move(fromOffsets: source, toOffset: destination)
        saveHome()
    }

    /// Todo como venía de fábrica.
    func reset() {
        setAccent(.magenta)
        setScheme(.system)
        setTitleStyle(.comic)
        setCoverSize(.medium)
        setProgressText(.left)
        homeOrder = HomeSection.allCases
        homeHidden = []
        saveHome()
    }

    private func saveHome() {
        UserDefaults.standard.set(homeOrder.map(\.rawValue), forKey: Key.homeOrder)
        UserDefaults.standard.set(homeHidden.map(\.rawValue), forKey: Key.homeHidden)
    }
}

extension LocalComic {
    /// El avance como lo elegiste en Personalizar: "Quedan 17 páginas", "Página 5 de 22" o "23 % leído".
    @MainActor
    var progressText: String {
        if isFinished { return "Leído ✓" }
        let current = (lastPage ?? 0) + 1
        let total = max(pageCount, 1)
        switch AppearanceSettings.shared.progressText {
        case .left:
            let left = max(total - current, 0)
            switch left {
            case 0: return "Última página"
            case 1: return "Queda 1 página"
            default: return "Quedan \(left) páginas"
            }
        case .page:
            return "Página \(min(current, total)) de \(total)"
        case .percent:
            return "\(min(100, current * 100 / total)) % leído"
        }
    }

    /// Avance de 0 a 1 (para la barrita).
    var progressFraction: Double {
        isFinished ? 1 : Double((lastPage ?? 0) + 1) / Double(max(pageCount, 1))
    }
}

// MARK: - Pantalla "Personalizar"

struct AppearanceScreen: View {
    private var settings: AppearanceSettings { AppearanceSettings.shared }
    @State private var askReset = false

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 14) {
                    ForEach(AppearanceSettings.Accent.allCases) { accent in
                        Button { settings.setAccent(accent) } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(accent.color).frame(width: 40, height: 40)
                                    if settings.accent == accent {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.heavy))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().stroke(Theme.ink.opacity(settings.accent == accent ? 0.9 : 0), lineWidth: 2).padding(-4))
                                Text(accent.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(accent.name)
                        .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Color principal")
            } footer: {
                Text("Botones, pestañas y detalles de toda la app.")
            }

            Section("Modo") {
                Picker("Modo", selection: Binding(get: { settings.scheme }, set: { settings.setScheme($0) })) {
                    ForEach(AppearanceSettings.Scheme.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Letra", selection: Binding(get: { settings.titleStyle }, set: { settings.setTitleStyle($0) })) {
                    ForEach(AppearanceSettings.TitleStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Cómic Unlimited")
                    .font(.system(.title2, weight: .black).width(Theme.titleWidth))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } header: {
                Text("Letra de los títulos")
            }

            Section {
                Picker("Portadas", selection: Binding(get: { settings.coverSize }, set: { settings.setCoverSize($0) })) {
                    ForEach(AppearanceSettings.CoverSize.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.chip)
                            .overlay(Image(systemName: "book.closed").foregroundStyle(Theme.ink2))
                            .frame(width: settings.coverSize.rowWidth * 0.6, height: settings.coverSize.rowWidth * 0.9)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .animation(.easeOut(duration: 0.2), value: settings.coverSize)
            } header: {
                Text("Tamaño de las portadas")
            } footer: {
                Text("En las filas de Inicio, en \"Ver todo\" y en las grillas de la Biblioteca.")
            }

            Section {
                Picker("Avance", selection: Binding(get: { settings.progressText }, set: { settings.setProgressText($0) })) {
                    ForEach(AppearanceSettings.ProgressText.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.progressText.example)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text("Avance en Seguir leyendo")
            } footer: {
                Text("Cómo se cuenta lo que te falta de cada cómic en Inicio.")
            }

            Section {
                NavigationLink {
                    HomeSectionsScreen()
                } label: {
                    LabeledContent("Filas de Inicio", value: "\(settings.visibleHomeSections.count) de \(settings.homeOrder.count)")
                }
            } header: {
                Text("Inicio")
            } footer: {
                Text("Elegí qué filas ver en Inicio y en qué orden.")
            }

            Section {
                Button("Volver a como venía", role: .destructive) { askReset = true }
            }
        }
        .tint(Theme.magenta)
        .navigationTitle("Personalizar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("¿Volver los colores, el modo, la letra, las portadas, el avance e Inicio a como venían?",
                            isPresented: $askReset, titleVisibility: .visible) {
            Button("Volver a como venía", role: .destructive) { settings.reset() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

/// Prender, apagar y ordenar las filas de Inicio.
private struct HomeSectionsScreen: View {
    private var settings: AppearanceSettings { AppearanceSettings.shared }

    var body: some View {
        List {
            Section {
                ForEach(settings.homeOrder) { section in
                    Toggle(isOn: Binding(get: { settings.isVisible(section) },
                                         set: { settings.setVisible(section, $0) })) {
                        Label(section.name, systemImage: section.icon)
                    }
                }
                .onMove { settings.moveHome(from: $0, to: $1) }
            } footer: {
                Text("Arrastrá ≡ para cambiar el orden. Las que apagues no se ven en Inicio (y no gastan consultas).")
            }
        }
        .environment(\.editMode, .constant(.active))
        .tint(Theme.magenta)
        .navigationTitle("Filas de Inicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
