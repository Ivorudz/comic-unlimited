import SwiftUI
import UIKit

// Lector para tus cómics en archivo (.cbz, .zip o PDF).
// Las páginas se pasan deslizando. Zoom: con dos dedos o con doble toque.
// Tocar el borde derecho o izquierdo pasa de página; tocar el centro muestra u oculta los controles.

/// Saca las páginas del archivo de a una, en segundo plano, y recuerda las últimas que usó.
actor PageLoader {
    private let file: ComicFile
    private let cache = NSCache<NSNumber, UIImage>()
    let pageCount: Int

    init(file: ComicFile) {
        self.file = file
        pageCount = file.pageCount
        cache.countLimit = 8
    }

    func image(_ index: Int, maxWidth: CGFloat) -> UIImage? {
        if let cached = cache.object(forKey: NSNumber(value: index)) { return cached }
        guard let image = file.page(index, maxWidth: maxWidth) else { return nil }
        cache.setObject(image, forKey: NSNumber(value: index))
        return image
    }
}

struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let comic: LocalComic

    @State private var page: Int
    @State private var showControls = true
    @State private var loader: PageLoader?
    @State private var errorText: String?

    init(comic: LocalComic, startPage: Int) {
        self.comic = comic
        _page = State(initialValue: startPage)
    }

    private var pageCount: Int { loader?.pageCount ?? comic.pageCount }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let loader {
                    TabView(selection: $page) {
                        ForEach(0..<loader.pageCount, id: \.self) { index in
                            LocalPageView(loader: loader, index: index,
                                          maxWidth: geo.size.width * UIScreen.main.scale) { x in
                                handleTap(at: x, width: geo.size.width)
                            }
                            .tag(index)
                        }
                        endCard.tag(loader.pageCount)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                } else if let errorText {
                    VStack(spacing: 14) {
                        Text(errorText).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button("Cerrar") { dismiss() }.foregroundStyle(Color(hex: 0xFF4FA3))
                    }
                    .padding(30)
                } else {
                    ProgressView().tint(.white)
                }

                if showControls || page == pageCount {
                    controls.transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(.dark)
        .task {
            let url = LocalLibrary.shared.fileURL(comic)
            let result: Result<ComicFile, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try ComicFile(url: url)) } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let file):
                loader = PageLoader(file: file)
                page = min(page, max(file.pageCount - 1, 0))
            case .failure(let error):
                errorText = (error as? LocalizedError)?.errorDescription ?? "No se pudo abrir el archivo."
            }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.2)) { showControls = false }
        }
        .onChange(of: page) { _, newPage in
            guard loader != nil else { return }
            if newPage >= pageCount {
                LocalLibrary.shared.markFinished(comic.id)
            } else {
                LocalLibrary.shared.setPage(newPage, for: comic.id)
            }
        }
    }

    private func handleTap(at x: CGFloat, width: CGFloat) {
        let ratio = x / max(width, 1)
        if ratio < 0.25 {
            withAnimation { page = max(0, page - 1) }
        } else if ratio > 0.75 {
            withAnimation { page = min(pageCount, page + 1) }
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
                Text(comic.displayTitle)
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

            if pageCount > 1 {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { Double(min(page, pageCount - 1) + 1) },
                            set: { page = Int($0.rounded()) - 1 }
                        ),
                        in: 1...Double(pageCount),
                        step: 1
                    )
                    .tint(Color(hex: 0xFF4FA3))
                    .accessibilityLabel("Ir a la página")
                    Text("\(min(page, pageCount - 1) + 1) / \(pageCount)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private var endCard: some View {
        VStack(spacing: 12) {
            Text("Terminaste")
                .font(.headline)
                .foregroundStyle(Color(hex: 0xFF4FA3))
            Text(comic.displayTitle)
                .font(.system(size: 28, weight: .black).width(.expanded))
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

/// Una página: la carga en segundo plano y deja hacer zoom.
private struct LocalPageView: View {
    let loader: PageLoader
    let index: Int
    let maxWidth: CGFloat
    let onTap: (CGFloat) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                ZoomableImage(image: image, onSingleTap: onTap)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: index) {
            image = await loader.image(index, maxWidth: maxWidth)
            // Dejamos lista la siguiente página para que no haya espera al pasar.
            _ = await loader.image(index + 1, maxWidth: maxWidth)
        }
    }
}

/// Imagen con zoom (dos dedos o doble toque), hecha con UIKit.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped(_:)))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scroll.setZoomScale(1, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: (CGFloat) -> Void
        weak var imageView: UIImageView?

        init(onSingleTap: @escaping (CGFloat) -> Void) { self.onSingleTap = onSingleTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }

        @objc func singleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            // Con zoom, un toque solo muestra u oculta los controles (no pasa de página).
            if scroll.zoomScale > 1.01 {
                onSingleTap(scroll.bounds.width / 2)
            } else {
                onSingleTap(gesture.location(in: scroll).x)
            }
        }
    }
}
