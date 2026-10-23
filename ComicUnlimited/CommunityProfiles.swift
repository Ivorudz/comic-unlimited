import SwiftUI
import UIKit

// Perfiles de la comunidad (0.30): tu perfil (nombre, bio, emoji, si compartís tus listas)
// y el perfil de cada amigo (sus números, comentarios y listas). Todo lo ven solo tus amigos.

// MARK: - "Foto" (emoji o inicial)

struct AvatarView: View {
    let profile: CommunityProfile?
    var size: CGFloat = 40

    var body: some View {
        let text = profile?.initial ?? "?"
        let isEmoji = profile?.avatar?.isEmpty == false
        ZStack {
            Circle().fill(isEmoji ? Theme.chip : Theme.magenta)
            Text(text)
                .font(.system(size: size * (isEmoji ? 0.55 : 0.45), weight: .heavy))
                .foregroundStyle(isEmoji ? Theme.ink : .white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Aviso: actualizar la base de datos

/// Si la base de datos se armó antes de la 0.30, hay que pegar un texto corto más en Supabase.
struct DatabaseUpdateBanner: View {
    @State private var copied = false
    private var community: Community { Community.shared }

    /// Link directo al SQL Editor del proyecto (el código del proyecto sale de su dirección).
    private var sqlEditorURL: URL? {
        guard let host = URL(string: community.projectURL)?.host,
              let ref = host.components(separatedBy: ".").first else { return nil }
        return URL(string: "https://supabase.com/dashboard/project/\(ref)/sql/new")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Falta actualizar la base de datos", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Para los perfiles y las listas compartidas: copiá este texto, abrí el SQL Editor de Supabase, pegalo y tocá Run (no borra nada). Después volvé a esta pantalla.")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            HStack {
                Button(copied ? "¡Copiado!" : "Copiar el texto") {
                    UIPasteboard.general.string = CommunitySetup.updateV2
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.magenta)
                if let sqlEditorURL {
                    Link("Abrir SQL Editor", destination: sqlEditorURL)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.magenta.opacity(0.6)))
        .padding(.top, 12)
    }
}

// MARK: - Un comentario en "Tus amigos comentaron"

/// Arriba quién lo escribió (toca y abre su perfil); abajo el cómic (toca y abre su ficha).
struct FeedItem: View {
    let review: RemoteReview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: CommunityRoute.profile(review.userId)) {
                HStack(spacing: 6) {
                    AvatarView(profile: CommunityProfile(id: review.userId, username: review.username,
                                                         avatar: review.profiles?.avatar), size: 22)
                    Text("@\(review.username)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                    Spacer()
                }
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RemoteReviewLink(review: review) { RemoteReviewRow(review: review, showsUser: true) }
        }
    }
}

// MARK: - Perfil de un amigo

struct FriendProfileView: View {
    let userID: String
    @State private var profile: CommunityProfile?
    @State private var activity: [RemoteReview] = []
    @State private var tab = 0
    @State private var loading = true
    @State private var errorText: String?
    private var community: Community { Community.shared }

    private var opinions: [RemoteReview] {
        activity.filter { $0.comment != nil || $0.rating != nil || $0.thumbs != nil }
    }
    private func list(_ status: String) -> [RemoteReview] { activity.filter { $0.status == status } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    AvatarView(profile: profile, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile?.name ?? "")
                            .font(.system(size: 22, weight: .black).width(.expanded))
                            .foregroundStyle(Theme.ink)
                        if let profile, profile.displayName?.isEmpty == false {
                            Text("@\(profile.username)").font(.subheadline).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .padding(.top, 10)

                if let bio = profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 10)
                }

                HStack(spacing: 10) {
                    stat("\(profile?.readCount ?? list("leido").count)", "leídos")
                    stat("\(opinions.filter { $0.comment != nil }.count)", "comentarios")
                    stat("\(opinions.filter { $0.rating != nil || $0.thumbs != nil }.count)", "puntuados")
                }
                .padding(.top, 14)

                Picker("", selection: $tab) {
                    Text("Comentarios").tag(0)
                    Text("Leyendo").tag(1)
                    Text("Quiere leer").tag(2)
                    Text("Leídos").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.top, 16)

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if let errorText {
                    Text(errorText).font(.subheadline).foregroundStyle(Theme.ink2).padding(.top, 12)
                } else {
                    let items: [RemoteReview] = [opinions, list("leyendo"), list("quiero"), list("leido")][tab]
                    if items.isEmpty {
                        Text(tab == 0 ? "Todavía no comentó ni puntuó nada."
                             : (profile?.shareLists == false ? "No comparte sus listas." : "No hay nada en esta lista."))
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .padding(.top, 12)
                    }
                    ForEach(items) { item in
                        RemoteReviewLink(review: item) { RemoteReviewRow(review: item, showsUser: true) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle(profile?.name ?? "Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { if profile == nil { await load() } }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .black)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            profile = try await community.profile(id: userID)
            activity = try await community.activity(of: userID)
            if profile != nil, activity.isEmpty, community.friends.contains(where: { $0.id == userID }) == false {
                errorText = "Para ver sus comentarios y listas, tienen que agregarse los dos."
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Editar tu perfil

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var bio = ""
    @State private var avatar = ""
    @State private var shareLists = true
    @State private var saving = false
    @State private var errorText: String?
    private var community: Community { Community.shared }

    private let emojis = ["🦸", "🦹", "🕷️", "🦇", "⚡️", "🔥", "🛡️", "🤖", "👽", "🐉", "💀", "⭐️"]

    var body: some View {
        Form {
            if community.needsDatabaseUpdate {
                Section { DatabaseUpdateBanner() }
            }
            Section {
                HStack {
                    Spacer()
                    AvatarView(profile: CommunityProfile(id: "", username: community.me?.username ?? "?",
                                                         displayName: displayName, avatar: avatar), size: 72)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Inicial") { avatar = "" }
                            .buttonStyle(.bordered)
                        ForEach(emojis, id: \.self) { emoji in
                            Button(emoji) { avatar = emoji }
                                .font(.title2)
                                .padding(4)
                                .background(avatar == emoji ? Theme.magenta.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } header: {
                Text("Tu foto")
            } footer: {
                Text("Un emoji o la inicial de tu nombre.")
            }

            Section("Nombre y bio") {
                TextField("Nombre para mostrar (opcional)", text: $displayName)
                TextField("Una frase sobre vos (opcional)", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Toggle("Compartir mis listas con mis amigos", isOn: $shareLists)
            } footer: {
                Text("Tus amigos ven qué estás leyendo, qué querés leer y qué leíste. Tus comentarios y puntajes los ven siempre.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView() } else { Text("Guardar") }
                }
                .disabled(saving || !community.hasProfileV2)
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.magenta)
                }
            }
        }
        .tint(Theme.magenta)
        .navigationTitle("Editar perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await community.loadMe()
            displayName = community.me?.displayName ?? ""
            bio = community.me?.bio ?? ""
            avatar = community.me?.avatar ?? ""
            shareLists = community.me?.shareLists ?? true
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        do {
            try await community.updateProfile(displayName: String(displayName.prefix(40)),
                                              bio: String(bio.prefix(200)),
                                              avatar: avatar, shareLists: shareLists)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Tarjeta en la pestaña Perfil

struct ProfileCommunityCard: View {
    private var community: Community { Community.shared }

    var body: some View {
        if community.isLoggedIn, let me = community.me {
            NavigationLink(value: CommunityRoute.editProfile) {
                HStack(spacing: 12) {
                    AvatarView(profile: me, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(me.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                        Text("@\(me.username) · \(community.friends.count) \(community.friends.count == 1 ? "amigo" : "amigos")")
                            .font(.caption).foregroundStyle(Theme.ink2)
                        if let bio = me.bio, !bio.isEmpty {
                            Text(bio).font(.caption).foregroundStyle(Theme.ink).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Editar perfil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.magenta)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .task {
                await community.loadMe()
                await community.loadFriends()
            }
        } else {
            Text("Entrá a la pestaña Comunidad para tener tu perfil y ver lo que comentan tus amigos.")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 8)
        }
    }
}
