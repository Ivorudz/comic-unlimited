import SwiftUI

// Pestaña Perfil: tus listas de cómics reales (Leyendo, Quiero leer, Leídos) con portadas y puntajes.
// Las listas se arman desde la ficha de cada cómic real (botones y estrellas).

struct ProfileView: View {
    @State private var selected: RealLibrary.Status = .reading
    @AppStorage(AppSettings.showMissingKey) private var showMissing = true
    @AppStorage(AppSettings.autoLinkKey) private var autoLink = true
    @AppStorage(TranslationSettings.enabledKey) private var translate = true
    @AppStorage(TranslationSettings.languageKey) private var language = "es"
    private var library: RealLibrary { RealLibrary.shared }

    private static let tabs: [(status: RealLibrary.Status, label: String)] = [
        (.reading, "Leyendo"),
        (.wantToRead, "Quiero leer"),
        (.read, "Leídos"),
    ]

    var body: some View {
        let all = Array(library.entries.values)
        let list = all.filter { $0.status == selected }.sorted { $0.updated > $1.updated }
        let rated = all.compactMap(\.rating)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Perfil")
                        .font(.system(size: 32, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                        .misprint(0.7)
                        .padding(.top, 20)

                    // Números rápidos.
                    HStack(spacing: 10) {
                        StatTile(value: "\(all.filter { $0.status == .read }.count)", label: "Leídos")
                        StatTile(value: "\(all.filter { $0.status == .reading }.count)", label: "Leyendo")
                        StatTile(value: "\(all.filter { $0.status == .wantToRead }.count)", label: "Quiero leer")
                        StatTile(value: rated.isEmpty ? "–" : String(format: "%.1f", Double(rated.reduce(0, +)) / Double(rated.count)),
                                 label: "Puntaje que das")
                    }
                    .padding(.top, 18)

                    SectionTitle("Tus listas")
                    Picker("Lista", selection: $selected) {
                        ForEach(Self.tabs, id: \.status) { tab in
                            Text(tab.label).tag(tab.status)
                        }
                    }
                    .pickerStyle(.segmented)

                    if list.isEmpty {
                        Text(emptyText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(list, id: \.key) { entry in
                            NavigationLink(value: entry.isSeries
                                           ? CVRoute.series(id: entry.id, name: entry.title)
                                           : CVRoute.issue(id: entry.id, title: entry.title)) {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionTitle("Configuración")
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $autoLink) {
                            Text("Buscar la ficha de Comic Vine al importar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.magenta)
                        Text(autoLink
                             ? "Cada archivo que importás o descargás se une solo con su ficha (después la podés revisar en Biblioteca → Revisar fichas)."
                             : "Los archivos se agregan sin ficha. La elegís vos: mantené apretado el cómic → Elegir ficha, o desde la ficha de Comic Vine → ¿Ya lo tenés?")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)

                        Divider().padding(.vertical, 8)

                        Toggle(isOn: $showMissing) {
                            Text("Mostrar en gris los números que no tengo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.magenta)
                        Text("En las carpetas de series y arcos de la Biblioteca, los números que te faltan aparecen en gris en su lugar.")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)

                        Divider().padding(.vertical, 8)

                        Toggle(isOn: $translate) {
                            Text("Traducir textos de Comic Vine")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.magenta)
                        HStack {
                            Text("Idioma")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(translate ? Theme.ink : Theme.ink2)
                            Spacer()
                            Picker("Idioma", selection: $language) {
                                ForEach(TranslationSettings.languages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .tint(Theme.magenta)
                            .disabled(!translate)
                        }
                        Text("Traduce \"De qué se trata\" de cómics, series y arcos con el traductor de Apple (viene en el iPhone). La primera vez puede pedir descargar el idioma.")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))

                    Text("Las listas y los puntajes quedan guardados solo en este iPhone. Datos y portadas: Comic Vine. Las portadas pertenecen a sus editoriales.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .appDestinations()
            .navigationTitle("Perfil")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var emptyText: String {
        switch selected {
        case .reading:
            return "No tenés cómics en Leyendo. Abrí la ficha de un cómic o de una serie real (desde Inicio) y tocá Leyendo."
        case .wantToRead:
            return "Tu lista de pendientes está vacía. En la ficha de un cómic real, tocá Quiero leer."
        case .read:
            return "Cuando marques un cómic como Leído (o le pongas estrellas), va a aparecer acá."
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .black).width(.expanded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

private struct EntryRow: View {
    let entry: RealLibrary.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteCover(url: entry.coverURL.flatMap { URL(string: $0) })
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                if entry.isSeries {
                    Text("Serie")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(entry.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let thumbs = entry.thumbs {
                    Text(thumbs < 0 ? "👎" : thumbs == 1 ? "👍" : "👍👍")
                        .font(.footnote)
                } else if let rating = entry.rating {
                    (Text(String(repeating: "★", count: rating)).foregroundStyle(Theme.star)
                        + Text(String(repeating: "★", count: 5 - rating)).foregroundStyle(Theme.line))
                        .font(.footnote)
                } else if let writer = entry.writers.first {
                    Text(entry.isSeries ? "De \(writer.name)" : "Guion: \(writer.name)")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}
