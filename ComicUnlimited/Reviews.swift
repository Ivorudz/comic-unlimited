import SwiftUI
import UIKit

// Comentarios y puntaje.
// - Al terminar un cómic: "¿Qué te pareció?" (estrellas, manitos y comentario).
// - En cada ficha: "Tu comentario". En Perfil y en Comunidad: "Mis comentarios".
// - Metron: al terminar un cómic se marca como leído en tu colección de Metron (con tus estrellas)
//   y en cada ficha se ve el promedio de la comunidad de Metron.
// Con la comunidad (CommunityService.swift), tus comentarios y puntajes los ven tus amigos.

// MARK: - Tu comentario (en la ficha)

struct ReviewSection: View {
    let template: RealLibrary.Entry
    @State private var editing = false
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        let entry = library.entry(template.key)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Tu comentario")
            if let review = entry?.review {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if let date = entry?.reviewDate {
                        Text(Date(timeIntervalSince1970: date).formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Button("Editar") { editing = true }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            } else {
                Button {
                    editing = true
                } label: {
                    Label("Escribir un comentario", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $editing) {
            ReviewEditor(template: template)
        }
        FriendReviewsSection(comicKey: template.key)
    }
}

struct ReviewEditor: View {
    let template: RealLibrary.Entry
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private var library: RealLibrary { RealLibrary.shared }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(template.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                TextEditor(text: $text)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 180)
                Text(Community.shared.isLoggedIn
                     ? "Tu opinión sobre este cómic. La ven tus amigos de la comunidad."
                     : "Tu opinión sobre este cómic. Queda guardada en tu iPhone (si entrás a la Comunidad, también la ven tus amigos).")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                if library.entry(template.key)?.review != nil {
                    Button("Borrar comentario", role: .destructive) {
                        library.setReview(nil, for: template)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
                }
                Spacer()
            }
            .padding(18)
            .background(Theme.paper)
            .navigationTitle("Tu comentario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        library.setReview(text, for: template)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = library.entry(template.key)?.review ?? "" }
        }
    }
}

// MARK: - Al terminar un cómic

/// "¿Qué te pareció?": estrellas, manitos y comentario, al final del lector.
struct RateCard: View {
    let comic: LocalComic
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Qué te pareció?")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let template = RealLibrary.makeEntry(comic) {
                RealLibraryControls(template: template, showsStatus: false)
                Button {
                    editing = true
                } label: {
                    Label(RealLibrary.shared.entry(template.key)?.review == nil ? "Escribir un comentario" : "Editar tu comentario",
                          systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $editing) { ReviewEditor(template: template) }
            } else {
                Text("Para puntuarlo y comentarlo, elegile su ficha de Comic Vine (en la Biblioteca: mantené apretado el cómic → Elegir ficha).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Mis comentarios (Perfil y Comunidad)

struct ReviewRow: View {
    let entry: RealLibrary.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteCover(url: entry.coverURL.flatMap { URL(string: $0) }).frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    if let rating = entry.rating {
                        (Text(String(repeating: "★", count: rating)).foregroundStyle(Theme.star)
                            + Text(String(repeating: "★", count: 5 - rating)).foregroundStyle(Theme.line))
                    }
                    if let thumbs = entry.thumbs {
                        Text(thumbs < 0 ? "👎" : thumbs == 1 ? "👍" : "👍👍")
                    }
                    if let date = entry.reviewDate {
                        Text(Date(timeIntervalSince1970: date).formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .font(.caption)
                if let review = entry.review {
                    Text(review)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// Lleva a la ficha del cómic o la serie de un comentario.
struct EntryLink<Label: View>: View {
    let entry: RealLibrary.Entry
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            if entry.id < 0 {
                NavigationLink(value: LibraryRoute.metronIssue(-entry.id)) { label() }
            } else if entry.isArc {
                NavigationLink(value: CVRoute.arc(id: entry.id, name: entry.title)) { label() }
            } else if entry.isSeries {
                NavigationLink(value: CVRoute.series(id: entry.id, name: entry.title)) { label() }
            } else {
                NavigationLink(value: CVRoute.issue(id: entry.id, title: entry.title)) { label() }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Comunidad (pestaña)

struct CommunityView: View {
    private var library: RealLibrary { RealLibrary.shared }
    private var community: Community { Community.shared }
    @State private var feed: [RemoteReview] = []
    @State private var feedError: String?
    @State private var loadingFeed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Comunidad")
                        .font(.system(size: 32, weight: .black).width(.expanded))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 8)

                    if !community.isConfigured {
                        CommunitySetupCard()
                    } else if !community.isLoggedIn {
                        CommunityLoginCard()
                    } else if community.needsUsername {
                        UsernameCard()
                    } else {
                        accountHeader
                        if community.needsDatabaseUpdate { DatabaseUpdateBanner() }
                        SectionTitle("Tus amigos comentaron")
                        if loadingFeed && feed.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                        } else if let feedError {
                            Text(feedError).font(.subheadline).foregroundStyle(Theme.ink2)
                        } else if feed.isEmpty {
                            Text(community.friends.isEmpty
                                 ? "Todavía no tenés amigos en la comunidad. Tocá \"Amigos\" para agregar a alguien por su nombre de usuario (y que esa persona te agregue a vos)."
                                 : "Tus amigos todavía no comentaron nada.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink2)
                        }
                        ForEach(feed) { review in
                            FeedItem(review: review)
                        }
                    }

                    SectionTitle("Mis comentarios")
                    let reviews = library.reviews
                    if reviews.isEmpty {
                        Text("Todavía no comentaste ningún cómic. Al terminar uno, en el lector aparece \"¿Qué te pareció?\". También podés comentar desde la ficha de cualquier cómic.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                    ForEach(reviews, id: \.key) { entry in
                        EntryLink(entry: entry) { ReviewRow(entry: entry) }
                    }

                    // Botón grande gris: guía para empezar a leer.
                    NavigationLink(value: CommunityRoute.startGuide) {
                        HStack(spacing: 14) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Theme.magenta)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("¿No sabés por dónde empezar a leer?")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Text("Rutas de lectura en orden, con puntos y medallas")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.bold))
                                .foregroundStyle(Theme.ink2)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.paper)
            .refreshable { await loadFeed() }
            .appDestinations()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { BrowsingContext.current = nil }
            .task(id: community.me?.id) {
                await community.loadMe()
                await library.fillMissingCovers()
                await loadFeed()
            }
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 10) {
            NavigationLink(value: CommunityRoute.editProfile) {
                HStack(spacing: 8) {
                    AvatarView(profile: community.me, size: 34)
                    Text("@\(community.me?.username ?? "")")
                        .font(.headline)
                        .foregroundStyle(Theme.magenta)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            NavigationLink(value: CommunityRoute.friends) {
                Label("Amigos\(community.requests.isEmpty ? "" : " (\(community.requests.count))")", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.chip, in: Capsule())
            }
            .buttonStyle(.plain)
            NavigationLink(value: CommunityRoute.settings) {
                Image(systemName: "gearshape")
                    .font(.subheadline.weight(.bold))
                    .padding(9)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.chip, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private func loadFeed() async {
        guard community.isLoggedIn, !community.needsUsername else { return }
        loadingFeed = true
        feedError = nil
        await community.loadFriends()
        do {
            feed = try await community.feed()
        } catch {
            feedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loadingFeed = false
    }
}

enum CommunityRoute: Hashable {
    case friends, settings, editProfile
    /// Perfil de un amigo (por su id en la comunidad).
    case profile(String)
    /// "¿No sabés por dónde empezar a leer?", cada ruta y la ficha de una serie de la guía (StartGuide.swift).
    case startGuide
    case guideRoute(String)
    case guideSeries(String, Int, String)
}

// MARK: - Configurar (primera vez)

private struct CommunitySetupCard: View {
    @State private var url = ""
    @State private var key = ""
    @State private var code = ""
    @State private var errorText: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Para ver lo que comentan tus amigos, la comunidad usa una base de datos gratuita (Supabase) que crea una sola persona. Los demás se suman con un código de invitación.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)

            GroupBox("¿Te invitaron? Pegá el código") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("CU1-…", text: $code, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button("Unirme") {
                        errorText = Community.shared.join(code: code) ? nil : "Ese código no es válido. Copialo entero (empieza con CU1-)."
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .disabled(code.isEmpty)
                }
            }

            GroupBox("¿La creás vos? (una sola vez)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. En Safari, entrá a supabase.com, creá una cuenta gratis y un proyecto nuevo (región: South America).")
                    Text("2. En el proyecto: SQL Editor → New query → pegá el texto de abajo → Run.")
                    Button(copied ? "¡Copiado!" : "Copiar el texto para pegar") {
                        UIPasteboard.general.string = CommunitySetup.sql
                        copied = true
                    }
                    .buttonStyle(.bordered)
                    Text("3. Authentication → Sign In / Providers → Email: apagá \"Confirm email\" y guardá.")
                    Text("4. Project Settings → Data API (o API Keys): copiá la dirección (Project URL) y la clave pública (\"anon\" o \"publishable\"). Pegalas acá:")
                    TextField("https://xxxx.supabase.co", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Clave pública", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Guardar") {
                        Community.shared.configure(url: url, key: key)
                        errorText = Community.shared.isConfigured ? nil : "La dirección tiene que empezar con https://"
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .disabled(url.isEmpty || key.isEmpty)
                    Text("Nunca pegues acá la clave \"service_role\" ni la \"secret\": esas no se comparten.")
                        .font(.caption)
                        .foregroundStyle(Theme.magenta)
                }
                .font(.footnote)
            }

            if let errorText {
                Text(errorText).font(.subheadline).foregroundStyle(Theme.magenta)
            }
        }
        .padding(.top, 10)
    }
}

// MARK: - Entrar / crear cuenta

private struct CommunityLoginCard: View {
    @State private var creating = true
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var working = false
    @State private var errorText: String?

    private var validUsername: Bool { username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $creating) {
                Text("Crear cuenta").tag(true)
                Text("Ya tengo cuenta").tag(false)
            }
            .pickerStyle(.segmented)
            TextField("Mail", text: $email)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                .padding(10).background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            SecureField("Contraseña (6 o más letras y números)", text: $password)
                .padding(10).background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            if creating {
                TextField("Nombre de usuario (minúsculas, números o _)", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: username) { _, value in username = value.lowercased() }
                    .padding(10).background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                Text("Tus amigos te encuentran por este nombre. De 3 a 24: letras minúsculas, números o _.")
                    .font(.caption).foregroundStyle(Theme.ink2)
            }
            Button {
                Task { await go() }
            } label: {
                Group {
                    if working { ProgressView() } else { Text(creating ? "Crear cuenta" : "Entrar") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.magenta)
            .disabled(working || email.isEmpty || password.count < 6 || (creating && !validUsername))
            if let errorText {
                Text(errorText).font(.subheadline).foregroundStyle(Theme.magenta)
            }
            Text("Tu contraseña es solo para la comunidad (no es la de Metron ni la de Comic Vine).")
                .font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(.top, 12)
    }

    private func go() async {
        working = true
        errorText = nil
        do {
            if creating {
                try await Community.shared.signUp(email: email, password: password, username: username)
            } else {
                try await Community.shared.signIn(email: email, password: password)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        working = false
    }
}

/// Entraste pero falta elegir el nombre de usuario.
private struct UsernameCard: View {
    @State private var username = ""
    @State private var errorText: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Elegí tu nombre de usuario").font(.headline).foregroundStyle(Theme.ink)
            TextField("nombre_de_usuario", text: $username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: username) { _, value in username = value.lowercased() }
                .padding(10).background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            Button("Guardar") {
                Task {
                    working = true
                    do {
                        try await Community.shared.createProfile(username: username)
                        await Community.shared.syncAfterLogin()
                    } catch {
                        errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    working = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.magenta)
            .disabled(working || username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) == nil)
            if let errorText { Text(errorText).font(.subheadline).foregroundStyle(Theme.magenta) }
        }
        .padding(.top, 12)
    }
}

// MARK: - Amigos

struct FriendsView: View {
    private var community: Community { Community.shared }
    @State private var username = ""
    @State private var message: String?
    @State private var working = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nombre de usuario de tu amigo", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Agregar") { Task { await add() } }
                        .disabled(working || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.ink2) }
            } header: {
                Text("Agregar")
            } footer: {
                Text("Son amigos cuando los dos se agregan. Ahí ven sus comentarios y puntajes.")
            }

            if !community.requests.isEmpty {
                Section("Te quieren agregar") {
                    ForEach(community.requests) { person in
                        HStack {
                            Text("@\(person.username)")
                            Spacer()
                            Button("Aceptar") { Task { try? await community.follow(person) } }
                                .buttonStyle(.borderedProminent).tint(Theme.magenta)
                        }
                    }
                }
            }

            Section("Amigos") {
                if community.friends.isEmpty {
                    Text("Todavía no tenés amigos en la comunidad.").foregroundStyle(Theme.ink2)
                }
                ForEach(community.friends) { person in
                    NavigationLink(value: CommunityRoute.profile(person.id)) {
                        HStack(spacing: 10) {
                            AvatarView(profile: person, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name).font(.subheadline.weight(.semibold))
                                if person.displayName?.isEmpty == false {
                                    Text("@\(person.username)").font(.caption).foregroundStyle(Theme.ink2)
                                }
                            }
                        }
                    }
                        .swipeActions {
                            Button("Sacar", role: .destructive) { Task { try? await community.remove(person) } }
                        }
                }
            }

            if !community.pending.isEmpty {
                Section {
                    ForEach(community.pending) { person in
                        Text("@\(person.username)")
                            .foregroundStyle(Theme.ink2)
                            .swipeActions {
                                Button("Cancelar", role: .destructive) { Task { try? await community.remove(person) } }
                            }
                    }
                } header: {
                    Text("Esperando que te agreguen")
                }
            }

            Section {
                ShareLink(item: inviteText) {
                    Label("Invitar a un amigo", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Le manda el código para unirse a tu comunidad y cómo instalar la app. El código no incluye ninguna contraseña.")
            }
        }
        .navigationTitle("Amigos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await community.loadFriends() }
        .task { await community.loadFriends() }
    }

    private var inviteText: String {
        """
        ¡Sumate a mi comunidad de Cómic Unlimited! Mi usuario es @\(community.me?.username ?? "").
        1) Instalá la app: https://github.com/ivorudz/comic-unlimited/releases/latest (se abre con LiveContainer).
        2) En la pestaña Comunidad, pegá este código y tocá "Unirme":
        \(community.inviteCode)
        3) Creá tu cuenta y agregame.
        """
    }

    private func add() async {
        working = true
        message = nil
        do {
            if let found = try await community.add(username: username) {
                message = community.friends.contains(found)
                    ? "¡Listo! @\(found.username) ya es tu amigo."
                    : "Le mandaste el pedido a @\(found.username). Cuando te agregue, van a ser amigos."
                username = ""
            } else {
                message = "No encontré a nadie con ese nombre."
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        working = false
    }
}

struct CommunitySettingsView: View {
    private var community: Community { Community.shared }
    @State private var copied = false
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section("Tu cuenta") {
                Text("@\(community.me?.username ?? "")")
                Text(community.session?.email ?? "").foregroundStyle(Theme.ink2)
                Button("Salir de la comunidad", role: .destructive) { community.signOut() }
            }
            Section {
                Button(copied ? "¡Copiado!" : "Copiar código de invitación") {
                    UIPasteboard.general.string = community.inviteCode
                    copied = true
                }
            } footer: {
                Text("Con este código, tus amigos se suman a esta misma comunidad.")
            }
            Section {
                Button("Usar otra comunidad", role: .destructive) { confirmingReset = true }
            } footer: {
                Text("Borra de este iPhone la dirección y la clave de la comunidad (no borra nada de la base de datos).")
            }
        }
        .navigationTitle("Comunidad")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("¿Usar otra comunidad?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Sí, cambiar", role: .destructive) { community.configure(url: "", key: "") }
        }
    }
}

// MARK: - Comentarios de amigos

struct RemoteReviewRow: View {
    let review: RemoteReview
    var showsUser = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsUser {
                RemoteCover(url: review.coverUrl.flatMap { URL(string: $0) }).frame(width: 48)
            }
            VStack(alignment: .leading, spacing: 4) {
                if showsUser {
                    Text(review.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                HStack(spacing: 6) {
                    Text("@\(review.username)").foregroundStyle(Theme.magenta).fontWeight(.semibold)
                    if let rating = review.rating {
                        (Text(String(repeating: "★", count: rating)).foregroundStyle(Theme.star)
                            + Text(String(repeating: "★", count: max(0, 5 - rating))).foregroundStyle(Theme.line))
                    }
                    if let thumbs = review.thumbs {
                        Text(thumbs < 0 ? "👎" : thumbs == 1 ? "👍" : "👍👍")
                    }
                    if let date = review.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.ink2)
                    }
                }
                .font(.caption)
                if let comment = review.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// Lleva a la ficha del cómic que comentó un amigo.
struct RemoteReviewLink<Label: View>: View {
    let review: RemoteReview
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            if let cv = review.cvId, review.kind == "arc" {
                NavigationLink(value: CVRoute.arc(id: cv, name: review.title)) { label() }
            } else if let cv = review.cvId, review.kind == "series" {
                NavigationLink(value: CVRoute.series(id: cv, name: review.title)) { label() }
            } else if let cv = review.cvId {
                NavigationLink(value: CVRoute.issue(id: cv, title: review.title)) { label() }
            } else if let metron = review.metronId {
                NavigationLink(value: LibraryRoute.metronIssue(metron)) { label() }
            } else {
                label()
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Lo que dicen tus amigos" en la ficha de un cómic o serie.
struct FriendReviewsSection: View {
    let comicKey: String
    @State private var reviews: [RemoteReview] = []
    private var community: Community { Community.shared }

    var body: some View {
        Group {
            if !reviews.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Lo que dicen tus amigos")
                    ForEach(reviews) { RemoteReviewRow(review: $0, showsUser: false) }
                }
            }
        }
        .task(id: comicKey) {
            guard community.isLoggedIn, !community.needsUsername else { return }
            reviews = (try? await community.reviews(for: comicKey)) ?? []
        }
    }
}

// MARK: - Metron: "leído" con tus estrellas, y promedio de la comunidad

@MainActor
enum MetronSync {
    static let enabledKey = "settings.metronSync"
    /// Mandar a tu colección de Metron lo que terminás de leer (y tus estrellas). Prendido salvo que lo apagues.
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static var metronIDs: [Int: Int] = [:]
    private static var ratings: [Int: (average: Double, count: Int)] = [:]

    private struct IssueRef: Decodable { let id: Int }

    /// El número de Metron que corresponde a un número de Comic Vine.
    static func metronID(forComicVine cv: Int) async -> Int? {
        if let known = metronIDs[cv] { return known }
        guard let client = MetronClient.current,
              let url = URL(string: "https://metron.cloud/api/issue/?cv_id=\(cv)"),
              let page: MetronList<IssueRef> = try? await client.get(url) else { return nil }
        // Por las dudas: si Metron no entendió el filtro, devuelve muchísimos; solo sirve si es uno.
        guard (page.count ?? page.results.count) == 1, let id = page.results.first?.id else { return nil }
        metronIDs[cv] = id
        return id
    }

    /// Marca como leído en tu colección de Metron (con tus estrellas, si pusiste).
    static func markRead(cvID: Int) async {
        guard enabled, let client = MetronClient.current, let issue = await metronID(forComicVine: cvID) else { return }
        let key = "issue-\(cvID)"
        var body: [String: Any] = ["issue_id": issue]
        if let stars = RealLibrary.shared.entry(key)?.rating { body["rating"] = stars }
        struct Scrobbled: Decodable { let id: Int }
        guard let url = URL(string: "https://metron.cloud/api/collection/scrobble/"),
              let result: Scrobbled = try? await client.send("POST", url, body: body) else { return }
        RealLibrary.shared.setMetronCollectionID(result.id, for: key)
    }

    /// Cambiaste las estrellas de algo que ya está en tu colección de Metron.
    static func updateRating(collectionID: Int, stars: Int) async {
        guard enabled, let client = MetronClient.current,
              let url = URL(string: "https://metron.cloud/api/collection/\(collectionID)/") else { return }
        struct Updated: Decodable { let id: Int }
        let _: Updated? = try? await client.send("PATCH", url, body: ["rating": stars])
    }

    /// Promedio de la comunidad de Metron para un número de Comic Vine.
    static func communityRating(cvID: Int) async -> (average: Double, count: Int)? {
        if let known = ratings[cvID] { return known }
        guard let client = MetronClient.current, let id = await metronID(forComicVine: cvID),
              let detail = try? await client.issueDetail(id: id),
              let result = Self.rating(of: detail) else { return nil }
        ratings[cvID] = result
        return result
    }

    static func rating(of detail: MetronIssueDetail) -> (average: Double, count: Int)? {
        guard let text = detail.averageRating?.text, let average = Double(text), average > 0,
              let count = detail.ratingCount, count > 0 else { return nil }
        return (average, count)
    }
}

/// "Comunidad de Metron: ★ 4.2 (35 votos)" en la ficha de un número.
struct MetronCommunityRating: View {
    let cvID: Int?
    var known: (average: Double, count: Int)? = nil
    @State private var rating: (average: Double, count: Int)?

    var body: some View {
        Group {
            if let rating = known ?? rating {
                Label {
                    Text("Comunidad de Metron: ") + Text(String(format: "★ %.1f", rating.average)).bold()
                        + Text(" (\(rating.count) \(rating.count == 1 ? "voto" : "votos"))")
                } icon: {
                    Image(systemName: "person.3.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 10)
            }
        }
        .task(id: cvID) {
            guard known == nil, let cvID, MetronAccount.isSet else { return }
            rating = await MetronSync.communityRating(cvID: cvID)
        }
    }
}
