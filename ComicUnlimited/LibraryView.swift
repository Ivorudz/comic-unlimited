import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Pestaña Biblioteca: los cómics que tenés en archivos (.cbz, .zip, .cbr o PDF).
// Tocar uno lo abre en el lector. Mantenerlo apretado muestra más opciones.

struct LibraryView: View {
    /// Abre un cómic en el lector.
    let onRead: (LocalComic) -> Void
    private var library: LocalLibrary { LocalLibrary.shared }
    @State private var linking: LocalComic?
    @State private var showImporter = false
    @State private var problems: [String] = []
    @State private var showProblems = false
    @State private var toDelete: LocalComic?

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Biblioteca")
                    .font(.system(size: 32, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.7)
                    .padding(.top, 20)

                Text("Tus cómics en archivo. Se guardan solo en este iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                Button {
                    showImporter = true
                } label: {
                    Label("Importar cómic (.cbz, .zip, .cbr o PDF)", systemImage: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .foregroundStyle(Theme.ink2)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .buttonStyle(.plain)
                .disabled(library.importing)
                .padding(.top, 16)

                if library.importing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importando… los archivos grandes (y los .cbr, que se convierten a .cbz) pueden tardar un poco.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 14)
                }

                if library.items.isEmpty && !library.importing {
                    Text("Todavía no importaste cómics. Tocá el botón de arriba y elegí un archivo desde la app Archivos (por ejemplo, de iCloud Drive o Descargas).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 18)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                              alignment: .leading, spacing: 18) {
                        ForEach(library.items) { comic in
                            Button { onRead(comic) } label: {
                                LocalComicCard(comic: comic, matching: library.matching.contains(comic.id))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { onRead(comic) } label: {
                                    Label("Leer", systemImage: "book")
                                }
                                if let issueID = comic.cvIssueID {
                                    NavigationLink(value: CVRoute.issue(id: issueID, title: comic.displayTitle)) {
                                        Label("Ver ficha en Comic Vine", systemImage: "info.circle")
                                    }
                                } else {
                                    Button {
                                        Task {
                                            let found = await library.autoLink(comic.id)
                                            if !found { linking = comic }
                                        }
                                    } label: {
                                        Label("Buscar su ficha en Comic Vine", systemImage: "sparkle.magnifyingglass")
                                    }
                                }
                                Button { linking = comic } label: {
                                    Label("Elegir ficha de Comic Vine", systemImage: "list.bullet.rectangle")
                                }
                                Button(role: .destructive) {
                                    toDelete = comic
                                } label: {
                                    Label("Borrar de la Biblioteca", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.top, 20)

                    Text("Tocá un cómic para leerlo. Mantenelo apretado para ver su ficha, elegir otra ficha de Comic Vine o borrarlo.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationDestination(for: CVRoute.self) { route in
            CVDestination(route: route)
        }
        .navigationTitle("Biblioteca")
        .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $linking) { comic in
            LinkPickerView(comic: comic)
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                showImporter = false
                guard !urls.isEmpty else { return }
                Task {
                    problems = await library.importFiles(urls)
                    showProblems = !problems.isEmpty
                }
            }
            .ignoresSafeArea()
        }
        .alert("Algunos archivos no se pudieron importar", isPresented: $showProblems) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problems.joined(separator: "\n\n"))
        }
        .confirmationDialog("¿Borrar este cómic de la Biblioteca?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let comic = toDelete { library.delete(comic) }
                toDelete = nil
            }
            Button("Cancelar", role: .cancel) { toDelete = nil }
        } message: {
            Text("Se borra la copia guardada en la app. El archivo original sigue en la app Archivos.")
        }
    }
}

/// Portada (primera página) y nombre de un cómic importado.
private struct LocalComicCard: View {
    let comic: LocalComic
    let matching: Bool
    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                Theme.chip
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.richtext").foregroundStyle(Theme.ink2)
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))

            Text(comic.displayTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            if let name = comic.cvIssueName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Group {
                if comic.isFinished {
                    Text("Leído ✓")
                } else if let page = comic.lastPage {
                    Text("Página \(page + 1) de \(comic.pageCount)")
                } else {
                    Text("\(comic.pageCount) \(comic.pageCount == 1 ? "página" : "páginas")")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.ink2)
            if matching {
                Text("Buscando ficha…").font(.caption2).foregroundStyle(Theme.magenta)
            } else if comic.cvIssueID != nil {
                Label("Comic Vine", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.magenta)
            }
        }
        .task(id: comic.id) {
            cover = UIImage(contentsOfFile: LocalLibrary.shared.coverURL(comic).path)
        }
    }
}

/// Selector de archivos del iPhone. Pide una COPIA de cada archivo elegido:
/// así funciona también dentro de LiveContainer, donde leer el original puede fallar.
private struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.pdf, .zip, .data]
        for ext in ["cbz", "cbr"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}
