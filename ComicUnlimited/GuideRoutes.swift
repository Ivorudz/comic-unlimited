import SwiftUI

// Rutas de lectura de la guía "¿No sabés por dónde empezar a leer?" (StartGuide.swift).
// Son información, como el catálogo de una comiquería: nombre de cada etapa, series y números
// (los textos son propios). Cada tomo dice de qué serie de Comic Vine es (nombre y año en que empezó)
// y qué números trae, para buscar su ficha y para contar los que ya leíste.

struct GuideBook: Identifiable, Hashable {
    /// Lo que se muestra (por ejemplo "La fuga").
    let title: String
    /// Serie como figura en Comic Vine, y año en que empezó.
    let series: String
    let year: Int
    /// Números que trae. `last` vacío = serie que sigue saliendo.
    let first: Double
    let last: Double?
    var note: String? = nil

    var id: String { "\(series)|\(year)|\(first)" }
    var issueCount: Int? { last.map { Int($0 - first) + 1 } }

    var numbersText: String {
        func n(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }
        guard let last else { return "#\(n(first)) en adelante" }
        return first == last ? "#\(n(first))" : "#\(n(first))–\(n(last))"
    }
}

struct GuideStage: Identifiable {
    let id: String
    let title: String
    let years: String
    let text: String
    let books: [GuideBook]
    /// Buen lugar para empezar.
    var start = false
}

struct GuideRoute: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let stages: [GuideStage]
}

private func book(_ title: String, _ series: String, _ year: Int, _ first: Double, _ last: Double?,
                  note: String? = nil) -> GuideBook {
    GuideBook(title: title, series: series, year: year, first: first, last: last, note: note)
}

enum GuideRoutes {
    static let all: [GuideRoute] = [avengers, xmen, spiderMan, batman, justiceLeague]

    static func route(_ id: String) -> GuideRoute? { all.first { $0.id == id } }

    // MARK: Avengers

    static let avengers = GuideRoute(
        id: "avengers", title: "Avengers", subtitle: "Marvel · los Vengadores de los clásicos a hoy",
        icon: "shield.lefthalf.filled", color: Color(hex: 0x2F6FDB), stages: [
        GuideStage(id: "av-clasicos", title: "Los clásicos (opcional)", years: "1963–1999",
                   text: "Cómo nació el equipo y sus primeras grandes historias. Se pueden saltear y volver después.",
                   books: [
            book("Los primeros Vengadores", "The Avengers", 1963, 1, 8),
            book("La guerra Kree-Skrull", "The Avengers", 1963, 89, 97),
            book("Avengers Forever", "Avengers Forever", 1998, 1, 12),
        ]),
        GuideStage(id: "av-busiek", title: "Busiek y Pérez", years: "1998–2002",
                   text: "Una de las mejores etapas: todos los Vengadores clásicos juntos y aventuras enormes.",
                   books: [
            book("El regreso de los Vengadores", "Avengers", 1998, 1, 40),
            book("La dinastía Kang", "Avengers", 1998, 41, 55),
        ], start: true),
        GuideStage(id: "av-disassembled", title: "Avengers Disassembled", years: "2004",
                   text: "El final del equipo clásico. Desde acá arranca la etapa moderna de Brian Michael Bendis.",
                   books: [
            book("Vengadores desunidos", "Avengers", 1998, 500, 503),
        ], start: true),
        GuideStage(id: "av-new", title: "New Avengers", years: "2005–2006",
                   text: "Un equipo nuevo se forma después de una fuga masiva de La Balsa. Leé los tomos en este orden.",
                   books: [
            book("La fuga", "New Avengers", 2005, 1, 6),
            book("Centinela", "New Avengers", 2005, 7, 10),
            book("Secretos y mentiras", "New Avengers", 2005, 11, 15),
            book("El colectivo", "New Avengers", 2005, 16, 20),
        ]),
        GuideStage(id: "av-hom", title: "House of M", years: "2005",
                   text: "La Bruja Escarlata cambia la realidad. Evento clave para Avengers y X-Men.",
                   books: [
            book("House of M", "House of M", 2005, 1, 8),
        ]),
        GuideStage(id: "av-civilwar", title: "Civil War", years: "2006–2007",
                   text: "La ley de registro divide a los héroes: Iron Man contra el Capitán América.",
                   books: [
            book("Civil War", "Civil War", 2006, 1, 7),
            book("New Avengers en Civil War", "New Avengers", 2005, 21, 25),
        ]),
        GuideStage(id: "av-postcw", title: "Después de Civil War", years: "2007–2008",
                   text: "Dos equipos: los Nuevos Vengadores en la clandestinidad y los Poderosos Vengadores del gobierno.",
                   books: [
            book("Revolución y La confianza", "New Avengers", 2005, 26, 37),
            book("Mighty Avengers", "Mighty Avengers", 2007, 1, 11),
        ]),
        GuideStage(id: "av-si", title: "Secret Invasion", years: "2008",
                   text: "Los Skrulls estaban infiltrados entre los héroes. Todo lo anterior explota acá.",
                   books: [
            book("Secret Invasion", "Secret Invasion", 2008, 1, 8),
            book("New Avengers en Secret Invasion", "New Avengers", 2005, 38, 47),
        ]),
        GuideStage(id: "av-darkreign", title: "Dark Reign", years: "2009",
                   text: "Norman Osborn queda al mando y arma sus propios Vengadores con villanos.",
                   books: [
            book("Dark Avengers", "Dark Avengers", 2009, 1, 16),
            book("New Avengers en Dark Reign", "New Avengers", 2005, 48, 60),
        ]),
        GuideStage(id: "av-siege", title: "Siege", years: "2010",
                   text: "El asedio a Asgard cierra toda la etapa que empezó con Disassembled.",
                   books: [
            book("Siege", "Siege", 2010, 1, 4),
            book("New Avengers: el final", "New Avengers", 2005, 61, 64),
        ]),
        GuideStage(id: "av-heroic", title: "La Era Heroica", years: "2010–2012",
                   text: "Los héroes vuelven a la luz. Avengers y New Avengers empiezan de nuevo desde el #1.",
                   books: [
            book("Avengers (Era Heroica)", "Avengers", 2010, 1, 34),
            book("New Avengers (Era Heroica)", "New Avengers", 2010, 1, 34),
            book("Avengers vs. X-Men", "Avengers vs. X-Men", 2012, 0, 12),
        ]),
        GuideStage(id: "av-hickman", title: "Jonathan Hickman", years: "2012–2015",
                   text: "Una sola historia gigante, planeada de punta a punta, que termina en Secret Wars.",
                   books: [
            book("Avengers", "Avengers", 2012, 1, 44),
            book("New Avengers", "New Avengers", 2013, 1, 33),
            book("Infinity", "Infinity", 2013, 1, 6),
            book("Secret Wars", "Secret Wars", 2015, 1, 9),
        ], start: true),
        GuideStage(id: "av-aaron", title: "Jason Aaron", years: "2018–2023",
                   text: "Un equipo nuevo, con los Vengadores de hace un millón de años. Buen punto de entrada.",
                   books: [
            book("Avengers", "Avengers", 2018, 1, 66),
        ], start: true),
        GuideStage(id: "av-hoy", title: "Hoy", years: "2023–",
                   text: "La etapa actual, de Jed MacKay.",
                   books: [
            book("Avengers", "Avengers", 2023, 1, nil),
        ], start: true),
    ])

    // MARK: X-Men

    static let xmen = GuideRoute(
        id: "xmen", title: "X-Men", subtitle: "Marvel · los mutantes, de Claremont a Krakoa",
        icon: "xmark.shield.fill", color: Color(hex: 0xE0A100), stages: [
        GuideStage(id: "xm-nuevos", title: "Los nuevos X-Men", years: "1975–1979",
                   text: "Llega el equipo más famoso: Tormenta, Rondador Nocturno, Coloso y Wolverine.",
                   books: [
            book("Giant-Size X-Men", "Giant-Size X-Men", 1975, 1, 1),
            book("Los primeros años de Claremont", "Uncanny X-Men", 1963, 94, 128),
        ], start: true),
        GuideStage(id: "xm-fenix", title: "La saga de Fénix Oscura", years: "1980–1981",
                   text: "La historia más famosa de los X-Men, y justo después, Días del futuro pasado.",
                   books: [
            book("La saga de Fénix Oscura", "Uncanny X-Men", 1963, 129, 138),
            book("Días del futuro pasado", "Uncanny X-Men", 1963, 141, 142),
        ]),
        GuideStage(id: "xm-dios", title: "Dios ama, el hombre mata", years: "1982",
                   text: "Una novela gráfica sobre el odio a los mutantes. Se lee sola.",
                   books: [
            book("Dios ama, el hombre mata", "Marvel Graphic Novel", 1982, 5, 5),
        ]),
        GuideStage(id: "xm-morrison", title: "New X-Men de Grant Morrison", years: "2001–2004",
                   text: "Una etapa moderna y muy distinta, con la escuela de mutantes en el centro.",
                   books: [
            book("New X-Men", "New X-Men", 2001, 114, 154),
        ], start: true),
        GuideStage(id: "xm-astonishing", title: "Astonishing X-Men", years: "2004–2008",
                   text: "Joss Whedon y John Cassaday: acción, humor y un equipo clásico. Ideal para empezar.",
                   books: [
            book("Astonishing X-Men", "Astonishing X-Men", 2004, 1, 24),
        ], start: true),
        GuideStage(id: "xm-hom", title: "House of M y después", years: "2005–2008",
                   text: "Casi todos los mutantes pierden sus poderes. Después llega el primer bebé mutante.",
                   books: [
            book("House of M", "House of M", 2005, 1, 8),
            book("Messiah Complex", "X-Men: Messiah Complex", 2007, 1, 1,
                 note: "La historia sigue en varias series: buscá su orden de lectura en Biblioteca → Listas."),
        ]),
        GuideStage(id: "xm-cisma", title: "Cisma", years: "2011",
                   text: "Cíclope y Wolverine se separan y los mutantes quedan divididos.",
                   books: [
            book("Cisma", "X-Men: Schism", 2011, 1, 5),
            book("Avengers vs. X-Men", "Avengers vs. X-Men", 2012, 0, 12),
        ]),
        GuideStage(id: "xm-krakoa", title: "La era de Krakoa", years: "2019–2024",
                   text: "Jonathan Hickman reinventa todo: los mutantes fundan su propia nación. Gran punto de entrada.",
                   books: [
            book("House of X", "House of X", 2019, 1, 6, note: "Se lee intercalado con Powers of X (1 y 1, 2 y 2…)."),
            book("Powers of X", "Powers of X", 2019, 1, 6),
            book("X-Men", "X-Men", 2019, 1, 21),
        ], start: true),
        GuideStage(id: "xm-hoy", title: "Hoy", years: "2024–",
                   text: "Después de Krakoa, un nuevo comienzo con Jed MacKay.",
                   books: [
            book("X-Men", "X-Men", 2024, 1, nil),
        ], start: true),
    ])

    // MARK: Spider-Man

    static let spiderMan = GuideRoute(
        id: "spiderman", title: "Spider-Man", subtitle: "Marvel · el Hombre Araña de 1962 a hoy",
        icon: "circle.hexagongrid.fill", color: Color(hex: 0xD62828), stages: [
        GuideStage(id: "sm-origen", title: "Los comienzos", years: "1962–1966",
                   text: "Stan Lee y Steve Ditko: el origen y los villanos que todos conocen.",
                   books: [
            book("El origen", "Amazing Fantasy", 1962, 15, 15),
            book("Lee y Ditko", "The Amazing Spider-Man", 1963, 1, 38),
        ]),
        GuideStage(id: "sm-gwen", title: "La muerte de Gwen Stacy", years: "1973",
                   text: "Una de las historias más importantes de la historieta de superhéroes.",
                   books: [
            book("La noche en que murió Gwen Stacy", "The Amazing Spider-Man", 1963, 121, 122),
        ]),
        GuideStage(id: "sm-kraven", title: "La última cacería de Kraven", years: "1987",
                   text: "Una historia oscura y cerrada.",
                   books: [
            book("La última cacería de Kraven", "The Amazing Spider-Man", 1963, 293, 294,
                 note: "Sigue en Web of Spider-Man #31–32 y Spectacular Spider-Man #131–132."),
        ]),
        GuideStage(id: "sm-ultimate", title: "Ultimate Spider-Man", years: "2000–2011",
                   text: "Peter Parker desde cero, sin nada previo. El mejor lugar para empezar si sos nuevo.",
                   books: [
            book("Ultimate Spider-Man", "Ultimate Spider-Man", 2000, 1, 111),
        ], start: true),
        GuideStage(id: "sm-jms", title: "J. Michael Straczynski", years: "2001–2007",
                   text: "Peter como profesor y una mirada nueva sobre sus poderes. Termina con Civil War.",
                   books: [
            book("Straczynski, parte 1", "The Amazing Spider-Man", 1999, 30, 58),
            book("Straczynski, parte 2", "The Amazing Spider-Man", 1999, 500, 545),
        ]),
        GuideStage(id: "sm-bnd", title: "Brand New Day", years: "2008–2010",
                   text: "Un nuevo comienzo con historias más clásicas y livianas.",
                   books: [
            book("Brand New Day", "The Amazing Spider-Man", 1999, 546, 600),
        ], start: true),
        GuideStage(id: "sm-slott", title: "Dan Slott", years: "2010–2014",
                   text: "Peter en su mejor momento… hasta que llega el Superior Spider-Man.",
                   books: [
            book("Big Time", "The Amazing Spider-Man", 1999, 648, 700),
            book("Superior Spider-Man", "Superior Spider-Man", 2013, 1, 31),
            book("Spider-Verse", "The Amazing Spider-Man", 2014, 9, 15),
        ]),
        GuideStage(id: "sm-spencer", title: "Nick Spencer", years: "2018–2021",
                   text: "Peter vuelve a lo básico, con humor y viejos conocidos.",
                   books: [
            book("Amazing Spider-Man", "The Amazing Spider-Man", 2018, 1, 74),
        ], start: true),
        GuideStage(id: "sm-hoy", title: "Hoy", years: "2022–",
                   text: "La serie principal actual y el nuevo Ultimate Spider-Man, ideal para empezar.",
                   books: [
            book("Amazing Spider-Man", "The Amazing Spider-Man", 2022, 1, nil),
            book("Ultimate Spider-Man (nuevo)", "Ultimate Spider-Man", 2024, 1, nil),
        ], start: true),
    ])

    // MARK: Batman

    static let batman = GuideRoute(
        id: "batman", title: "Batman", subtitle: "DC · el Caballero Oscuro, de Año Uno a hoy",
        icon: "moon.stars.fill", color: Color(hex: 0x3A3F4B), stages: [
        GuideStage(id: "bm-anio", title: "Año Uno", years: "1987",
                   text: "El primer año de Batman y de Jim Gordon. El mejor comienzo.",
                   books: [
            book("Batman: Año Uno", "Batman", 1940, 404, 407),
        ], start: true),
        GuideStage(id: "bm-halloween", title: "El largo Halloween", years: "1996–1997",
                   text: "Un asesino que ataca en cada feriado. Misterio con todos los villanos clásicos.",
                   books: [
            book("El largo Halloween", "Batman: The Long Halloween", 1996, 1, 13),
        ]),
        GuideStage(id: "bm-dkr", title: "El regreso del Caballero Oscuro", years: "1986",
                   text: "Un Batman viejo vuelve a la acción. Un clásico que cambió todo.",
                   books: [
            book("El regreso del Caballero Oscuro", "Batman: The Dark Knight Returns", 1986, 1, 4),
        ]),
        GuideStage(id: "bm-muerte", title: "Una muerte en la familia", years: "1988",
                   text: "El Joker contra el segundo Robin.",
                   books: [
            book("Una muerte en la familia", "Batman", 1940, 426, 429),
        ]),
        GuideStage(id: "bm-caida", title: "La caída del murciélago", years: "1993",
                   text: "Bane quiebra a Batman.",
                   books: [
            book("Knightfall", "Batman", 1940, 491, 500, note: "Se cruza con Detective Comics: buscá su orden de lectura."),
        ]),
        GuideStage(id: "bm-silencio", title: "Silencio", years: "2002–2003",
                   text: "Un villano misterioso usa a toda la galería de enemigos de Batman.",
                   books: [
            book("Silencio", "Batman", 1940, 608, 619),
        ]),
        GuideStage(id: "bm-morrison", title: "Grant Morrison", years: "2006–2013",
                   text: "Una saga enorme: el hijo de Batman, Batman R.I.P. y Batman Incorporated.",
                   books: [
            book("Batman e hijo hasta R.I.P.", "Batman", 1940, 655, 683),
            book("Batman y Robin", "Batman and Robin", 2009, 1, 16),
            book("Batman Incorporated", "Batman Incorporated", 2012, 1, 13),
        ]),
        GuideStage(id: "bm-snyder", title: "Scott Snyder (Los Nuevos 52)", years: "2011–2016",
                   text: "Empieza con La Corte de los Búhos. Un gran punto de entrada moderno.",
                   books: [
            book("Batman", "Batman", 2011, 1, 52),
        ], start: true),
        GuideStage(id: "bm-king", title: "Tom King", years: "2016–2019",
                   text: "Batman y Gatúbela, en una etapa larga y muy personal.",
                   books: [
            book("Batman", "Batman", 2016, 1, 85),
        ]),
        GuideStage(id: "bm-hoy", title: "Hoy", years: "2024–",
                   text: "Absolute Batman: un Batman nuevo, desde cero.",
                   books: [
            book("Absolute Batman", "Absolute Batman", 2024, 1, nil),
        ], start: true),
    ])

    // MARK: Liga de la Justicia y DC

    static let justiceLeague = GuideRoute(
        id: "dc", title: "Liga de la Justicia y DC", subtitle: "DC · el equipo y los grandes eventos",
        icon: "bolt.shield.fill", color: Color(hex: 0x0A8F5A), stages: [
        GuideStage(id: "dc-crisis", title: "Crisis en Tierras Infinitas", years: "1985–1986",
                   text: "El evento que ordenó todo el universo de DC.",
                   books: [
            book("Crisis en Tierras Infinitas", "Crisis on Infinite Earths", 1985, 1, 12),
        ]),
        GuideStage(id: "dc-jla", title: "JLA de Grant Morrison", years: "1997–2000",
                   text: "Los siete grandes juntos de nuevo, con amenazas gigantes. Ideal para empezar.",
                   books: [
            book("JLA", "JLA", 1997, 1, 41),
        ], start: true),
        GuideStage(id: "dc-identity", title: "Crisis de identidad", years: "2004",
                   text: "Un misterio policial que destapa secretos de la Liga.",
                   books: [
            book("Crisis de identidad", "Identity Crisis", 2004, 1, 7),
        ]),
        GuideStage(id: "dc-infinite", title: "Crisis infinita y 52", years: "2005–2007",
                   text: "Un evento grande y un año contado semana a semana.",
                   books: [
            book("Crisis infinita", "Infinite Crisis", 2005, 1, 7),
            book("52", "52", 2006, 1, 52),
        ]),
        GuideStage(id: "dc-final", title: "Final Crisis", years: "2008",
                   text: "Darkseid gana. El cierre de toda una época.",
                   books: [
            book("Final Crisis", "Final Crisis", 2008, 1, 7),
        ]),
        GuideStage(id: "dc-flashpoint", title: "Flashpoint", years: "2011",
                   text: "Flash cambia la historia y nace un universo nuevo.",
                   books: [
            book("Flashpoint", "Flashpoint", 2011, 1, 5),
        ]),
        GuideStage(id: "dc-n52", title: "Los Nuevos 52", years: "2011–2016",
                   text: "La Liga se forma de nuevo desde cero. Muy buen comienzo.",
                   books: [
            book("Justice League", "Justice League", 2011, 1, 52),
        ], start: true),
        GuideStage(id: "dc-rebirth", title: "Renacimiento", years: "2016–2019",
                   text: "DC recupera su historia y se cruza con Watchmen.",
                   books: [
            book("DC Universe: Rebirth", "DC Universe: Rebirth", 2016, 1, 1),
            book("Doomsday Clock", "Doomsday Clock", 2017, 1, 12),
            book("Dark Nights: Metal", "Dark Nights: Metal", 2017, 1, 6),
        ]),
        GuideStage(id: "dc-hoy", title: "Hoy: el universo Absolute", years: "2024–",
                   text: "Versiones nuevas de los héroes, desde cero.",
                   books: [
            book("Absolute Superman", "Absolute Superman", 2024, 1, nil),
            book("Absolute Wonder Woman", "Absolute Wonder Woman", 2024, 1, nil),
        ], start: true),
    ])
}
