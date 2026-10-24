import SwiftUI
import Observation

// Perfiles de lectura: cada serie puede recordar su dirección (izq → der, der → izq, vertical)
// y su tamaño de página. Si una serie no tiene perfil, se usan las opciones de siempre del lector.
// Además, el manga (editoriales como Viz o Kodansha) se abre de derecha a izquierda solo.
// Todo queda guardado solo en el iPhone.

extension ReaderDirection: Codable {}
extension ReaderFit: Codable {}

@MainActor
@Observable
final class ReadingProfiles {
    static let shared = ReadingProfiles()
    private static let storeKey = "reader.profiles"
    /// Prendido de entrada: el manga se abre de derecha a izquierda.
    nonisolated static let autoMangaKey = "reader.autoManga"

    struct Profile: Codable, Hashable {
        /// Nombre de la serie, para mostrarlo en la lista.
        var name: String
        var direction: ReaderDirection
        var fit: ReaderFit
    }

    /// Perfil de cada serie (la clave sale de `key(for:)`).
    private(set) var profiles: [String: Profile]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([String: Profile].self, from: data) {
            profiles = saved
        } else {
            profiles = [:]
        }
    }

    // MARK: Serie de cada cómic

    /// La serie de Comic Vine si tiene ficha; si no, el nombre de la serie sacado del archivo.
    static func key(for comic: LocalComic) -> String? {
        if let id = comic.cvSeriesID { return "cv:\(id)" }
        let name = FileNameInfo(comic.title).series.trimmingCharacters(in: .whitespaces).lowercased()
        return name.isEmpty ? nil : "nombre:\(name)"
    }

    static func seriesName(for comic: LocalComic) -> String {
        if let name = comic.cvSeriesName, !name.isEmpty { return name }
        let name = FileNameInfo(comic.title).series.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? comic.displayTitle : name
    }

    func profile(for comic: LocalComic) -> Profile? {
        Self.key(for: comic).flatMap { profiles[$0] }
    }

    func save(_ profile: Profile, for comic: LocalComic) {
        guard let key = Self.key(for: comic) else { return }
        profiles[key] = profile
        persist()
    }

    func remove(for comic: LocalComic) {
        guard let key = Self.key(for: comic) else { return }
        remove(key: key)
    }

    func remove(key: String) {
        profiles[key] = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: Manga

    /// Editoriales de manga (por cómo empieza su nombre en Comic Vine).
    private static let mangaPublishers = ["viz", "kodansha", "yen press", "seven seas", "shueisha", "shogakukan",
                                          "square enix", "tokyopop", "vertical", "kadokawa", "hakusensha",
                                          "akita shoten", "futabasha", "j-novel", "denpa", "one peace",
                                          "ghost ship", "airship", "udon", "dark horse manga", "ize press"]

    static func isManga(_ comic: LocalComic) -> Bool {
        guard let publisher = comic.cvPublisher?.lowercased(), !publisher.isEmpty else { return false }
        return mangaPublishers.contains { publisher.hasPrefix($0) }
    }

    /// Dirección que va a usar el lector para este cómic: la de su serie, la del manga o la de siempre.
    func direction(for comic: LocalComic, global: ReaderDirection, autoManga: Bool) -> ReaderDirection {
        if let profile = profile(for: comic) { return profile.direction }
        if autoManga && global == .leftToRight && Self.isManga(comic) { return .rightToLeft }
        return global
    }

    func fit(for comic: LocalComic, global: ReaderFit) -> ReaderFit {
        profile(for: comic)?.fit ?? global
    }
}

// MARK: - Lista de perfiles (Perfil → Configuración)

struct ReadingProfilesView: View {
    private var store: ReadingProfiles { ReadingProfiles.shared }
    @AppStorage(ReadingProfiles.autoMangaKey) private var autoManga = true

    var body: some View {
        let profiles = store.profiles
        let keys = profiles.keys.sorted {
            (profiles[$0]?.name ?? "").localizedStandardCompare(profiles[$1]?.name ?? "") == .orderedAscending
        }
        List {
            Section {
                Toggle("Manga de derecha a izquierda", isOn: $autoManga)
                    .tint(Theme.magenta)
            } footer: {
                Text("Si la editorial es de manga (Viz, Kodansha, Yen Press…), el lector se abre de derecha a izquierda aunque no le hayas puesto ajustes a esa serie.")
            }

            Section {
                if keys.isEmpty {
                    Text("Todavía no hay series con ajustes propios. En el lector, tocá ⚙︎ y prendé \"Recordar para esta serie\".")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(keys, id: \.self) { key in
                    let profile = profiles[key] ?? .init(name: "", direction: .leftToRight, fit: .page)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.subheadline.weight(.bold))
                        Text("\(profile.direction.label) · \(profile.direction == .vertical ? "Al ancho" : profile.fit.label)")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.remove(key: key) } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Series con ajustes propios")
            } footer: {
                if !keys.isEmpty { Text("Deslizá a la izquierda para borrar uno: esa serie vuelve a usar las opciones de siempre.") }
            }
        }
        .navigationTitle("Ajustes por serie")
        .navigationBarTitleDisplayMode(.inline)
    }
}
