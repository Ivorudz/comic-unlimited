import SwiftUI

// "¿No sabés por dónde empezar a leer?" (botón grande abajo de todo en Comunidad).
// Una guía para empezar: lo básico (números, series, arcos, tomos, eventos) y recomendaciones según
// lo que te gusta. Las recomendaciones son información (título, año, autores, editorial) con textos propios;
// la portada y la ficha salen de Comic Vine: la app busca cada serie por su nombre y año la primera vez
// que se ve y guarda solo su código y el link de la portada (nunca la imagen).

struct GuidePick: Identifiable, Hashable {
    /// Nombre para buscar en Comic Vine (como figura allá).
    let query: String
    /// Nombre para mostrar (en español si se conoce así).
    let title: String
    let year: Int
    let creators: String
    let publisher: String
    /// Por qué es un buen comienzo (texto propio).
    let why: String
    var adults = false

    var id: String { "\(query)|\(year)" }
}

struct GuideSection: Identifiable {
    let id: String
    let title: String
    let intro: String
    let picks: [GuidePick]
}

enum StartGuide {
    static let sections: [GuideSection] = [
        GuideSection(id: "primeros", title: "Para tu primer cómic",
                     intro: "Historias cerradas, que se entienden sin haber leído nada antes.",
                     picks: [
            GuidePick(query: "Batman: Year One", title: "Batman: Año Uno", year: 1987,
                      creators: "Frank Miller y David Mazzucchelli", publisher: "DC",
                      why: "El primer año de Batman en Ciudad Gótica. Corto, policial y perfecto para arrancar."),
            GuidePick(query: "All Star Superman", title: "All-Star Superman", year: 2006,
                      creators: "Grant Morrison y Frank Quitely", publisher: "DC",
                      why: "Doce números que cuentan todo lo que hace grande a Superman, sin necesitar nada previo."),
            GuidePick(query: "Ms. Marvel", title: "Ms. Marvel", year: 2014,
                      creators: "G. Willow Wilson y Adrian Alphona", publisher: "Marvel",
                      why: "Kamala Khan descubre sus poderes. Divertido, cercano y muy fácil de seguir."),
            GuidePick(query: "Hawkeye", title: "Hawkeye (Ojo de Halcón)", year: 2012,
                      creators: "Matt Fraction y David Aja", publisher: "Marvel",
                      why: "Lo que hace un Vengador en sus días libres. Mucho humor y un dibujo muy original."),
            GuidePick(query: "The Unbeatable Squirrel Girl", title: "La imbatible Chica Ardilla", year: 2015,
                      creators: "Ryan North y Erica Henderson", publisher: "Marvel",
                      why: "Superhéroes en clave de comedia, para todas las edades."),
        ]),
        GuideSection(id: "heroes", title: "Superhéroes",
                     intro: "Puntos de entrada a los personajes más conocidos.",
                     picks: [
            GuidePick(query: "Ultimate Spider-Man", title: "Ultimate Spider-Man", year: 2000,
                      creators: "Brian Michael Bendis y Mark Bagley", publisher: "Marvel",
                      why: "Peter Parker desde cero, en el colegio. Una serie larga para engancharse."),
            GuidePick(query: "Batman: The Long Halloween", title: "Batman: El largo Halloween", year: 1996,
                      creators: "Jeph Loeb y Tim Sale", publisher: "DC",
                      why: "Un asesino que ataca en cada feriado durante un año. Misterio con los villanos clásicos."),
            GuidePick(query: "Mister Miracle", title: "Mister Miracle", year: 2017,
                      creators: "Tom King y Mitch Gerads", publisher: "DC",
                      why: "Un superhéroe que escapa de todo, menos de sus problemas. Distinto y muy premiado."),
            GuidePick(query: "Daredevil", title: "Daredevil", year: 2011,
                      creators: "Mark Waid y Paolo Rivera", publisher: "Marvel",
                      why: "El abogado ciego vuelve con aventuras luminosas. Se lee solo, sin saber nada antes."),
        ]),
        GuideSection(id: "terror", title: "Terror",
                     intro: "Para leer con la luz prendida.",
                     picks: [
            GuidePick(query: "Locke & Key: Welcome to Lovecraft", title: "Locke & Key", year: 2008,
                      creators: "Joe Hill y Gabriel Rodríguez", publisher: "IDW",
                      why: "Una casa llena de llaves mágicas y una familia que las descubre. Terror y aventura."),
            GuidePick(query: "Something is Killing the Children", title: "Something is Killing the Children", year: 2019,
                      creators: "James Tynion IV y Werther Dell'Edera", publisher: "BOOM! Studios",
                      why: "En un pueblo desaparecen chicos y llega una cazadora de monstruos. Atrapa enseguida."),
            GuidePick(query: "Gideon Falls", title: "Gideon Falls", year: 2018,
                      creators: "Jeff Lemire y Andrea Sorrentino", publisher: "Image",
                      why: "Un granero negro que aparece donde no debería. Misterio inquietante."),
            GuidePick(query: "Hellboy: Seed of Destruction", title: "Hellboy: Semilla de destrucción", year: 1994,
                      creators: "Mike Mignola y John Byrne", publisher: "Dark Horse",
                      why: "Un demonio que caza monstruos para los buenos. El comienzo de un clásico."),
        ]),
        GuideSection(id: "scifi", title: "Ciencia ficción",
                     intro: "Futuros, viajes y mundos raros.",
                     picks: [
            GuidePick(query: "Saga", title: "Saga", year: 2012,
                      creators: "Brian K. Vaughan y Fiona Staples", publisher: "Image",
                      why: "Una familia escapando de una guerra entre planetas. Épica y emotiva.", adults: true),
            GuidePick(query: "Paper Girls", title: "Paper Girls", year: 2015,
                      creators: "Brian K. Vaughan y Cliff Chiang", publisher: "Image",
                      why: "Cuatro chicas que reparten diarios en 1988 terminan viajando en el tiempo."),
            GuidePick(query: "Y: The Last Man", title: "Y: El último hombre", year: 2002,
                      creators: "Brian K. Vaughan y Pia Guerra", publisher: "Vertigo (DC)",
                      why: "Todos los hombres del planeta mueren de golpe, menos uno.", adults: true),
            GuidePick(query: "Descender", title: "Descender", year: 2015,
                      creators: "Jeff Lemire y Dustin Nguyen", publisher: "Image",
                      why: "Un nene robot en un universo que les tiene miedo a las máquinas. Dibujo en acuarela."),
        ]),
        GuideSection(id: "fantasia", title: "Fantasía",
                     intro: "Magia, criaturas y mundos inventados.",
                     picks: [
            GuidePick(query: "Bone", title: "Bone", year: 1991,
                      creators: "Jeff Smith", publisher: "Cartoon Books",
                      why: "Tres primos perdidos en un valle con dragones. Para todas las edades."),
            GuidePick(query: "The Sandman", title: "The Sandman", year: 1989,
                      creators: "Neil Gaiman y varios dibujantes", publisher: "DC (Vertigo)",
                      why: "El señor de los sueños y sus historias. Uno de los cómics más importantes.", adults: true),
            GuidePick(query: "Monstress", title: "Monstress", year: 2015,
                      creators: "Marjorie Liu y Sana Takeda", publisher: "Image",
                      why: "Una chica con un monstruo adentro, en un mundo en guerra. Dibujo deslumbrante.", adults: true),
        ]),
        GuideSection(id: "policial", title: "Policiales y suspenso",
                     intro: "Crímenes, mafias y misterios sin superpoderes.",
                     picks: [
            GuidePick(query: "Criminal", title: "Criminal", year: 2006,
                      creators: "Ed Brubaker y Sean Phillips", publisher: "Icon (Marvel)",
                      why: "Historias de ladrones y perdedores, cada tomo se lee por separado.", adults: true),
            GuidePick(query: "100 Bullets", title: "100 balas", year: 1999,
                      creators: "Brian Azzarello y Eduardo Risso", publisher: "Vertigo (DC)",
                      why: "Un desconocido te da un arma y 100 balas imposibles de rastrear. Dibujo de un argentino.", adults: true),
        ]),
        GuideSection(id: "clasicos", title: "Clásicos que cambiaron todo",
                     intro: "Para cuando quieras leer los que todos nombran.",
                     picks: [
            GuidePick(query: "Watchmen", title: "Watchmen", year: 1986,
                      creators: "Alan Moore y Dave Gibbons", publisher: "DC",
                      why: "Superhéroes en un mundo real y oscuro. Una historia cerrada de 12 números.", adults: true),
            GuidePick(query: "Batman: The Dark Knight Returns", title: "Batman: El regreso del Caballero Oscuro", year: 1986,
                      creators: "Frank Miller", publisher: "DC",
                      why: "Un Batman viejo que vuelve a la acción. Cambió cómo se contaban los superhéroes."),
            GuidePick(query: "El Eternauta", title: "El Eternauta", year: 1957,
                      creators: "Héctor G. Oesterheld y Francisco Solano López", publisher: "Hora Cero",
                      why: "Una nevada mortal cae sobre Buenos Aires. El gran clásico de la historieta argentina."),
            GuidePick(query: "Maus", title: "Maus", year: 1986,
                      creators: "Art Spiegelman", publisher: "Pantheon",
                      why: "La historia real del padre del autor en el Holocausto, contada con ratones y gatos."),
        ]),
        GuideSection(id: "eventos", title: "Grandes eventos",
                     intro: "Historias donde se juntan muchos personajes. Conviene leerlas con su orden de lectura.",
                     picks: [
            GuidePick(query: "Civil War", title: "Civil War", year: 2006,
                      creators: "Mark Millar y Steve McNiven", publisher: "Marvel",
                      why: "Los héroes de Marvel se dividen en dos bandos. Se entiende bastante bien sola."),
            GuidePick(query: "The Infinity Gauntlet", title: "El Guantelete del Infinito", year: 1991,
                      creators: "Jim Starlin, George Pérez y Ron Lim", publisher: "Marvel",
                      why: "Thanos junta las gemas del infinito. La historia que inspiró las películas."),
            GuidePick(query: "Crisis on Infinite Earths", title: "Crisis en Tierras Infinitas", year: 1985,
                      creators: "Marv Wolfman y George Pérez", publisher: "DC",
                      why: "El evento que reordenó todo el universo de DC."),
        ]),
    ]

    static func pick(_ id: String) -> GuidePick? {
        sections.lazy.flatMap(\.picks).first { $0.id == id }
    }

    // MARK: Ficha de Comic Vine de cada recomendación (se busca una vez y se guarda el código)

    struct Found: Codable {
        let cvID: Int
        let name: String
        let cover: String?
    }

    private static let storeKey = "startGuide.found"

    static func found(_ pick: GuidePick) -> Found? {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let all = try? JSONDecoder().decode([String: Found].self, from: data) else { return nil }
        return all[pick.id]
    }

    private static func remember(_ found: Found, for pick: GuidePick) {
        var all: [String: Found] = [:]
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([String: Found].self, from: data) { all = saved }
        all[pick.id] = found
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: storeKey) }
    }

    /// Busca la serie en Comic Vine por nombre y año (1 consulta) y guarda su código y portada.
    static func resolve(_ pick: GuidePick) async throws -> Found? {
        if let found = found(pick) { return found }
        guard !ComicVineKey.current.isEmpty else { return nil }
        let results = try await ComicVineKey.client.searchSeries(pick.query)
        guard let best = best(results, for: pick) else { return nil }
        let found = Found(cvID: best.id, name: best.name ?? pick.title, cover: best.image?.small?.absoluteString)
        remember(found, for: pick)
        return found
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// El resultado que mejor coincide: mismo nombre y año parecido.
    private static func best(_ results: [CVVolumeSummary], for pick: GuidePick) -> CVVolumeSummary? {
        let target = normalized(pick.query)
        var bestScore = 0
        var best: CVVolumeSummary?
        for result in results {
            let name = normalized(result.name ?? "")
            var score = 0
            if name == target { score += 10 } else if !name.isEmpty && (name.contains(target) || target.contains(name)) { score += 4 }
            if let year = Int(result.startYear ?? "") {
                let gap = abs(year - pick.year)
                score += gap <= 1 ? 6 : (gap <= 3 ? 2 : 0)
            }
            score += min(result.countOfIssues ?? 0, 50) / 25
            if score > bestScore { bestScore = score; best = result }
        }
        return bestScore >= 8 ? best : nil
    }
}

/// Pide a Comic Vine las fichas de a una (sin apurar el límite de consultas).
actor GuideResolver {
    static let shared = GuideResolver()

    func resolve(_ pick: GuidePick) async -> StartGuide.Found? {
        if let found = StartGuide.found(pick) { return found }
        try? await Task.sleep(for: .milliseconds(400))
        return try? await StartGuide.resolve(pick)
    }
}

// MARK: - Pantalla de la guía

struct StartGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Por dónde empezar")
                    .font(.system(size: 28, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.ink)
                    .misprint(0.6)
                    .padding(.top, 8)
                Text("No hace falta leer todo lo anterior: cualquier buen comienzo sirve. Elegí algo que te tiente y tirate de cabeza.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)

                basics

                ForEach(StartGuide.sections) { section in
                    SectionTitle(section.title)
                    Text(section.intro)
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, -6)
                        .padding(.bottom, 10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(section.picks) { pick in
                                NavigationLink(value: CommunityRoute.guidePick(pick.id)) {
                                    GuidePickCard(pick: pick)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                }

                tips

                Text("Datos y portadas: Comic Vine. Las portadas pertenecen a sus editoriales. Las recomendaciones y los textos son de Cómic Unlimited.")
                    .font(.caption2)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.paper)
        .navigationTitle("Empezar a leer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Las palabras que más se usan, explicadas.
    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lo básico").font(.headline).foregroundStyle(Theme.ink)
            term("Número (#)", "Cada revista que sale, por ejemplo Batman #1. Suelen tener unas 20 a 30 páginas.")
            term("Serie", "Todos los números de un mismo título. Cuando una serie vuelve a empezar desde el #1, se dice que es un \"volumen\" nuevo (por eso ves años al lado del nombre).")
            term("Arco", "Una historia que ocupa varios números seguidos. Empezar al principio de un arco es una buena forma de entrar.")
            term("Tomo o TPB", "Un libro que junta varios números, casi siempre un arco completo. El \"Vol. 1\" es un gran lugar para empezar.")
            term("Evento", "Una historia grande que cruza muchas series a la vez. Mejor leerla con un orden de lectura.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .padding(.top, 18)
    }

    private func term(_ name: String, _ text: String) -> some View {
        (Text(name + ": ").bold().foregroundColor(Theme.ink) + Text(text).foregroundColor(Theme.ink2))
            .font(.subheadline)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Consejos")
            tip("star", "Tocá un cómic, mirá \"De qué se trata\" y marcalo como \"Quiero leer\": así \"Para vos\" (en Inicio) te sugiere otros parecidos.")
            tip("list.number", "Para los eventos, en Biblioteca → Listas → Subir lista .cbl → Buscar en la colección, encontrás su orden de lectura.")
            tip("sparkles", "En Inicio, las filas por género te muestran más series de lo que te gusta, de todas las épocas.")
            tip("person.2", "Si algo te gustó, dejá tu comentario: tus amigos lo ven en esta pestaña.")
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.magenta).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        }
    }
}

private struct GuidePickCard: View {
    let pick: GuidePick
    @State private var found: StartGuide.Found?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RemoteCover(url: found?.cover.flatMap { URL(string: $0) })
            Text(pick.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 5)
            Text("\(String(pick.year)) · \(pick.publisher)")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Text(pick.why)
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            if pick.adults {
                Text("Para adultos")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.magenta)
            }
        }
        .frame(width: 140)
        .task(id: pick.id) { found = await GuideResolver.shared.resolve(pick) }
    }
}

/// Al tocar una recomendación: busca su serie en Comic Vine y muestra la ficha.
struct GuidePickView: View {
    let pickID: String
    @State private var found: StartGuide.Found?
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if let found {
                SeriesView(id: found.cvID, name: found.name)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let pick = StartGuide.pick(pickID) {
                        Text(pick.title).font(.title2.weight(.black)).foregroundStyle(Theme.ink)
                        Text("\(String(pick.year)) · \(pick.creators) · \(pick.publisher)")
                            .font(.subheadline).foregroundStyle(Theme.ink2)
                        Text(pick.why).font(.body).foregroundStyle(Theme.ink)
                    }
                    Text(errorText ?? "No encontré su ficha en Comic Vine. Probá buscarla con el buscador de Inicio.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paper)
            }
        }
        .task {
            guard let pick = StartGuide.pick(pickID) else { loading = false; return }
            if ComicVineKey.current.isEmpty && StartGuide.found(pick) == nil {
                errorText = "Para ver la ficha, cargá tu clave de Comic Vine en Perfil → Configuración → Cuentas de Metron y Comic Vine."
            } else {
                do { found = try await StartGuide.resolve(pick) } catch {
                    errorText = CVText.message(for: error)
                }
            }
            loading = false
        }
    }
}
