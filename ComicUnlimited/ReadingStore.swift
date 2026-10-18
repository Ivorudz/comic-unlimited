import Foundation
import Observation

// Guarda en el celular en qué página quedaste de cada cómic.
// Usa UserDefaults: una memoria chiquita que cada app tiene en el iPhone
// y que no se borra al cerrar la app.
@Observable
final class ReadingStore {
    private static let pagesKey = "reading.pages"
    private static let finishedKey = "reading.finished"

    /// Página guardada de cada cómic (la primera página es la 0).
    private(set) var pages: [String: Int]
    /// Cómics que leíste hasta el final.
    private(set) var finished: Set<String>

    init() {
        pages = (UserDefaults.standard.dictionary(forKey: Self.pagesKey) as? [String: Int]) ?? [:]
        finished = Set(UserDefaults.standard.stringArray(forKey: Self.finishedKey) ?? [])
    }

    func savedPage(for comic: Comic) -> Int {
        min(pages[comic.id] ?? 0, comic.pageCount - 1)
    }

    func hasStarted(_ comic: Comic) -> Bool {
        pages[comic.id] != nil
    }

    func isFinished(_ comic: Comic) -> Bool {
        finished.contains(comic.id)
    }

    /// Cómics empezados y sin terminar, para la fila "Seguir leyendo".
    func inProgress(from comics: [Comic]) -> [Comic] {
        comics.filter { hasStarted($0) && !isFinished($0) }
    }

    /// Se llama al abrir el lector. Devuelve la página donde hay que arrancar.
    func open(_ comic: Comic) -> Int {
        if isFinished(comic) {
            // Si ya lo terminaste, empieza de nuevo desde la primera página.
            finished.remove(comic.id)
            setPage(0, for: comic)
            persist()
            return 0
        }
        let page = savedPage(for: comic)
        setPage(page, for: comic)
        return page
    }

    func setPage(_ page: Int, for comic: Comic) {
        pages[comic.id] = max(0, min(page, comic.pageCount - 1))
        persist()
    }

    func markFinished(_ comic: Comic) {
        finished.insert(comic.id)
        pages[comic.id] = comic.pageCount - 1
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(pages, forKey: Self.pagesKey)
        UserDefaults.standard.set(Array(finished).sorted(), forKey: Self.finishedKey)
    }
}
