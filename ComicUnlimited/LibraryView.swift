import SwiftUI
import UniformTypeIdentifiers

// Pestaña Biblioteca: los cómics que tenés en archivos (.cbz, .zip o PDF).
// Por ahora se importan y se ven; leerlos llega en la próxima versión.

struct LibraryView: View {
    private var library: LocalLibrary { LocalLibrary.shared }
    @State private var showImporter = false
    @State private var problems: [String] = []
    @State private var showProblems = false
    @State private var toDelete: LocalComic?

    var body: some View {
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
                    Label("Importar cómic (.cbz, .zip o PDF)", systemImage: "square.and.arrow.down")
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
                        Text("Importando… los archivos grandes pueden tardar un poco.")
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
                            LocalComicCard(comic: comic)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        toDelete = comic
                                    } label: {
                                        Label("Borrar de la Biblioteca", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.top, 20)

                    Text("Para borrar un cómic, mantenelo apretado. Leer tus archivos llega en la próxima versión.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf, .zip, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    problems = await library.importFiles(urls)
                    showProblems = !problems.isEmpty
                }
            case .failure(let error):
                problems = [error.localizedDescription]
                showProblems = true
            }
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

            Text(comic.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.top, 6)
            Text("\(comic.pageCount) \(comic.pageCount == 1 ? "página" : "páginas")")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
        }
        .task(id: comic.id) {
            cover = UIImage(contentsOfFile: LocalLibrary.shared.coverURL(comic).path)
        }
    }
}
