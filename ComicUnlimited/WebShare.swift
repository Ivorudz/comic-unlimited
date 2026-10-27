import SwiftUI
import Network
import AVFoundation
import Observation

// "Ver en la compu": el iPhone hace de servidor en tu Wi-Fi y la compu lee tus cómics en el navegador.
// - Nada sale de tu casa: la compu le pide las páginas directo al iPhone (sin internet, sin subir nada).
// - Hace falta un código de 6 números que muestra la app (así nadie más en tu Wi-Fi puede entrar).
// - Solo lectura: desde la compu no se borran ni se agregan cómics (solo se guarda la página donde quedaste).
// - "Con el teléfono bloqueado": iOS duerme las apps que no están en pantalla; para seguir funcionando,
//   la app reproduce un silencio continuo (LiveContainer permite audio en segundo plano). Gasta algo de batería.
// - Se apaga solo después de 30 minutos sin que la compu pida nada.
// La página que ve la compu está en WebShareSite.swift.

@MainActor
@Observable
final class WebShare {
    static let shared = WebShare()
    nonisolated static let lockedKey = "webshare.keepRunningLocked"

    private(set) var isOn = false
    private(set) var address: String?
    private(set) var code = ""
    private(set) var errorText: String?
    /// Cuándo pidió algo la compu por última vez, y cuántas páginas mandó.
    private(set) var lastRequest: Date?
    private(set) var pagesServed = 0

    private var server: WebServer?
    private let silence = SilentAudio()
    private var idleTimer: Timer?
    private static let idleLimit: TimeInterval = 30 * 60

    var keepRunningLocked: Bool {
        UserDefaults.standard.object(forKey: Self.lockedKey) as? Bool ?? true
    }

    func start() {
        guard !isOn else { return }
        errorText = nil
        guard let ip = Self.wifiAddress() else {
            errorText = "No encontré tu Wi-Fi. Conectá el iPhone a la misma red Wi-Fi que la compu y probá de nuevo."
            return
        }
        code = String(format: "%06d", Int.random(in: 0...999_999))
        guard launch(ip: ip, port: 8080) else { return }
        isOn = true
        lastRequest = Date()
        pagesServed = 0
        if keepRunningLocked { silence.start() }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in WebShare.shared.checkIdle() }
        }
    }

    /// Abre el servidor en ese puerto. Si el puerto está ocupado, prueba con el siguiente (hasta 8090).
    @discardableResult
    private func launch(ip: String, port: UInt16) -> Bool {
        let accessCode = code
        let server = WebServer { request in await WebShareRoutes.handle(request, code: accessCode) }
        server.onFailure = {
            Task { @MainActor in WebShare.shared.portFailed(ip: ip, port: port) }
        }
        do {
            try server.start(port: port)
        } catch {
            errorText = "No se pudo abrir la conexión en el iPhone. Probá de nuevo en un rato."
            return false
        }
        self.server = server
        address = "http://\(ip):\(port)/?c=\(accessCode)"
        return true
    }

    private func portFailed(ip: String, port: UInt16) {
        guard isOn else { return }
        server?.stop()
        server = nil
        if port < 8090, launch(ip: ip, port: port + 1) { return }
        stop()
        errorText = "No se pudo abrir la conexión en el iPhone. Probá de nuevo en un rato."
    }

    func stop() {
        server?.stop()
        server = nil
        silence.stop()
        idleTimer?.invalidate()
        idleTimer = nil
        isOn = false
        address = nil
    }

    /// Prender o apagar "con el teléfono bloqueado" mientras ya está compartiendo.
    func setKeepRunningLocked(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.lockedKey)
        guard isOn else { return }
        if on { silence.start() } else { silence.stop() }
    }

    func noteRequest(page: Bool) {
        lastRequest = Date()
        if page { pagesServed += 1 }
    }

    private func checkIdle() {
        guard isOn, let lastRequest else { return }
        if Date().timeIntervalSince(lastRequest) > Self.idleLimit {
            stop()
            errorText = "Se apagó solo después de 30 minutos sin usarse."
        }
    }

    /// Dirección del iPhone en el Wi-Fi (por ejemplo 192.168.0.15).
    private static func wifiAddress() -> String? {
        var result: String?
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let item = pointer {
            let interface = item.pointee
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if name == "en0" { return ip }
                // Otra red de casa (por si el Wi-Fi no se llama en0).
                if result == nil, name.hasPrefix("en"), !ip.hasPrefix("169.254") { result = ip }
            }
            pointer = interface.ifa_next
        }
        return result
    }
}

// MARK: - Qué responde el iPhone

enum WebShareRoutes {
    struct ComicInfo: Encodable {
        let id: String
        let title: String
        let series: String?
        let pages: Int
        let lastPage: Int
        let finished: Bool
        let opened: Double
        let added: Double
    }

    static func handle(_ request: HTTPRequest, code: String) async -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        if parts.isEmpty || parts == ["index.html"] {
            return .html(WebShareSite.html)
        }
        guard parts.first == "api" else { return .text(404, "No existe.") }
        guard request.query["c"] == code else { return .text(403, "Falta el código o no es correcto.") }

        switch Array(parts.dropFirst()).count > 0 ? parts[1] : "" {
        case "library":
            let list: [ComicInfo] = await MainActor.run {
                WebShare.shared.noteRequest(page: false)
                return LocalLibrary.shared.items.map { c in
                    ComicInfo(id: c.id, title: c.displayTitle, series: c.cvSeriesName,
                              pages: c.pageCount, lastPage: c.lastPage ?? 0, finished: c.isFinished,
                              opened: c.lastOpened ?? 0, added: c.added)
                }
            }
            return .json(list)

        case "cover" where parts.count == 3:
            let url: URL? = await MainActor.run {
                LocalLibrary.shared.item(parts[2]).map { LocalLibrary.shared.coverURL($0) }
            }
            guard let url, let data = try? Data(contentsOf: url) else { return .text(404, "Sin portada.") }
            return HTTPResponse(status: 200, contentType: "image/jpeg", body: data, cache: true)

        case "page" where parts.count == 4:
            guard let index = Int(parts[3]) else { return .text(400, "Página no válida.") }
            let url: URL? = await MainActor.run {
                WebShare.shared.noteRequest(page: true)
                return LocalLibrary.shared.item(parts[2]).map { LocalLibrary.shared.fileURL($0) }
            }
            guard let url, let data = await PageServer.shared.jpeg(file: url, page: index) else {
                return .text(404, "No se pudo leer esa página.")
            }
            return HTTPResponse(status: 200, contentType: "image/jpeg", body: data, cache: true)

        case "progress" where parts.count == 4:
            guard let page = Int(parts[3]) else { return .text(400, "Página no válida.") }
            await MainActor.run {
                let library = LocalLibrary.shared
                guard let comic = library.item(parts[2]) else { return }
                if page >= comic.pageCount - 1 { library.markFinished(comic.id) } else { library.setPage(page, for: comic.id) }
            }
            return .text(200, "ok")

        default:
            return .text(404, "No existe.")
        }
    }
}

/// Abre los archivos y saca las páginas de a una (guarda abiertos los últimos dos cómics).
actor PageServer {
    static let shared = PageServer()
    private var open: [(url: URL, file: ComicFile)] = []

    func jpeg(file url: URL, page: Int) -> Data? {
        let file: ComicFile
        if let found = open.first(where: { $0.url == url }) {
            file = found.file
        } else {
            guard let opened = try? ComicFile(url: url) else { return nil }
            open.insert((url: url, file: opened), at: 0)
            if open.count > 2 { open.removeLast() }
            file = opened
        }
        return file.page(page, maxWidth: 2000)?.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Servidor HTTP chiquito (Network de Apple, sin programas de terceros)

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
}

struct HTTPResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data
    var cache = false

    static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    static func html(_ text: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(text.utf8))
    }

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json; charset=utf-8",
                     body: (try? JSONEncoder().encode(value)) ?? Data("[]".utf8))
    }

    func serialized() -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += cache ? "Cache-Control: private, max-age=3600\r\n" : "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

final class WebServer: @unchecked Sendable {
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private let queue = DispatchQueue(label: "comicunlimited.webshare")
    private var listener: NWListener?
    /// Se llama si no se pudo abrir el puerto (por ejemplo, porque lo usa otra app).
    var onFailure: (@Sendable () -> Void)?

    init(handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.handler = handler
    }

    func start(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw URLError(.badURL) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.onFailure?() }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                guard let request = Self.parse(head) else { connection.cancel(); return }
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            } else if isComplete || error != nil || buffer.count > 32_768 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    /// Lee la primera línea del pedido: "GET /api/page/ID/3?c=123456 HTTP/1.1".
    private static func parse(_ head: String) -> HTTPRequest? {
        guard let line = head.split(separator: "\r\n", omittingEmptySubsequences: false).first else { return nil }
        let pieces = line.split(separator: " ")
        guard pieces.count >= 2 else { return nil }
        let target = String(pieces[1])
        let components = URLComponents(string: "http://iphone" + target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(method: String(pieces[0]), path: components?.path ?? "/", query: query)
    }
}

// MARK: - Silencio para seguir con el teléfono bloqueado

final class SilentAudio {
    private var player: AVAudioPlayer?
    private var observer: NSObjectProtocol?

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: Self.silentWAV())
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.play()
        // Si una llamada corta el audio, cuando termina se vuelve a empezar.
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.player?.play()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Un segundo de silencio en formato WAV (se arma acá, sin archivos de sonido).
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let samples = Data(count: Int(sampleRate) * 2)   // 16 bits, mono, todo en cero
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count).littleEndian)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian); append((sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count).littleEndian)
        data.append(samples)
        return data
    }
}

// MARK: - Pantalla "Ver en la compu"

struct WebShareView: View {
    private var share: WebShare { WebShare.shared }
    @AppStorage(WebShare.lockedKey) private var keepRunningLocked = true
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Leé tus cómics en el navegador de la compu, sin subirlos a ningún lado: la compu se los pide directo a este iPhone por tu Wi-Fi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)

                if share.isOn, let address = share.address {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Compartiendo", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundStyle(Theme.magenta)
                        Text("En la compu, abrí el navegador y escribí:")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Text(address)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                        Text("Código: \(share.code)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                        Button(copied ? "¡Copiado!" : "Copiar dirección") {
                            UIPasteboard.general.string = address
                            copied = true
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                        if let last = share.lastRequest {
                            Text("Última vez que la compu pidió algo: \(last.formatted(date: .omitted, time: .shortened)) · \(share.pagesServed) páginas")
                                .font(.caption)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.magenta, lineWidth: 2))

                    Button(role: .destructive) { share.stop() } label: {
                        Text("Dejar de compartir").frame(maxWidth: .infinity).padding(12)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        copied = false
                        share.start()
                    } label: {
                        Label("Empezar a compartir", systemImage: "desktopcomputer")
                            .font(.system(size: 16, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .foregroundStyle(.white)
                            .background(Theme.magenta, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                if let error = share.errorText {
                    Text(error).font(.subheadline).foregroundStyle(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { keepRunningLocked }, set: { on in
                        keepRunningLocked = on
                        share.setKeepRunningLocked(on)
                    })) {
                        Text("Seguir con el teléfono bloqueado")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.magenta)
                    Text("Para que no se corte al bloquear el iPhone, la app reproduce un silencio mientras comparte (no se escucha nada y no corta tu música). Gasta un poco más de batería.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bueno saber").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                    Group {
                        Text("• El iPhone y la compu tienen que estar en el mismo Wi-Fi.")
                        Text("• La primera vez el iPhone pide permiso para \"buscar dispositivos en la red local\": tocá Permitir.")
                        Text("• Al abrir un cómic, la compu guarda todas sus páginas: si se corta la conexión, ese cómic se sigue leyendo.")
                        Text("• Desde la compu solo se lee. La página donde quedaste vuelve al iPhone.")
                        Text("• Se apaga solo después de 30 minutos sin usarse.")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                }
            }
            .padding(18)
        }
        .background(Theme.paper)
        .navigationTitle("Ver en la compu")
        .navigationBarTitleDisplayMode(.inline)
    }
}
