import SwiftUI
import UIKit

// "Revisar conexión": hace unas consultas de prueba a Metron y Comic Vine
// y muestra qué responde cada uno, para entender por qué no aparecen lanzamientos.
// El texto se puede copiar y pegar en el chat. Nunca muestra la clave ni la contraseña.

struct DiagnosticsView: View {
    @State private var report = ""
    @State private var running = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hace algunas consultas de prueba y muestra qué responde cada servicio. Tu clave y tu contraseña no aparecen en el texto.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)

                HStack(spacing: 10) {
                    Button(running ? "Probando…" : "Probar de nuevo") {
                        Task { await run() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .disabled(running)

                    Button(copied ? "¡Copiado!" : "Copiar todo") {
                        UIPasteboard.general.string = report
                        copied = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(report.isEmpty || running)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button("Probar géneros y temas") {
                        Task { await runGenres() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.magenta)
                    .disabled(running)
                    Text("Busca qué temas tiene Comic Vine (zombis, vampiros, terror…) y qué géneros tienen las series en Metron. Hace unas 30 consultas y tarda alrededor de un minuto.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }

                if running {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                }

                Text(report.isEmpty ? " " : report)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }
            .padding(18)
        }
        .background(Theme.paper)
        .task { if report.isEmpty { await run() } }
    }

    // MARK: Pruebas

    private func run() async {
        running = true
        copied = false
        var lines: [String] = []
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        lines.append("Cómic Unlimited \(version)")
        lines.append("Fecha del iPhone: \(day(Date()))")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        let wednesday = nextWednesday(from: today)

        // Metron
        lines.append("")
        lines.append("=== METRON ===")
        // Primero, ¿se llega a metron.cloud? (sin cuenta, pedidos livianos)
        lines.append(await plain("A) Página de Metron (sin cuenta)", "https://metron.cloud/"))
        lines.append(await plain("B) API de Metron (sin cuenta)", "https://metron.cloud/api/"))
        if MetronAccount.isSet {
            lines.append(await metron("C) Con tu cuenta, consulta liviana", path: "publisher/", ["name": "marvel"]))
            lines.append(await metron("D) Un solo día (\(day(wednesday)))", ["store_date": day(wednesday)]))
            lines.append(await metron("E) Esta semana", [
                "store_date_range_after": day(today),
                "store_date_range_before": day(weekEnd),
            ]))
        } else {
            lines.append("No hay cuenta de Metron cargada.")
        }

        // Comic Vine
        lines.append("")
        lines.append("=== COMIC VINE ===")
        if !ComicVineKey.current.isEmpty {
            lines.append(await comicVine("1) Miércoles \(day(wednesday))", [
                "filter": "store_date:\(day(wednesday))",
                "field_list": "name,issue_number,store_date,volume",
                "limit": "5",
            ]))
            lines.append(await comicVine("2) Rango de esta semana", [
                "filter": "store_date:\(day(today))|\(day(weekEnd))",
                "field_list": "name,issue_number,store_date,volume",
                "limit": "5",
            ]))
            lines.append(await comicVine("3) Fechas más lejanas cargadas", [
                "sort": "store_date:desc",
                "field_list": "name,issue_number,store_date,volume",
                "limit": "5",
            ]))
            // Anunciados: los que tienen fecha de tapa en los próximos meses (aunque no tengan fecha de venta).
            let in1 = calendar.date(byAdding: .month, value: 1, to: today) ?? today
            let in3 = calendar.date(byAdding: .month, value: 3, to: today) ?? today
            lines.append(await comicVine("4) Anunciados (fecha de tapa \(day(in1)) a \(day(in3)))", [
                "filter": "cover_date:\(day(in1))|\(day(in3))",
                "sort": "cover_date:asc",
                "field_list": "name,issue_number,store_date,cover_date,volume",
                "limit": "8",
            ]))
        } else {
            lines.append("No hay clave de Comic Vine cargada.")
        }

        report = lines.joined(separator: "\n")
        running = false
    }

    // MARK: Prueba de géneros y temas

    /// Qué datos de género hay: los "temas" (concepts) de Comic Vine y los géneros de las series en Metron.
    private func runGenres() async {
        running = true
        copied = false
        report = ""
        var lines: [String] = []
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        lines.append("Cómic Unlimited \(version) · prueba de géneros y temas")
        lines.append("Fecha del iPhone: \(day(Date()))")

        // Comic Vine: no tiene géneros, pero sí "temas" (concepts) unidos a series y números.
        lines.append("")
        lines.append("=== COMIC VINE: TEMAS ===")
        if ComicVineKey.current.isEmpty {
            lines.append("No hay clave de Comic Vine cargada.")
        } else {
            let top = await cvGet("concepts/", [
                "sort": "count_of_isssue_appearances:desc",
                "field_list": "id,name,count_of_isssue_appearances",
                "limit": "40",
            ])
            lines.append("")
            lines.append("T1) Los 40 temas que aparecen en más números")
            lines += describe(top) { results in
                results.map { "- \($0["name"] ?? "?") · \($0["count_of_isssue_appearances"] ?? "?") números · id \($0["id"] ?? "?")" }
            }

            let terms = ["horror", "zombie", "vampire", "superhero", "science fiction", "fantasy",
                         "crime", "mystery", "western", "war", "romance", "humor", "magic", "space"]
            var detailFor: [(term: String, id: Int)] = []
            for (i, term) in terms.enumerated() {
                let found = await cvGet("search/", [
                    "resources": "concept",
                    "query": term,
                    "field_list": "id,name,count_of_isssue_appearances",
                    "limit": "3",
                ])
                lines.append("")
                lines.append("T\(i + 2)) Buscar el tema \"\(term)\"")
                lines += describe(found) { results in
                    results.map { "- \($0["name"] ?? "?") · \($0["count_of_isssue_appearances"] ?? "?") números · id \($0["id"] ?? "?")" }
                }
                if ["horror", "zombie", "superhero"].contains(term),
                   let first = (found.json?["results"] as? [[String: Any]])?.first,
                   let id = first["id"] as? Int {
                    detailFor.append((term: term, id: id))
                }
            }

            // ¿Cuántas series trae cada tema? (de esto saldría una fila)
            for item in detailFor {
                let detail = await cvGet("concept/4015-\(item.id)/", ["field_list": "name,volume_credits"])
                lines.append("")
                lines.append("Series del tema \"\(item.term)\" (id \(item.id))")
                if let result = detail.json?["results"] as? [String: Any],
                   let volumes = result["volume_credits"] as? [[String: Any]] {
                    lines.append("Tema: \(result["name"] ?? "?") · series en total: \(volumes.count)")
                    lines += volumes.prefix(10).map { "- \($0["name"] ?? "?")" }
                } else {
                    lines += describe(detail) { _ in [] }
                }
            }
        }

        // Metron: los géneros están en la ficha de cada serie. Probamos con series de esta semana.
        lines.append("")
        lines.append("=== METRON: GÉNEROS DE SERIES ===")
        if !MetronAccount.isSet {
            lines.append("No hay cuenta de Metron cargada.")
        } else {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let from = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let to = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let week = await metronGet("issue/", ["store_date_range_after": day(from), "store_date_range_before": day(to)])
            var picked: [(id: Int, name: String)] = []
            for item in (week.json?["results"] as? [[String: Any]]) ?? [] {
                guard let series = item["series"] as? [String: Any], let id = series["id"] as? Int,
                      !picked.contains(where: { $0.id == id }) else { continue }
                picked.append((id: id, name: series["name"] as? String ?? "?"))
                if picked.count == 10 { break }
            }
            if picked.isEmpty {
                lines.append("")
                lines.append("Cómics de la semana")
                lines += describe(week) { _ in [] }
            }
            var withGenres = 0
            var seen: [String: Int] = [:]
            for series in picked {
                try? await Task.sleep(for: .milliseconds(3500))   // límite de Metron: 20 por minuto
                let detail = await metronGet("series/\(series.id)/", [:])
                let genres = ((detail.json?["genres"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
                let publisher = (detail.json?["publisher"] as? [String: Any])?["name"] as? String ?? "?"
                let year = detail.json?["year_began"] ?? "?"
                if !genres.isEmpty { withGenres += 1 }
                for g in genres { seen[g, default: 0] += 1 }
                if let error = detail.error {
                    lines.append("- \(series.name): error (\(error))")
                } else {
                    lines.append("- \(series.name) (\(year), \(publisher)): " + (genres.isEmpty ? "sin géneros" : genres.joined(separator: ", ")))
                }
            }
            if !picked.isEmpty {
                lines.append("Con algún género: \(withGenres) de \(picked.count) series")
                if !seen.isEmpty {
                    lines.append("Géneros vistos: " + seen.sorted { $0.value > $1.value }.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
                }
            }
        }

        report = lines.joined(separator: "\n")
        running = false
    }

    private struct Probe {
        var code = 0
        var json: [String: Any]?
        var error: String?
        var seconds = 0.0
    }

    private func cvGet(_ resource: String, _ params: [String: String]) async -> Probe {
        try? await Task.sleep(for: .milliseconds(700))   // sin apurar a Comic Vine
        var components = URLComponents(string: "https://comicvine.gamespot.com/api/\(resource)")!
        components.queryItems = [URLQueryItem(name: "api_key", value: ComicVineKey.current),
                                 URLQueryItem(name: "format", value: "json")]
            + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return await fetch(URLRequest(url: components.url!))
    }

    private func metronGet(_ path: String, _ params: [String: String]) async -> Probe {
        var components = URLComponents(string: "https://metron.cloud/api/\(path)")!
        if !params.isEmpty {
            components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        let login = Data("\(MetronAccount.user):\(MetronAccount.password)".utf8).base64EncodedString()
        request.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return await fetch(request)
    }

    private func fetch(_ original: URLRequest) async -> Probe {
        var request = original
        request.timeoutInterval = 30
        request.setValue("ComicUnlimited/0.4 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")
        let start = Date()
        var probe = Probe()
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            probe.code = (response as? HTTPURLResponse)?.statusCode ?? 0
            probe.json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if !(200..<300).contains(probe.code) { probe.error = "código HTTP \(probe.code)" }
        } catch {
            probe.error = error.localizedDescription
        }
        probe.seconds = Date().timeIntervalSince(start)
        return probe
    }

    /// Resume una respuesta de Comic Vine: código, estado, total y la lista de resultados.
    private func describe(_ probe: Probe, _ format: ([[String: Any]]) -> [String]) -> [String] {
        var out = [String(format: "Código HTTP: %ld (tardó %.1f s)", probe.code, probe.seconds)]
        if let error = probe.error, probe.json == nil { out.append("Error: \(error)") }
        if let status = probe.json?["error"] as? String, status != "OK" { out.append("Estado: \(status)") }
        if let total = probe.json?["number_of_total_results"] { out.append("Total: \(total)") }
        if let results = probe.json?["results"] as? [[String: Any]] {
            out += format(results)
        }
        if let detail = probe.json?["detail"] { out.append("Mensaje: \(detail)") }
        return out
    }

    /// Pedido simple, sin cuenta: solo para saber si se llega al sitio.
    private func plain(_ title: String, _ link: String) async -> String {
        await probe(title, URLRequest(url: URL(string: link)!), shownURL: link) { json in
            json["detail"].map { ["Mensaje: \($0)"] } ?? []
        }
    }

    private func metron(_ title: String, path: String = "issue/", _ params: [String: String]) async -> String {
        var components = URLComponents(string: "https://metron.cloud/api/\(path)")!
        if !params.isEmpty {
            components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        let login = Data("\(MetronAccount.user):\(MetronAccount.password)".utf8).base64EncodedString()
        request.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return await probe(title, request, shownURL: components.url!.absoluteString) { json in
            var out: [String] = []
            if let count = json["count"] { out.append("Total: \(count)") }
            if let results = json["results"] as? [[String: Any]] {
                for item in results.prefix(3) {
                    let name = item["issue"] ?? item["name"] ?? "?"
                    out.append("- \(name) | salida: \(item["store_date"] ?? "-")")
                }
            }
            if let detail = json["detail"] { out.append("Mensaje: \(detail)") }
            return out
        }
    }

    private func comicVine(_ title: String, _ params: [String: String]) async -> String {
        var components = URLComponents(string: "https://comicvine.gamespot.com/api/issues/")!
        var items = [URLQueryItem(name: "format", value: "json")]
        items += params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        let shown = components.url!.absoluteString
        components.queryItems = [URLQueryItem(name: "api_key", value: ComicVineKey.current)] + items
        return await probe(title, URLRequest(url: components.url!), shownURL: shown + "&api_key=(oculta)") { json in
            var out: [String] = []
            if let error = json["error"] { out.append("Estado: \(error)") }
            if let count = json["number_of_total_results"] { out.append("Total: \(count)") }
            if let results = json["results"] as? [[String: Any]] {
                for item in results.prefix(5) {
                    let series = (item["volume"] as? [String: Any])?["name"] ?? "?"
                    out.append("- \(series) #\(item["issue_number"] ?? "?") | salida: \(item["store_date"] ?? "sin fecha") | tapa: \(item["cover_date"] ?? "-")")
                }
            }
            return out
        }
    }

    /// Hace el pedido y resume la respuesta.
    private func probe(_ title: String, _ original: URLRequest, shownURL: String,
                       summarize: ([String: Any]) -> [String]) async -> String {
        var request = original
        request.timeoutInterval = 30
        request.setValue("ComicUnlimited/0.4 (app personal, uso no comercial)", forHTTPHeaderField: "User-Agent")
        var out = ["", title, "Pedido: \(shownURL)"]
        let start = Date()
        func elapsed() -> String { String(format: "%.1f s", Date().timeIntervalSince(start)) }
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            out.append("Código HTTP: \(code) (tardó \(elapsed()))")
            if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                out += summarize(json)
            } else {
                let text = String(decoding: data.prefix(160), as: UTF8.self)
                    .replacingOccurrences(of: "\n", with: " ")
                out.append("Respuesta (no es JSON): \(text)")
            }
        } catch {
            let ns = error as NSError
            out.append("Error de conexión: \(error.localizedDescription) [código \(ns.code), tardó \(elapsed())]")
        }
        return out.joined(separator: "\n")
    }

    // MARK: Fechas

    private func day(_ date: Date) -> String {
        ComicVineClient.dayFormatter.string(from: date)
    }

    private func nextWednesday(from date: Date) -> Date {
        let calendar = Calendar.current
        var d = date
        while calendar.component(.weekday, from: d) != 4 {
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }
}
