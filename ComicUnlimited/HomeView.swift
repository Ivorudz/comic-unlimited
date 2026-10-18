import SwiftUI

// Pestaña Inicio: buscador, "Seguir leyendo", cómic destacado y catálogo.
struct HomeView: View {
    @Environment(ReadingStore.self) private var store
    /// Se usa para abrir el lector desde cualquier pantalla.
    let onRead: (Comic) -> Void

    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case editorial = "Editoriales"
        case indie = "Independientes"
        var id: String { rawValue }
    }

    private var catalog: [Comic] {
        let q = normalize(query)
        return Catalog.comics
            .filter { comic in
                switch filter {
                case .all: return true
                case .editorial: return comic.source == .editorial
                case .indie: return comic.source == .indie
                }
            }
            .filter { q.isEmpty || normalize("\($0.title) \($0.author) \($0.genre)").contains(q) }
            .sorted { $0.rating > $1.rating }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    searchField
                    continueReading
                    featured
                    catalogSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            .navigationDestination(for: Comic.self) { comic in
                DetailView(comic: comic, onRead: onRead)
            }
            .navigationTitle("Inicio")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Partes de la pantalla

    private var header: some View {
        Text("Cómic\nUnlimited")
            .font(.system(size: 44, weight: .black).width(.expanded))
            .lineSpacing(-6)
            .foregroundStyle(Theme.ink)
            .misprint()
            .padding(.top, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
            TextField("Buscar por título, autor o género", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 18)
    }

    @ViewBuilder
    private var continueReading: some View {
        let reading = store.inProgress(from: Catalog.comics)
        if !reading.isEmpty {
            SectionTitle("Seguir leyendo")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(reading) { comic in
                        Button { onRead(comic) } label: {
                            ContinueCard(comic: comic, page: store.savedPage(for: comic))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
        }
    }

    private var featured: some View {
        let comic = Catalog.comics[0]
        return NavigationLink(value: comic) {
            HStack(alignment: .center, spacing: 16) {
                CoverArt(comic: comic)
                    .frame(width: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nuevo número")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                    Text(comic.fullTitle)
                        .font(.system(size: 24, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                    Text(comic.synopsis)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.leading)
                    Text("Ver cómic")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.bottom, 2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.magenta).frame(height: 2)
                        }
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Catálogo")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { option in
                        Button { filter = option } label: {
                            Text(option.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(filter == option ? Theme.paper : Theme.ink)
                                .background(filter == option ? Theme.ink : Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.horizontal, -18)
            .padding(.bottom, 14)

            let list = catalog
            if list.isEmpty {
                Text("No hay cómics que coincidan con la búsqueda.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                          alignment: .leading, spacing: 18) {
                    ForEach(list) { comic in
                        NavigationLink(value: comic) {
                            CatalogCard(comic: comic)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Pasa a minúsculas y saca los acentos, para que "comic" encuentre "cómic".
    private func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Piezas reutilizables

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .padding(.top, 28)
            .padding(.bottom, 12)
    }
}

struct SourceBadge: View {
    let source: Comic.Source

    var body: some View {
        Text(source.label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(source == .editorial ? Color(hex: 0x00A3D9) : Color(hex: 0xD1006C),
                        in: RoundedRectangle(cornerRadius: 4))
    }
}

struct CatalogCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CoverArt(comic: comic)
                .overlay(alignment: .topLeading) {
                    SourceBadge(source: comic.source).padding(6)
                }
            Text(comic.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            Text(comic.author)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
            (Text("★ ").foregroundStyle(Theme.star) + Text(String(format: "%.1f", comic.rating)))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
        }
    }
}

struct ContinueCard: View {
    let comic: Comic
    let page: Int

    var body: some View {
        let progress = Double(page + 1) / Double(comic.pageCount)
        HStack(spacing: 12) {
            CoverArt(comic: comic).frame(width: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(comic.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text("Página \(page + 1) de \(comic.pageCount)")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                ProgressBar(value: progress).padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 290)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chip)
                Capsule().fill(Theme.magenta).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
