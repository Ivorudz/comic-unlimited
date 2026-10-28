import Foundation

// "Siguiente número": la app recuerda desde dónde abriste cada cómic (un arco o una serie)
// y, al terminarlo, te ofrece el que sigue ahí entre los que tenés.

/// Un arco o una serie desde donde abriste un cómic.
struct ReadContext: Codable, Hashable {
    enum Kind: String, Codable { case series, arc, list }
    let kind: Kind
    let id: Int
    let name: String

    /// Texto chiquito para "Seguir leyendo".
    var label: String {
        switch kind {
        case .arc: return "Arco: \(name)"
        case .series: return "Serie: \(name)"
        case .list: return "Lista: \(name)"
        }
    }
}

/// Lo que estás mirando ahora (lo marcan las carpetas de arco y de serie al aparecer;
/// las pantallas principales lo borran).
@MainActor
enum BrowsingContext {
    static var current: ReadContext?
}

extension LocalLibrary {
    /// ¿Este cómic es parte de ese arco o serie?
    func belongs(_ comic: LocalComic, to context: ReadContext) -> Bool {
        switch context.kind {
        case .series:
            return comic.cvSeriesID == context.id
        case .arc:
            if comic.cvArcs?.contains(where: { $0.id == context.id }) == true { return true }
            let listed = Set(ReadingOrderStore.shared.orders[context.id]?.items.compactMap(\.cvID) ?? [])
            if let cv = comic.cvIssueID, listed.contains(cv) { return true }
            return comic.contents?.contains { listed.contains($0.cvID) } == true
        case .list:
            return CustomListStore.shared.list(context.id)?.items.contains { isIn(comic, $0) } == true
        }
    }

    /// El cómic que sigue (entre los tuyos) en el arco o la serie desde donde abriste este.
    func next(after comic: LocalComic) -> (comic: LocalComic, label: String)? {
        let context = comic.lastContext
        if let context, context.kind == .arc, let found = nextInArc(after: comic, arc: context) {
            return (found, "Siguiente en \(context.name)")
        }
        if let context, context.kind == .list, let found = nextInList(after: comic, listID: context.id) {
            return (found, "Siguiente en \(context.name)")
        }
        guard let series = comic.cvSeriesID else { return nil }
        let list = items.filter { $0.cvSeriesID == series && $0.id != comic.id }
            .filter { $0.numberForSorting > comic.numberForSorting }
            .sorted(by: LibraryGrouping.byNumber)
        guard let found = list.first else { return nil }
        return (found, "Siguiente en \(comic.cvSeriesName ?? "la serie")")
    }

    /// El siguiente de la lista que tengas (suelto, en un TPB o archivo sin ficha).
    private func nextInList(after comic: LocalComic, listID: Int) -> LocalComic? {
        guard let list = CustomListStore.shared.list(listID),
              let position = list.items.lastIndex(where: { isIn(comic, $0) }) else { return nil }
        for item in list.items[(position + 1)...] {
            if let next = owned(item), next.id != comic.id { return next }
        }
        return nil
    }

    private func nextInArc(after comic: LocalComic, arc: ReadContext) -> LocalComic? {
        let store = ReadingOrderStore.shared
        if let order = store.orders[arc.id], !store.byDate.contains(arc.id) {
            // Con orden de lectura: el siguiente número de la lista que tengas (suelto o en un TPB).
            let direct = Dictionary(items.compactMap { c in c.cvIssueID.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })
            let collected = collectedIssues
            let ids = order.items.compactMap(\.cvID)
            let mine = Set([comic.cvIssueID].compactMap { $0 } + (comic.contents ?? []).map(\.cvID))
            guard let position = ids.lastIndex(where: { mine.contains($0) }) else { return nil }
            for id in ids[(position + 1)...] {
                if let next = direct[id] ?? collected[id], next.id != comic.id { return next }
            }
            return nil
        }
        // Por fecha: el siguiente de tus cómics de ese arco.
        let list = items.filter { $0.cvArcs?.contains(where: { $0.id == arc.id }) == true }
            .sorted(by: LibraryGrouping.byDate)
        guard let index = list.firstIndex(where: { $0.id == comic.id }), index + 1 < list.count else { return nil }
        return list[index + 1]
    }
}
