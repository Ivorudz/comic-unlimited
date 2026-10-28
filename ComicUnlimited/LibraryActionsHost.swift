import SwiftUI

// Ventanas del menú de cada cómic de tu Biblioteca (elegir ficha, cambiar nombre, borrar).
// Van en la raíz de la app para que funcionen desde cualquier pestaña
// (por ejemplo, un cómic tuyo que aparece en un arco abierto desde Inicio).

struct LibraryActionsHost: ViewModifier {
    @Bindable var actions: LibraryActions
    @State private var renameText = ""
    private var library: LocalLibrary { LocalLibrary.shared }

    func body(content: Content) -> some View {
        content
        .environment(actions)
        .sheet(item: $actions.linking) { comic in
            LinkPickerView(comic: comic)
        }
        .sheet(item: $actions.editingContents) { comic in
            TPBContentsEditor(comicID: comic.id)
        }
        .sheet(item: $actions.addingToList) { item in
            AddToListSheet(item: item)
        }
        .alert("Cambiar nombre",
               isPresented: Binding(get: { actions.renaming != nil }, set: { if !$0 { actions.renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                if let comic = actions.renaming { library.rename(comic.id, to: renameText) }
                actions.renaming = nil
            }
            if actions.renaming?.customTitle != nil {
                Button("Volver al nombre original") {
                    if let comic = actions.renaming { library.rename(comic.id, to: nil) }
                    actions.renaming = nil
                }
            }
            Button("Cancelar", role: .cancel) { actions.renaming = nil }
        } message: {
            Text("Es solo el nombre que se ve en la app. El archivo no cambia.")
        }
        .onChange(of: actions.renaming) { _, comic in
            renameText = comic?.displayTitle ?? ""
        }
        .confirmationDialog("¿Borrar este cómic de la Biblioteca?",
                            isPresented: Binding(get: { actions.toDelete != nil },
                                                 set: { if !$0 { actions.toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let comic = actions.toDelete { library.delete(comic) }
                actions.toDelete = nil
            }
            Button("Cancelar", role: .cancel) { actions.toDelete = nil }
        } message: {
            Text("Se borra la copia guardada en la app. El archivo original sigue en la app Archivos.")
        }
    }
}
