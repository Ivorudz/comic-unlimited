import SwiftUI

// Revisar las fichas de Comic Vine que eligió la app sola, y unir un archivo desde una ficha.
// - "Revisar fichas": tu portada al lado de la de Comic Vine, con "Es correcta" o "Cambiar".
// - En la ficha de un cómic que no tenés: "¿Ya lo tenés? Elegí el archivo".

/// Tarjeta en la Biblioteca: aparece solo si hay fichas para revisar.
struct ReviewLinksCard: View {
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let count = library.items.filter(\.needsReview).count
        if count > 0 {
            NavigationLink(value: LibraryRoute.reviewLinks) {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.magenta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Revisar fichas de Comic Vine").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(count == 1 ? "1 cómic con ficha elegida por la app"
                                        : "\(count) cómics con ficha elegida por la app")
                            .font(.caption).foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.ink2)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.magenta.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}

// MARK: - Revisar fichas

struct ReviewLinksView: View {
    @Environment(LibraryActions.self) private var actions: LibraryActions?
    @State private var images: [Int: URL] = [:]
    private var library: LocalLibrary { LocalLibrary.shared }

    var body: some View {
        let pending = library.items.filter(\.needsReview)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Revisar fichas")
                    .font(.system(size: 24, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text("La app eligió estas fichas de Comic Vine sola. Compará tu portada con la de Comic Vine: si alguna está mal, tocá Cambiar.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                if pending.isEmpty {
                    Text("No hay fichas para revisar. ¡Todo listo!")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 18)
                } else {
                    Button {
                        library.confirmLinks(pending.map(\.id))
                    } label: {
                        Label("Todas están bien (\(pending.count))", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .foregroundStyle(Theme.paper)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)

                    ForEach(pending) { comic in
                        ReviewLinkRow(comic: comic,
                                      image: comic.cvIssueID.flatMap { images[$0] },
                                      onConfirm: { library.confirmLinks([comic.id]) },
                                      onChange: actions == nil ? nil : { actions?.linking = comic })
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle("Revisar fichas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: pending.compactMap(\.cvIssueID)) { await loadImages(pending) }
    }

    /// Trae las portadas de Comic Vine de esas fichas (en un solo pedido cada 100).
    private func loadImages(_ pending: [LocalComic]) async {
        let missing = pending.compactMap(\.cvIssueID).filter { images[$0] == nil }
        guard !missing.isEmpty, !ComicVineKey.current.isEmpty,
              let found = try? await ComicVineKey.client.issues(ids: missing) else { return }
        for issue in found {
            if let url = issue.image?.small { images[issue.id] = url }
        }
    }
}

private struct ReviewLinkRow: View {
    let comic: LocalComic
    let image: URL?
    let onConfirm: () -> Void
    let onChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    LocalCover(comic: comic).frame(width: 74)
                    Text("Tu archivo").font(.caption2).foregroundStyle(Theme.ink2)
                }
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 44)
                VStack(spacing: 4) {
                    RemoteCover(url: image).frame(width: 74)
                    Text("Comic Vine").font(.caption2).foregroundStyle(Theme.ink2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(comic.cvTitle ?? "Ficha")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(CVText.join([comic.cvIssueName,
                                      comic.cvSeriesYear.flatMap { $0.isEmpty ? nil : "Serie de \($0)" },
                                      CVText.monthYear(comic.cvCoverDate)]))
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                    Text("Archivo: \(comic.title)")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(3)
                }
            }
            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Label("Es correcta", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                if let onChange {
                    Button(action: onChange) {
                        Label("Cambiar", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .foregroundStyle(.white)
                            .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                if let issueID = comic.cvIssueID {
                    NavigationLink(value: CVRoute.issue(id: issueID, title: comic.cvTitle ?? "Ficha")) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ink2)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Unir un archivo desde la ficha

/// Desde la ficha de Comic Vine de un número: elegir cuál de tus archivos es ese cómic.
struct PickLocalFileView: View {
    let detail: CVIssueDetail
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var relinking: LocalComic?
    private var library: LocalLibrary { LocalLibrary.shared }

    private static func number(_ n: String?) -> String? {
        guard let n = n?.trimmingCharacters(in: CharacterSet(charactersIn: " #")), !n.isEmpty else { return nil }
        let trimmed = String(n.drop { $0 == "0" })
        return trimmed.isEmpty || trimmed.hasPrefix(".") ? "0" + trimmed : trimmed
    }

    /// Archivos que parecen ser este cómic: mismo número y nombre de serie parecido.
    private var suggested: [LocalComic] {
        let wantedNumber = Self.number(detail.issueNumber)
        let wantedSeries = ComicVineMatcher.normalize(detail.volume?.name ?? "")
        guard wantedNumber != nil, !wantedSeries.isEmpty else { return [] }
        return library.items.filter { comic in
            let info = FileNameInfo(comic.title)
            var series = ComicVineMatcher.normalize(info.series)
            // Sin el número de orden del principio ("34 Fantastic Four").
            if let first = series.split(separator: " ").first, first.allSatisfy(\.isNumber) {
                series = series.split(separator: " ").dropFirst().joined(separator: " ")
            }
            let sameNumber = Self.number(info.number) == wantedNumber
                || Self.number(comic.cvIssueNumber) == wantedNumber
            let sameSeries = !series.isEmpty && (series.contains(wantedSeries) || wantedSeries.contains(series))
            return sameNumber && sameSeries
        }
    }

    private var others: [LocalComic] {
        let skip = Set(suggested.map(\.id))
        let q = query.trimmingCharacters(in: .whitespaces)
        return library.items
            .filter { !skip.contains($0.id) }
            .filter { q.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(q)
                      || $0.title.localizedCaseInsensitiveContains(q) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Buscar en tu biblioteca", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Elegí cuál de tus archivos es \(CVText.issueTitle(series: detail.volume?.name ?? "este cómic", number: detail.issueNumber)).")
                }
                if !suggested.isEmpty && query.isEmpty {
                    Section("Parecen ser este") {
                        ForEach(suggested) { row($0) }
                    }
                }
                Section("Tu biblioteca") {
                    if others.isEmpty {
                        Text("No hay archivos con ese nombre.").foregroundStyle(Theme.ink2)
                    }
                    ForEach(others) { row($0) }
                }
            }
            .navigationTitle("Elegí el archivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .confirmationDialog("Este archivo ya tiene otra ficha",
                                isPresented: Binding(get: { relinking != nil }, set: { if !$0 { relinking = nil } }),
                                titleVisibility: .visible) {
                Button("Cambiar a esta ficha") {
                    if let comic = relinking { link(comic) }
                    relinking = nil
                }
                Button("Cancelar", role: .cancel) { relinking = nil }
            } message: {
                Text("Ahora está unido a \"\(relinking?.cvTitle ?? "otra ficha")\".")
            }
        }
    }

    private func row(_ comic: LocalComic) -> some View {
        Button {
            if comic.cvIssueID != nil && comic.cvIssueID != detail.id {
                relinking = comic
            } else {
                link(comic)
            }
        } label: {
            HStack(spacing: 12) {
                LocalCover(comic: comic).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(comic.cvTitle.map { "Ahora: \($0)" } ?? "Sin ficha de Comic Vine")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    private func link(_ comic: LocalComic) {
        guard let volume = detail.volume else { return }
        let series = CVVolumeSummary(id: volume.id, name: volume.name, startYear: nil,
                                     countOfIssues: nil, publisher: nil, image: nil)
        let issue = CVIssueSummary(id: detail.id, name: detail.name, issueNumber: detail.issueNumber,
                                   coverDate: detail.coverDate, storeDate: detail.storeDate, image: detail.image)
        library.link(comic.id, series: series, issue: issue, reviewed: true)
        dismiss()
    }
}
