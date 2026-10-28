import Foundation
import Observation

// Comunidad con amigos, usando una base de datos gratuita (Supabase) que crea el dueño de la app.
// - La dirección del proyecto y su clave pública se escriben en la app (o llegan con un código de invitación)
//   y quedan guardadas solo en este iPhone, nunca en el código ni en GitHub.
// - Cada persona entra con mail y contraseña y elige un nombre de usuario.
// - Amigos: si vos agregás a alguien y esa persona te agrega a vos, son amigos y ven sus comentarios y puntajes.
// - Las reglas de privacidad están en la base de datos (ver `CommunitySetup.sql`): cada uno solo puede
//   escribir, cambiar o borrar lo suyo, y solo ve lo de sus amigos.
// Se habla con Supabase directamente por internet (sin programas de terceros dentro de la app).

struct CommunityProfile: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    /// Datos del perfil (0.30). Pueden faltar si la base de datos todavía no se actualizó.
    var displayName: String? = nil
    var bio: String? = nil
    /// Un emoji como "foto" (si no hay, se usa la inicial).
    var avatar: String? = nil
    /// Si comparte sus listas (Quiero leer / Leyendo / Leído) con sus amigos.
    var shareLists: Bool? = nil
    var readCount: Int? = nil

    /// Nombre para mostrar: el elegido, o el @usuario.
    var name: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        return "@" + username
    }

    var initial: String {
        if let avatar, !avatar.isEmpty { return avatar }
        return String((displayName?.first ?? username.first ?? "?")).uppercased()
    }
}

/// Un comentario o puntaje (tuyo o de un amigo) guardado en la base de datos.
struct RemoteReview: Decodable, Identifiable, Hashable {
    struct Author: Decodable, Hashable { let username: String?; let avatar: String? }
    let userId: String
    let comicKey: String
    let cvId: Int?
    let metronId: Int?
    let kind: String?
    let title: String
    let coverUrl: String?
    let rating: Int?
    let thumbs: Int?
    let comment: String?
    /// Lista ("quiero", "leyendo", "leido"), si comparte sus listas.
    let status: String?
    let updatedAt: String?
    let profiles: Author?

    var id: String { userId + "|" + comicKey }
    var username: String { profiles?.username ?? "alguien" }

    var date: Date? {
        guard let updatedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt)
    }
}

enum CommunityError: LocalizedError {
    case notConfigured
    case notLoggedIn
    case confirmEmail
    case usernameTaken
    case badLogin
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Falta configurar la comunidad (la dirección y la clave del proyecto)."
        case .notLoggedIn: return "Entrá con tu cuenta de la comunidad."
        case .confirmEmail:
            return "La cuenta se creó, pero Supabase pide confirmar el mail. En Supabase: Authentication → Sign In / Providers → Email → apagá \"Confirm email\" y volvé a entrar."
        case .usernameTaken: return "Ese nombre de usuario ya lo usa otra persona. Probá con otro."
        case .badLogin: return "El mail o la contraseña no son correctos."
        case .server(let why): return "La base de datos respondió con un error: \(why)"
        case .network(let why): return "No se pudo conectar. (\(why))"
        }
    }
}

@MainActor
@Observable
final class Community {
    static let shared = Community()

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Double
        let userID: String
        let email: String
    }

    private static let urlKey = "community.url"
    private static let anonKey = "community.key"
    private static let sessionKey = "community.session"
    private static let profileKey = "community.profile"

    private(set) var projectURL: String = UserDefaults.standard.string(forKey: Community.urlKey) ?? ""
    private(set) var apiKey: String = UserDefaults.standard.string(forKey: Community.anonKey) ?? ""
    private(set) var session: Session?
    private(set) var me: CommunityProfile?
    /// La base de datos tiene los datos de perfil y listas (texto de actualización de la 0.30 pegado).
    private(set) var hasProfileV2 = UserDefaults.standard.bool(forKey: "community.v2")
    /// Ya probamos si la base de datos está actualizada (para mostrar el aviso solo si hace falta).
    private(set) var checkedV2 = false
    var needsDatabaseUpdate: Bool { isLoggedIn && me != nil && checkedV2 && !hasProfileV2 }

    /// Amigos (se agregaron los dos), pedidos que te llegaron y pedidos que mandaste.
    private(set) var friends: [CommunityProfile] = []
    private(set) var requests: [CommunityProfile] = []
    private(set) var pending: [CommunityProfile] = []

    var isConfigured: Bool { base != nil && !apiKey.isEmpty }
    var isLoggedIn: Bool { session != nil }

    private var base: URL? {
        var text = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.profileKey) {
            me = try? JSONDecoder().decode(CommunityProfile.self, from: data)
        }
    }

    // MARK: Configuración e invitaciones

    func configure(url: String, key: String) {
        projectURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(projectURL, forKey: Self.urlKey)
        UserDefaults.standard.set(apiKey, forKey: Self.anonKey)
        signOut()
    }

    /// Código para invitar amigos: lleva la dirección del proyecto y su clave pública (no tu contraseña).
    var inviteCode: String {
        "CU1-" + Data("\(projectURL)\n\(apiKey)".utf8).base64EncodedString()
    }

    /// Unirse con un código de invitación. Devuelve false si el código no es válido.
    func join(code: String) -> Bool {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.range(of: "CU1-") else { return false }
        let encoded = String(text[start.upperBound...]).components(separatedBy: .whitespacesAndNewlines).first ?? ""
        guard let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) else { return false }
        let parts = decoded.components(separatedBy: "\n")
        guard parts.count == 2, URL(string: parts[0])?.host != nil, !parts[1].isEmpty else { return false }
        configure(url: parts[0], key: parts[1])
        return true
    }

    // MARK: Cuenta

    private struct AuthResponse: Decodable {
        struct User: Decodable { let id: String; let email: String? }
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let user: User?
        // Si Supabase pide confirmar el mail, la respuesta es el usuario solo (sin sesión).
        let id: String?
    }

    func signUp(email: String, password: String, username: String) async throws {
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
        let response: AuthResponse = try await auth("signup", ["email": email, "password": password])
        guard let session = makeSession(response, email: email) else { throw CommunityError.confirmEmail }
        store(session)
        do {
            try await createProfile(username: name)
            await loadMe()
        } catch {
            signOut()
            throw error
        }
        Task { await syncAfterLogin() }
    }

    func signIn(email: String, password: String) async throws {
        let response: AuthResponse
        do {
            response = try await auth("token?grant_type=password", ["email": email, "password": password])
        } catch CommunityError.server {
            throw CommunityError.badLogin
        }
        guard let session = makeSession(response, email: email) else { throw CommunityError.badLogin }
        store(session)
        await loadMe()
        Task { await syncAfterLogin() }
    }

    func signOut() {
        session = nil
        me = nil
        friends = []
        requests = []
        pending = []
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
    }

    /// Si entraste pero todavía no elegiste nombre de usuario.
    var needsUsername: Bool { isLoggedIn && me == nil }

    func createProfile(username: String) async throws {
        guard let session else { throw CommunityError.notLoggedIn }
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
        do {
            _ = try await rest("POST", "profiles", body: ["id": session.userID, "username": name],
                               prefer: "return=minimal")
        } catch CommunityError.server(let why) where why.contains("409") || why.contains("23505") {
            throw CommunityError.usernameTaken
        }
        setMe(CommunityProfile(id: session.userID, username: name))
    }

    static let profileColumnsV2 = "id,username,display_name,bio,avatar,share_lists,read_count"
    private var profileColumns: String { hasProfileV2 ? Self.profileColumnsV2 : "id,username" }

    func loadMe() async {
        guard let session else { return }
        // Primero con los datos nuevos del perfil; si la base de datos no los tiene, sin ellos.
        do {
            let list: [CommunityProfile]? = try await rest("GET", "profiles?id=eq.\(session.userID)&select=\(Self.profileColumnsV2)")
            setV2(true)
            if let found = list?.first { setMe(found) }
        } catch CommunityError.server {
            setV2(false)
            let list: [CommunityProfile]? = try? await rest("GET", "profiles?id=eq.\(session.userID)&select=id,username")
            if let found = list?.first { setMe(found) }
        } catch {}
    }

    private func setV2(_ value: Bool) {
        hasProfileV2 = value
        checkedV2 = true
        UserDefaults.standard.set(value, forKey: "community.v2")
    }

    /// Cambiar tu nombre, bio, emoji o si compartís tus listas.
    func updateProfile(displayName: String, bio: String, avatar: String, shareLists: Bool) async throws {
        guard let session, hasProfileV2 else { throw CommunityError.notLoggedIn }
        let sharingChanged = (me?.shareLists ?? true) != shareLists
        _ = try await rest("PATCH", "profiles?id=eq.\(session.userID)", body: [
            "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "avatar": String(avatar.trimmingCharacters(in: .whitespaces).prefix(2)),
            "share_lists": shareLists,
        ] as [String: Any], prefer: "return=minimal")
        await loadMe()
        if sharingChanged { await syncAfterLogin() }
    }

    /// El perfil de un amigo (con sus datos, si la base de datos está actualizada).
    func profile(id: String) async throws -> CommunityProfile? {
        let list: [CommunityProfile] = try await rest("GET", "profiles?id=eq.\(id)&select=\(profileColumns)") ?? []
        return list.first
    }

    /// Todo lo de un amigo: comentarios, puntajes y (si las comparte) sus listas.
    func activity(of userID: String) async throws -> [RemoteReview] {
        try await rest("GET", "reviews?select=\(reviewColumns)&user_id=eq.\(userID)&order=updated_at.desc&limit=300") ?? []
    }

    private func setMe(_ profile: CommunityProfile) {
        me = profile
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.profileKey) }
    }

    private func makeSession(_ r: AuthResponse, email: String) -> Session? {
        guard let token = r.accessToken, let refresh = r.refreshToken, let user = r.user else { return nil }
        return Session(accessToken: token, refreshToken: refresh,
                       expiresAt: Date().timeIntervalSince1970 + (r.expiresIn ?? 3600),
                       userID: user.id, email: user.email ?? email)
    }

    private func store(_ s: Session) {
        session = s
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.sessionKey) }
    }

    /// La "llave" de la sesión dura una hora: antes de que venza se pide otra.
    private func refreshIfNeeded() async throws {
        guard var s = session else { throw CommunityError.notLoggedIn }
        guard Date().timeIntervalSince1970 > s.expiresAt - 120 else { return }
        let r: AuthResponse = try await auth("token?grant_type=refresh_token", ["refresh_token": s.refreshToken])
        guard let token = r.accessToken, let refresh = r.refreshToken else {
            signOut()
            throw CommunityError.notLoggedIn
        }
        s.accessToken = token
        s.refreshToken = refresh
        s.expiresAt = Date().timeIntervalSince1970 + (r.expiresIn ?? 3600)
        store(s)
    }

    // MARK: Amigos

    private struct Follow: Decodable { let follower: String; let followee: String }

    func loadFriends() async {
        guard let session else { return }
        let me = session.userID
        guard let follows: [Follow] = try? await rest("GET", "follows?select=follower,followee&or=(follower.eq.\(me),followee.eq.\(me))") else { return }
        let iFollow = Set(follows.filter { $0.follower == me }.map(\.followee))
        let followMe = Set(follows.filter { $0.followee == me }.map(\.follower))
        let ids = iFollow.union(followMe)
        guard !ids.isEmpty else {
            friends = []; requests = []; pending = []
            return
        }
        let list: [CommunityProfile] = (try? await rest("GET", "profiles?select=\(profileColumns)&id=in.(\(ids.joined(separator: ",")))")) ?? []
        let sorted = list.sorted { $0.username < $1.username }
        friends = sorted.filter { iFollow.contains($0.id) && followMe.contains($0.id) }
        requests = sorted.filter { followMe.contains($0.id) && !iFollow.contains($0.id) }
        pending = sorted.filter { iFollow.contains($0.id) && !followMe.contains($0.id) }
    }

    /// Agregar a alguien por su nombre de usuario. Devuelve su perfil, o nil si no existe.
    func add(username: String) async throws -> CommunityProfile? {
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let list: [CommunityProfile] = try await rest("GET", "profiles?select=id,username&username=eq.\(name)") ?? []
        guard let found = list.first, found.id != session?.userID else { return nil }
        try await follow(found)
        return found
    }

    func follow(_ profile: CommunityProfile) async throws {
        guard let session else { throw CommunityError.notLoggedIn }
        _ = try await rest("POST", "follows?on_conflict=follower,followee",
                           body: ["follower": session.userID, "followee": profile.id],
                           prefer: "resolution=ignore-duplicates,return=minimal")
        await loadFriends()
    }

    func remove(_ profile: CommunityProfile) async throws {
        guard let session else { throw CommunityError.notLoggedIn }
        _ = try await rest("DELETE", "follows?follower=eq.\(session.userID)&followee=eq.\(profile.id)",
                           prefer: "return=minimal")
        await loadFriends()
    }

    // MARK: Comentarios y puntajes

    private var reviewColumns: String {
        hasProfileV2
            ? "user_id,comic_key,cv_id,metron_id,kind,title,cover_url,rating,thumbs,comment,status,updated_at,profiles(username,avatar)"
            : "user_id,comic_key,cv_id,metron_id,kind,title,cover_url,rating,thumbs,comment,updated_at,profiles(username)"
    }
    /// Solo filas con comentario o puntaje (no las que son solo "está en su lista").
    private static let onlyOpinions = "or=(comment.not.is.null,rating.not.is.null,thumbs.not.is.null)"

    /// Lo último de tus amigos (la base de datos solo devuelve lo de tus amigos y lo tuyo).
    func feed() async throws -> [RemoteReview] {
        guard let session else { throw CommunityError.notLoggedIn }
        return try await rest("GET", "reviews?select=\(reviewColumns)&user_id=neq.\(session.userID)&\(Self.onlyOpinions)&order=updated_at.desc&limit=60") ?? []
    }

    /// Lo que dijeron tus amigos de un cómic o serie (por ejemplo "issue-123").
    func reviews(for comicKey: String) async throws -> [RemoteReview] {
        guard let session else { throw CommunityError.notLoggedIn }
        let key = comicKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? comicKey
        return try await rest("GET", "reviews?select=\(reviewColumns)&comic_key=eq.\(key)&user_id=neq.\(session.userID)&\(Self.onlyOpinions)&order=updated_at.desc") ?? []
    }

    /// Sube (o borra) tu comentario y puntaje de un cómic.
    func push(_ entry: RealLibrary.Entry?, key: String) async {
        guard let session, me != nil else { return }
        if let entry, shouldShare(entry) {
            _ = try? await rest("POST", "reviews?on_conflict=user_id,comic_key", body: [row(entry, user: session.userID)],
                                prefer: "resolution=merge-duplicates,return=minimal")
        } else {
            let k = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? key
            _ = try? await rest("DELETE", "reviews?user_id=eq.\(session.userID)&comic_key=eq.\(k)", prefer: "return=minimal")
        }
    }

    /// Al entrar: sube todos tus comentarios y puntajes, y carga tus amigos.
    func syncAfterLogin() async {
        guard let session, me != nil else { return }
        let entries = Array(RealLibrary.shared.entries.values)
        let rows = entries.filter(shouldShare).map { row($0, user: session.userID) }
        if !rows.isEmpty {
            _ = try? await rest("POST", "reviews?on_conflict=user_id,comic_key", body: rows,
                                prefer: "resolution=merge-duplicates,return=minimal")
        }
        if hasProfileV2 {
            // Si dejaste de compartir tus listas, se borran las filas que eran solo "está en mi lista".
            if !sharesLists {
                _ = try? await rest("DELETE", "reviews?user_id=eq.\(session.userID)&comment=is.null&rating=is.null&thumbs=is.null",
                                    prefer: "return=minimal")
            }
            // Cuántos leíste (para tu perfil).
            let read = entries.filter { $0.status == .read && $0.isIssue }.count
            _ = try? await rest("PATCH", "profiles?id=eq.\(session.userID)", body: ["read_count": read], prefer: "return=minimal")
        }
        await loadFriends()
    }

    private var sharesLists: Bool { hasProfileV2 && (me?.shareLists ?? true) }

    /// Qué se sube: lo que tiene comentario o puntaje y, si compartís tus listas, también lo que está en una lista.
    private func shouldShare(_ e: RealLibrary.Entry) -> Bool {
        e.review != nil || e.rating != nil || e.thumbs != nil || (sharesLists && e.status != nil)
    }

    private func row(_ e: RealLibrary.Entry, user: String) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": user,
            "comic_key": e.key,
            "kind": e.isArc ? "arc" : (e.isSeries ? "series" : "issue"),
            "title": e.title,
            "updated_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: e.reviewDate ?? e.updated)),
        ]
        if e.id > 0 { row["cv_id"] = e.id } else { row["metron_id"] = -e.id }
        // Lo que no tiene valor va vacío (null), para que también se borre allá.
        row["cover_url"] = e.coverURL.map { $0 as Any } ?? NSNull()
        row["rating"] = e.rating.map { $0 as Any } ?? NSNull()
        row["thumbs"] = e.thumbs.map { $0 as Any } ?? NSNull()
        row["comment"] = e.review.map { $0 as Any } ?? NSNull()
        if hasProfileV2 {
            row["status"] = sharesLists ? (e.status.map { $0.rawValue as Any } ?? NSNull()) : NSNull()
        }
        return row
    }

    // MARK: Pedidos a Supabase

    private func auth<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        guard let base, isConfigured else { throw CommunityError.notConfigured }
        guard let url = URL(string: base.absoluteString + "/auth/v1/" + path) else { throw CommunityError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(request)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Pedido a las tablas. `path` es lo que va después de /rest/v1/.
    @discardableResult
    private func rest<T: Decodable>(_ method: String, _ path: String, body: Any? = nil,
                                    prefer: String? = nil) async throws -> T? {
        guard let base, isConfigured else { throw CommunityError.notConfigured }
        try await refreshIfNeeded()
        guard let session, let url = URL(string: base.absoluteString + "/rest/v1/" + path) else {
            throw CommunityError.notLoggedIn
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data = try await send(request)
        guard !data.isEmpty else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }

    /// Para pedidos que no devuelven nada.
    private func rest(_ method: String, _ path: String, body: Any? = nil, prefer: String? = nil) async throws -> Bool {
        let _: EmptyResponse? = try await rest(method, path, body: body, prefer: prefer)
        return true
    }

    private struct EmptyResponse: Decodable {}

    private func send(_ original: URLRequest) async throws -> Data {
        var request = original
        request.timeoutInterval = 30
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw CommunityError.network(error.localizedDescription)
        }
        let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let text = String(decoding: result.0.prefix(300), as: UTF8.self)
            throw CommunityError.server("código \(code) \(text)")
        }
        return result.0
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
