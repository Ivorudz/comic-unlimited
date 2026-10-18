import SwiftUI

// Lector a pantalla completa. Las páginas se pasan deslizando con el dedo.
// También se puede tocar el borde derecho o izquierdo para avanzar o volver,
// y tocar el centro para mostrar u ocultar los controles.
struct ReaderView: View {
    @Environment(ReadingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let comic: Comic

    /// Página que se está mostrando. Después de la última hay una tarjeta de "Terminaste".
    @State private var page: Int
    @State private var showControls = true

    init(comic: Comic, startPage: Int) {
        self.comic = comic
        _page = State(initialValue: startPage)
    }

    private var endIndex: Int { comic.pageCount }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $page) {
                    ForEach(0..<comic.pageCount, id: \.self) { index in
                        PageArt(comic: comic, page: index)
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                handleTap(at: location.x, width: geo.size.width)
                            }
                            .tag(index)
                    }
                    endCard
                        .tag(endIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                if showControls || page == endIndex {
                    controls
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(.dark)
        .onChange(of: page) { _, newPage in
            if newPage >= endIndex {
                store.markFinished(comic)
            } else {
                store.setPage(newPage, for: comic)
            }
        }
        .task {
            // A los 2 segundos se esconden los controles para ver la página entera.
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.2)) { showControls = false }
        }
    }

    private func handleTap(at x: CGFloat, width: CGFloat) {
        let ratio = x / max(width, 1)
        if ratio < 0.28 {
            withAnimation { page = max(0, page - 1) }
        } else if ratio > 0.72 {
            withAnimation { page = min(endIndex, page + 1) }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
        }
    }

    // MARK: Controles

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 36)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                .accessibilityLabel("Cerrar lector")
                Text(comic.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 36)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))

            Spacer()

            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(min(page, comic.pageCount - 1) + 1) },
                        set: { page = Int($0.rounded()) - 1 }
                    ),
                    in: 1...Double(max(comic.pageCount, 2)),
                    step: 1
                )
                .tint(Color(hex: 0xFF4FA3))
                .accessibilityLabel("Ir a la página")
                Text("\(min(page, comic.pageCount - 1) + 1) / \(comic.pageCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 54, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: Tarjeta final

    private var endCard: some View {
        VStack(spacing: 12) {
            Text("Terminaste")
                .font(.headline)
                .foregroundStyle(Color(hex: 0xFF4FA3))
            Text(comic.title)
                .font(.system(size: 30, weight: .black).width(.expanded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Quedó guardado como leído.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 12)
            Button {
                withAnimation { page = 0 }
            } label: {
                Text("Volver a empezar")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .background(.white.opacity(0.16), in: Capsule())
            }
            Button { dismiss() } label: {
                Text("Cerrar")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .overlay(Capsule().stroke(.white.opacity(0.3)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 330)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
