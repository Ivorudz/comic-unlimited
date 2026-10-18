import SwiftUI

// Ficha de un cómic: portada, datos, sinopsis y el botón para leer.
struct DetailView: View {
    @Environment(ReadingStore.self) private var store
    let comic: Comic
    let onRead: (Comic) -> Void

    private var buttonLabel: String {
        if store.isFinished(comic) { return "Volver a leer" }
        let page = store.savedPage(for: comic)
        return page > 0 ? "Seguir en la página \(page + 1)" : "Empezar a leer"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    CoverArt(comic: comic)
                        .frame(width: 140)
                    VStack(alignment: .leading, spacing: 6) {
                        SourceBadge(source: comic.source)
                        (Text(comic.title) + Text(comic.issue.isEmpty ? "" : " \(comic.issue)").foregroundStyle(Theme.magenta))
                            .font(.system(size: 26, weight: .black).width(.expanded))
                            .foregroundStyle(Theme.ink)
                            .misprint(0.7)
                        Text(comic.author)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                        if let publisher = comic.publisher {
                            Text("Editorial \(publisher)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                        }
                        (Text("★ ").foregroundStyle(Theme.star)
                            + Text(String(format: "%.1f", comic.rating)).bold()
                            + Text("  \(comic.votes) votos").font(.footnote).foregroundStyle(Theme.ink2))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 10)

                Button { onRead(comic) } label: {
                    Text(buttonLabel)
                        .font(.system(size: 17, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(15)
                        .foregroundStyle(Theme.paper)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                Text(comic.synopsis)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .padding(.top, 18)

                HStack(spacing: 10) {
                    Fact(title: "Género", value: comic.genre)
                    Fact(title: "Páginas", value: "\(comic.pageCount)")
                    Fact(title: "Origen", value: comic.source.label)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct Fact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.ink2)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}
