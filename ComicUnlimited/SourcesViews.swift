import SwiftUI

// Pantallas de "Fuentes" (Biblioteca → Fuentes):
// la lista de tus fuentes, agregar una con su link y ver/descargar sus cómics.

private let sourcesNotice = "Agregá solo fuentes que tengan permiso para compartir esos cómics (por ejemplo, de dominio público o con licencia libre)."

// MARK: - Lista de fuentes

struct SourcesView: View {
    private var store: SourceStore { SourceStore.shared }
    @State private var showAdd = false
    @State private var toRemove: SavedSource?
    @State private var updating: String?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Fuentes")
                    .font(.system(size: 28, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text("Catálogos de cómics que agregás con el link de un JSON. Lo que descargues queda en tu Biblioteca.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                WordPressSiteCard()
                    .padding(.top, 16)

                Button {
                    showAdd = true
                } label: {
                    Label("Agregar fuente (JSON)", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .foregroundStyle(Theme.paper)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.magenta).padding(.top, 10)
                }

                if store.sources.isEmpty {
                    Text("Todavía no agregaste fuentes.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.sources) { source in
                            NavigationLink(value: LibraryRoute.source(source.url)) {
                                SourceCard(manifest: source.manifest, link: source.url,
                                           newVersion: source.availableVersion)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if source.availableVersion != nil {
                                    Button {
                                        Task { await update(source.url) }
                                    } label: {
                                        Label("Actualizar fuente", systemImage: "arrow.down.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    toRemove = source
                                } label: {
                                    Label("Quitar fuente", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    Text("Mantené apretada una fuente para actualizarla o quitarla.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 10)
                }

                Text(sourcesNotice)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 24)
                Text("Cómo armar una fuente: archivo FUENTES.md en el repositorio de la app.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle("Fuentes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await store.checkForUpdates() }
        .refreshable { await store.checkForUpdates() }
        .sheet(isPresented: $showAdd) { AddSourceView() }
        .confirmationDialog("¿Quitar esta fuente?",
                            isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Quitar", role: .destructive) {
                if let source = toRemove { store.remove(source.url) }
                toRemove = nil
            }
            Button("Cancelar", role: .cancel) { toRemove = nil }
        } message: {
            Text("Los cómics que ya descargaste siguen en tu Biblioteca.")
        }
    }

    private func update(_ url: String) async {
        do {
            try await store.update(url)
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Ficha de una fuente: nombre, versión, autor, licencia y cantidad de cómics.
struct SourceCard: View {
    let manifest: SourceManifest
    let link: String
    var newVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(manifest.name)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if let version = manifest.version {
                    Text("v\(version)").font(.caption.weight(.bold)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                if let newVersion {
                    Text("Nueva: v\(newVersion)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Theme.magenta, in: Capsule())
                }
            }
            if let description = manifest.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
            }
            Text(CVText.join([
                manifest.author,
                manifest.license.map { "Licencia: \($0)" },
                "\(manifest.comics.count) \(manifest.comics.count == 1 ? "cómic" : "cómics")",
            ]))
            .font(.caption)
            .foregroundStyle(Theme.ink2)
            Text(link)
                .font(.caption2)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

// MARK: - Agregar una fuente

private struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var checking = false
    @State private var preview: (manifest: SourceManifest, raw: Data)?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pegá el link del JSON de la fuente. Antes de agregarla vas a ver de qué se trata.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)

                    TextField("https://…/fuente.json", text: $link)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        .onChange(of: link) { _, _ in preview = nil; errorText = nil }

                    Button {
                        Task { await check() }
                    } label: {
                        Text(checking ? "Revisando…" : "Revisar fuente")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(Theme.ink)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(checking || link.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let errorText {
                        Text(errorText).font(.subheadline).foregroundStyle(Theme.magenta)
                    }

                    if let preview {
                        SourceCard(manifest: preview.manifest, link: link)
                        if let repo = preview.manifest.repository, let url = URL(string: repo) {
                            Link("Ver repositorio", destination: url).font(.footnote).foregroundStyle(Theme.magenta)
                        }
                        if let home = preview.manifest.homepage, let url = URL(string: home) {
                            Link("Ver página de la fuente", destination: url).font(.footnote).foregroundStyle(Theme.magenta)
                        }
                        Text(sourcesNotice)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink2)
                        Button {
                            SourceStore.shared.add(link: link, manifest: preview.manifest, raw: preview.raw)
                            dismiss()
                        } label: {
                            Text("Agregar fuente")
                                .font(.system(size: 16, weight: .heavy))
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .foregroundStyle(Theme.paper)
                                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(Theme.paper)
            .navigationTitle("Agregar fuente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func check() async {
        checking = true
        errorText = nil
        preview = nil
        do {
            preview = try await SourceStore.shared.fetch(link)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        checking = false
    }
}

// MARK: - Cómics de una fuente

struct SourceDetailView: View {
    let url: String
    private var store: SourceStore { SourceStore.shared }
    @State private var query = ""

    var body: some View {
        if let source = store.source(url) {
            let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespaces)
            let comics = source.manifest.comics.filter { comic in
                q.isEmpty || "\(comic.title) \(comic.series ?? "") \(comic.publisher ?? "") \(comic.year ?? "")"
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(q)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SourceCard(manifest: source.manifest, link: source.url, newVersion: source.availableVersion)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink2)
                        TextField("Buscar en esta fuente", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 16)

                    if comics.isEmpty {
                        Text(source.manifest.comics.isEmpty ? "Esta fuente no tiene cómics." : "No hay cómics que coincidan.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 16)
                    } else {
                        ForEach(comics) { comic in
                            SourceComicRow(comic: comic)
                        }
                    }

                    Text("Datos de la fuente \"\(source.manifest.name)\". Las portadas se cargan de internet y pertenecen a sus dueños.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(source.manifest.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        } else {
            Text("Esta fuente ya no está.").foregroundStyle(Theme.ink2)
        }
    }
}

/// Un cómic de una fuente, con su botón para descargarlo a la Biblioteca.
struct SourceComicRow: View {
    let comic: SourceComic
    private var store: SourceStore { SourceStore.shared }

    var body: some View {
        let key = comic.download
        HStack(alignment: .center, spacing: 12) {
            RemoteCover(url: comic.coverURL).frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(comic.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(CVText.join([comic.publisher, comic.year, comic.fileExtension.uppercased(),
                                  comic.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]))
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                if let failure = store.failures[key] {
                    Text(failure).font(.caption2).foregroundStyle(Theme.magenta).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Group {
                if let value = store.progress[key] {
                    ZStack {
                        Circle().stroke(Theme.line, lineWidth: 4)
                        Circle().trim(from: 0, to: max(value, 0.02))
                            .stroke(Theme.magenta, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(value * 100))%").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    .frame(width: 38, height: 38)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Descargando, \(Int(value * 100)) por ciento")
                } else if store.downloaded.contains(key) {
                    Label("En tu Biblioteca", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(Theme.magenta)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Ya está en tu Biblioteca")
                } else {
                    Button {
                        Task { await store.download(comic) }
                    } label: {
                        Image(systemName: store.failures[key] == nil ? "arrow.down.circle" : "arrow.clockwise.circle")
                            .font(.title2)
                            .foregroundStyle(Theme.magenta)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.failures[key] == nil ? "Descargar a la Biblioteca" : "Reintentar")
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
