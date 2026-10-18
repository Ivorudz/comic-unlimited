import Foundation

// Un cómic de ejemplo. Todas son obras inventadas para la app (sin derechos de autor de terceros).
struct Comic: Identifiable, Hashable {
    enum Source: String {
        case editorial, indie

        var label: String {
            switch self {
            case .editorial: return "Editorial"
            case .indie: return "Independiente"
            }
        }
    }

    let id: String
    let title: String
    let issue: String
    let author: String
    let publisher: String?
    let source: Source
    let genre: String
    /// Tres colores en hexadecimal: fondo, color principal y color de acento.
    let palette: [UInt32]
    let rating: Double
    let votes: Int
    let synopsis: String
    /// Qué se dibuja en cada viñeta (3 viñetas por página).
    let scenes: [String]
    /// El texto de cada viñeta. Si empieza con "—" es un globo de diálogo.
    let lines: [String]

    /// Cada página tiene 3 viñetas.
    var pageCount: Int { lines.count / 3 }

    var fullTitle: String { issue.isEmpty ? title : "\(title) \(issue)" }
}

enum Catalog {
    static let comics: [Comic] = [
        Comic(
            id: "meridiano", title: "Meridiano", issue: "#1",
            author: "Paula Kessler y Joaquín Sosa", publisher: "Faro Sur",
            source: .editorial, genre: "Ciencia ficción",
            palette: [0x2B1055, 0xD1006C, 0xFFD400], rating: 4.7, votes: 318,
            synopsis: "Una estación espacial al borde de un sol que se apaga recibe una visita que no figura en ningún mapa.",
            scenes: ["sky", "object", "duo", "figure", "sky", "close", "duo", "object", "object", "figure", "duo", "close"],
            lines: [
                "Año 2311. La estación Meridiano orbita un sol que se apaga.",
                "Quedan 214 personas a bordo.",
                "—Capitana, el motor tres no responde.",
                "—Entonces vamos con dos.",
                "Afuera, algo brilla donde no debería haber nada.",
                "—Eso no está en ningún mapa.",
                "—Lo que importa nunca estuvo en un mapa.",
                "Lanzan una sonda.",
                "La sonda vuelve. Con alguien adentro.",
                "—Hola. Llegaron tarde.",
                "—¿Tarde para qué?",
                "—Para irse.",
            ]
        ),
        Comic(
            id: "grua", title: "La grúa de Dock Sud", issue: "",
            author: "Valeria Ocampo", publisher: nil,
            source: .indie, genre: "Policial",
            palette: [0x0E2A3B, 0x00A3D9, 0xFFD400], rating: 4.6, votes: 212,
            synopsis: "En el puerto, una grúa se mueve sola de madrugada. Dos estibadores y un inspector cansado intentan averiguar por qué.",
            scenes: ["crane", "city", "duo", "sea", "object", "object", "duo", "figure", "figure", "duo", "crane", "sky"],
            lines: [
                "Tres noches seguidas, la grúa se movió sola.",
                "Nadie trabaja en el muelle después de las doce.",
                "—¿Escuchaste eso?",
                "—Es el río. Siempre es el río.",
                "Los contenedores no estaban numerados.",
                "Uno tenía una luz adentro.",
                "—Abrilo vos.",
                "—Ni loco. Llamá a Ferreyra.",
                "Ferreyra llegó con el piloto mojado y sin paraguas.",
                "—Esto no es contrabando. Es otra cosa.",
                "Arriba, la grúa giró hacia nosotros.",
                "Continuará…",
            ]
        ),
        Comic(
            id: "faro", title: "El faro de los que no duermen", issue: "",
            author: "Martín Aldao", publisher: "Faro Sur",
            source: .editorial, genre: "Terror",
            palette: [0x1B1B2F, 0xD1006C, 0xFFD400], rating: 4.5, votes: 187,
            synopsis: "Un nuevo guardián llega a un faro que no se apaga desde 1952. El anterior no se fue nunca.",
            scenes: ["tower", "tower", "duo", "duo", "sea", "sea", "duo", "figure", "sky", "tower", "figure", "tower"],
            lines: [
                "El faro de Cabo Lindo no se apaga desde 1952.",
                "Tampoco su guardián duerme.",
                "—Vengo por el puesto.",
                "—Nadie viene por el puesto. El puesto viene por vos.",
                "La primera noche conté los barcos.",
                "No pasó ninguno. Pero alguien saludó desde el agua.",
                "—¿Quién vive en la isla?",
                "—Nadie que esté vivo.",
                "La segunda noche dejé de tener sueño.",
                "La tercera, el faro empezó a hablarme.",
                "—Cuidalo bien. Ahora es tuyo.",
                "Continuará…",
            ]
        ),
        Comic(
            id: "gatos", title: "Los gatos del Abasto", issue: "",
            author: "Tomás Iriarte", publisher: nil,
            source: .indie, genre: "Humor",
            palette: [0xFFD400, 0x17191E, 0xD1006C], rating: 4.8, votes: 401,
            synopsis: "Una asamblea de gatos de barrio decide qué hacer con el vecino que pone tango a las tres de la mañana.",
            scenes: ["city", "cats", "cats", "cats", "cats", "cats", "city", "cats", "cats", "close", "figure", "cats"],
            lines: [
                "En el Abasto hay más gatos que vecinos.",
                "Y todos tienen opinión.",
                "—El del tercero volvió a poner música a las tres.",
                "—Es tango. El tango no se discute.",
                "—Yo voto por arañarle el felpudo.",
                "—Moción aprobada.",
                "Esa noche: operativo felpudo.",
                "—Silencio total.",
                "—¿Quién trajo cascabel?",
                "—…",
                "El del tercero abrió la puerta y les sirvió leche.",
                "Reunión suspendida hasta nuevo aviso.",
            ]
        ),
        Comic(
            id: "plancton", title: "Plancton", issue: "#1",
            author: "Inés Gaitán", publisher: "Marea",
            source: .editorial, genre: "Aventura",
            palette: [0x004E64, 0x00A3D9, 0xFFD400], rating: 4.4, votes: 156,
            synopsis: "A 900 metros de profundidad, una piloto de batiscafo encuentra una ciudad iluminada que no debería existir.",
            scenes: ["sea", "object", "figure", "sea", "city", "figure", "sea", "close", "close", "figure", "figure", "sea"],
            lines: [
                "A 900 metros, la luz deja de existir.",
                "Pero Ana encontró otra.",
                "—Batiscafo a superficie: estoy viendo algo.",
                "—Repetí, Ana. Se corta.",
                "Una ciudad. Bajo el agua. Encendida.",
                "—No puede ser natural.",
                "Las luces se apagaron una por una.",
                "Todas menos una, justo frente a ella.",
                "—Me está mirando.",
                "—Ana, subí ya.",
                "—No. Quiere mostrarme algo.",
                "Fin del primer número.",
            ]
        ),
        Comic(
            id: "ruta", title: "Ruta 40, kilómetro cero", issue: "",
            author: "Lucía Benítez", publisher: nil,
            source: .indie, genre: "Drama",
            palette: [0xF2C14E, 0x5A3E2B, 0x00A3D9], rating: 4.9, votes: 96,
            synopsis: "Una moto, un mapa con una sola marca y tres mil kilómetros para entender a un padre que ya no está.",
            scenes: ["object", "sky", "duo", "figure", "sky", "tree", "duo", "figure", "tree", "close", "close", "sky"],
            lines: [
                "Mi viejo me dejó una moto y un mapa.",
                "El mapa tenía una sola marca.",
                "—¿Vas a ir sola hasta allá?",
                "—Voy con él. De alguna forma.",
                "Tres mil kilómetros de ruta.",
                "Viento, guanacos, una estación de servicio cerrada.",
                "—¿Buscás a alguien?",
                "—Busco un lugar.",
                "La marca era un árbol solo en medio de la nada.",
                "Tenía tallado mi nombre.",
                "Y una fecha: el día que nací.",
                "Continuará…",
            ]
        ),
    ]

    static func comic(id: String) -> Comic? {
        comics.first { $0.id == id }
    }
}
