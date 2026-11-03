import SwiftUI

// Pantallas de cada ruta de la guía "Por dónde empezar":
// - Tres caminos: Esencial, + Extras (los cruces marcados como opcionales) y Con todo.
// - Dos formas de verlo: Bloques (lista por eras) o Camino (paradas con tapas en zigzag, tipo juego).
// - Punto de partida a elección ("Empezá por acá" recomendados, comienzo de cada era o cualquier parada).
// - "Seguí por acá", medallas por era, cartel de puntos y detalle de cada parada.
// Los datos y los puntos están en GuideData.swift.

/// Las paradas de una era.
struct EraSection: Identifiable {
    let id: Int
    let era: RouteEra
    let blocks: [RouteBlock]
}

struct EraCount {
    var total = 0
    var read = 0
    var complete: Bool { total > 0 && read == total }
}

@MainActor
enum GuideLayout {
    static func sections(_ route: RouteData, _ blocks: [RouteBlock]) -> [EraSection] {
        var result: [EraSection] = []
        var currentEra = -1
        var current: [RouteBlock] = []
        for block in blocks {
            let era = route.stages.lastIndex { $0.i <= block.id } ?? 0
            if era != currentEra {
                if currentEra >= 0 && !current.isEmpty {
                    result.append(EraSection(id: currentEra, era: route.stages[currentEra], blocks: current))
                }
                currentEra = era
                current = []
            }
            current.append(block)
        }
        if currentEra >= 0 && !current.isEmpty {
            result.append(EraSection(id: currentEra, era: route.stages[currentEra], blocks: current))
        }
        return result
    }

    /// Lo esencial de cada era: cuántos números tiene y cuántos leíste (para las medallas).
    static func eraCounts(_ route: RouteData, _ read: Set<Int>) -> [EraCount] {
        var counts = Array(repeating: EraCount(), count: route.stages.count)
        var era = 0
        for (index, item) in route.items.enumerated() {
            while era + 1 < route.stages.count && route.stages[era + 1].i <= index { era += 1 }
            guard !item.isExtra, !counts.isEmpty else { continue }
            counts[era].total += 1
            if read.contains(item.cvID) { counts[era].read += 1 }
        }
        return counts
    }

    static func readCount(_ route: RouteData, _ block: RouteBlock, _ read: Set<Int>) -> Int {
        block.indices.filter { read.contains(route.items[$0].cvID) }.count
    }

    static func points(_ block: RouteBlock) -> Int {
        block.count * (block.isExtra ? GuideProgress.pointsPerExtra : GuideProgress.pointsPerIssue)
    }

    /// Cómo se llama un punto de partida.
    static func startName(_ route: RouteData, _ index: Int) -> String {
        if index <= 0 { return "Desde el principio" }
        if let mark = route.marks.first(where: { $0.i == index }) { return mark.t }
        if let era = route.stages.first(where: { $0.i == index }) { return "Comienzo de \(era.t)" }
        guard index < route.items.count else { return "Desde el principio" }
        let item = route.items[index]
        return "\(route.series[item.series].label) #\(item.number)"
    }
}

/// El cartel de "+N puntos".
struct GuideCheer: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let text: String
}

// MARK: - Pantalla de una ruta

struct GuideRouteView: View {
    let routeID: String

    var body: some View {
        if let route = GuideRoutesStore.route(routeID) {
            GuideRouteScreen(route: route, info: RouteInfo.all.first { $0.id == routeID } ?? RouteInfo.all[0])
        } else {
            ContentUnavailableView("No se pudo abrir esta ruta", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct GuideRouteScreen: View {
    let route: RouteData
    let info: RouteInfo
    @State private var showSettings = false
    @State private var cheer: GuideCheer?
    @State private var cheers = 0
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let read = progress.readSet()
        let path = progress.path(route.id)
        let start = progress.start(route.id)
        let blocks = GuideRoutesStore.blocks(route, path: path, from: start)
        let sections = GuideLayout.sections(route, blocks)
        let eras = GuideLayout.eraCounts(route, read)
        let next = progress.next(route, path: path, read: read)
        let showsWay = progress.showsWay(route.id)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(read: read, eras: eras, path: path, start: start)
                if let next {
                    NextUpCard(route: route, info: info, block: next, path: path, read: read,
                               onToggle: { toggle(next) })
                        .padding(.top, 18)
                } else if !blocks.isEmpty {
                    doneCard.padding(.top, 18)
                }

                if showsWay {
                    wayContent(sections: sections, eras: eras, next: next, path: path, read: read)
                } else {
                    blocksContent(sections: sections, eras: eras, next: next, path: path, read: read)
                }

                Text("Orden: \(route.source). Tapas: Comic Vine; pertenecen a sus editoriales.")
                    .font(.caption2)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Theme.paper)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Ajustes de la ruta")
            }
        }
        .overlay(alignment: .top) {
            if let cheer {
                CheerBanner(cheer: cheer, color: info.color)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.cheer = nil } }
            }
        }
        .task(id: cheer?.id) {
            guard cheer != nil else { return }
            try? await Task.sleep(for: .seconds(2.8))
            withAnimation { cheer = nil }
        }
        .sensoryFeedback(.success, trigger: cheers)
        .sheet(isPresented: $showSettings) {
            RouteSettingsSheet(route: route) {
                let current = progress.path(route.id)
                return saveList(blocks: GuideRoutesStore.blocks(route, path: current, from: progress.start(route.id)),
                                path: current)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Arriba: avance simple

    private func header(read: Set<Int>, eras: [EraCount], path: RoutePath, start: Int) -> some View {
        let score = progress.score(route, read)
        let essential = eras.reduce(EraCount()) { EraCount(total: $0.total + $1.total, read: $0.read + $1.read) }
        let fraction = Double(essential.read) / Double(max(essential.total, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(essential.read)")
                    .font(.system(size: 28, weight: .black).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text("de \(essential.total) esenciales")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 4)
                Label("\(score.medals)/\(score.eras)", systemImage: "medal.fill")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                Text("\(score.points) pts")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(info.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chip)
                    Capsule().fill(info.color).frame(width: max(4, geo.size.width * min(fraction, 1)))
                }
            }
            .frame(height: 6)
            Text("\(path.label) · \(GuideLayout.startName(route, start))")
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
        }
        .padding(.top, 12)
    }

    private var doneCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill").font(.title).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("¡Terminaste este camino!").font(.headline).foregroundStyle(Theme.ink)
                Text("Probá \"Con todo\" para sumar los extras (valen el doble).")
                    .font(.caption).foregroundStyle(Theme.ink2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.yellow, lineWidth: 2))
    }

    // MARK: Bloques

    @ViewBuilder
    private func blocksContent(sections: [EraSection], eras: [EraCount], next: RouteBlock?,
                               path: RoutePath, read: Set<Int>) -> some View {
        ForEach(sections) { section in
            EraHeader(era: section.era, count: section.id < eras.count ? eras[section.id] : EraCount())
                .padding(.top, 22)
                .padding(.bottom, 8)
            ForEach(section.blocks) { block in
                BlockRow(route: route, info: info, block: block, path: path,
                         readCount: GuideLayout.readCount(route, block, read),
                         isNext: block.id == next?.id,
                         onToggle: { toggle(block) })
                    .id(block.id)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: Camino en zigzag

    @ViewBuilder
    private func wayContent(sections: [EraSection], eras: [EraCount], next: RouteBlock?,
                            path: RoutePath, read: Set<Int>) -> some View {
        let order = Dictionary(uniqueKeysWithValues: sections.flatMap(\.blocks).enumerated().map { ($0.element.id, $0.offset) })
        Color.clear.frame(height: 18)
        ForEach(sections) { section in
            EraFlag(era: section.era, count: section.id < eras.count ? eras[section.id] : EraCount(), color: info.color)
            ForEach(section.blocks) { block in
                WayStop(route: route, info: info, block: block, path: path,
                        left: (order[block.id] ?? 0) % 2 == 0,
                        readCount: GuideLayout.readCount(route, block, read),
                        isNext: block.id == next?.id,
                        onToggle: { toggle(block) })
                    .id(block.id)
            }
        }
        WayEnd(color: info.color)
    }

    // MARK: Guardar en Mis listas

    private func saveList(blocks: [RouteBlock], path: RoutePath) -> String {
        var items: [ListItem] = []
        for block in blocks {
            for index in block.indices {
                let item = route.items[index]
                let name = route.series[item.series].name
                items.append(.comicVine(item.cvID, title: CVText.issueTitle(series: name, number: item.number),
                                        series: name, number: item.number, year: nil,
                                        cover: GuideCovers.shared.links[item.cvID]))
            }
        }
        guard !items.isEmpty else { return "Este camino no tiene números para guardar." }
        let list = CustomListStore.shared.create(name: "\(route.title) · \(path.label)", items: items,
                                                 origin: "Guía Por dónde empezar (CBRO)")
        return "Listo: \"\(list.name)\" (\(list.items.count) números) está en Biblioteca → Listas."
    }

    // MARK: Marcar leído y puntos

    private func toggle(_ block: RouteBlock) {
        let readBefore = progress.readSet()
        let before = progress.score(route, readBefore)
        let totalBefore = progress.total(readBefore).points
        progress.toggle(block.indices.map { route.items[$0].cvID })
        let readAfter = progress.readSet()
        let after = progress.score(route, readAfter)
        let totalAfter = progress.total(readAfter).points
        let gained = after.points - before.points
        guard gained > 0 else { return }
        var title = "¡Bien leído!"
        if after.routesDone > before.routesDone {
            title = "¡Ruta completa!"
        } else if after.medals > before.medals {
            title = "¡Era completada! Ganaste una medalla"
        }
        var text = "+\(gained) puntos"
        let levelBefore = GuideProgress.level(for: totalBefore)
        let levelAfter = GuideProgress.level(for: totalAfter)
        if levelAfter.index > levelBefore.index { text += " · Nuevo nivel: \(levelAfter.name)" }
        withAnimation(.spring(duration: 0.35)) { cheer = GuideCheer(title: title, text: text) }
        cheers += 1
    }
}

// MARK: - Piezas

private struct CheerBanner: View {
    let cheer: GuideCheer
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.circle.fill").font(.title2).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text(cheer.title).font(.subheadline.weight(.black)).foregroundStyle(.white)
                Text(cheer.text).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color, in: Capsule())
        .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

private struct EraHeader: View {
    let era: RouteEra
    let count: EraCount

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(era.t).font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(era.y).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink2)
            }
            Spacer()
            if count.complete {
                Label("Medalla", systemImage: "medal.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.star)
            } else if count.total > 0 {
                Text("\(count.read)/\(count.total)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.ink2)
            }
        }
    }
}

/// Insignias de una parada: "Empezá por acá", "Evento", "Extra ×2".
private struct BlockBadges: View {
    let route: RouteData
    let block: RouteBlock

    var body: some View {
        let isStart = route.marks.contains { $0.isStart && block.indices.contains($0.i) }
        HStack(spacing: 4) {
            if isStart { badge("★ Empezá por acá", Theme.magenta) }
            if block.isEvent { badge("⚡ Evento", Color(hex: 0xE65C00)) }
            if block.isExtra { badge("Extra ×2", Theme.cyan) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

private struct ReadCircle: View {
    let readCount: Int
    let total: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 3)
            if readCount > 0 && readCount < total {
                Circle()
                    .trim(from: 0, to: Double(readCount) / Double(max(total, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if readCount >= total && total > 0 {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct BlockRow: View {
    let route: RouteData
    let info: RouteInfo
    let block: RouteBlock
    let path: RoutePath
    let readCount: Int
    let isNext: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                ReadCircle(readCount: readCount, total: block.count, color: info.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(readCount >= block.count ? "Desmarcar como leído" : "Marcar como leído")

            NavigationLink(value: CommunityRoute.guideBlock(route.id, block.id, path.rawValue)) {
                HStack(spacing: 6) {
                    Text(block.series.label)
                        .font(.system(size: block.isExtra ? 13 : 15, weight: block.isExtra ? .medium : .bold))
                        .foregroundStyle(block.isExtra ? Theme.ink2 : Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(block.numbersText)
                        .font(.system(size: block.isExtra ? 12 : 14).monospacedDigit())
                        .foregroundStyle(Theme.ink2)
                    if block.isEvent {
                        Image(systemName: "bolt.fill").font(.caption).foregroundStyle(Color(hex: 0xE65C00))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.ink2.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, block.isExtra ? 6 : 9)
        .background(isNext ? Theme.yellow.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, block.isExtra ? 24 : 0)
    }
}

/// El cartel de cada era en el camino.
private struct EraFlag: View {
    let era: RouteEra
    let count: EraCount
    let color: Color

    var body: some View {
        ZStack {
            DashedLine().stroke(Theme.line, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
            HStack(spacing: 8) {
                if count.complete {
                    Image(systemName: "medal.fill").foregroundStyle(Theme.yellow)
                }
                VStack(spacing: 0) {
                    Text(era.t).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    Text(count.total > 0 ? "\(era.y) · \(count.read)/\(count.total)" : era.y)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
    }
}

/// Línea vertical por el medio (une las eras con las paradas).
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// El tramo de camino de una parada: entra por arriba al medio, pasa por la tapa y sale por abajo al medio.
private struct StopTrail: Shape {
    let nodeX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let node = CGPoint(x: nodeX, y: rect.midY)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: node, control: CGPoint(x: nodeX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: nodeX, y: rect.maxY))
        return path
    }
}

private struct WayStop: View {
    let route: RouteData
    let info: RouteInfo
    let block: RouteBlock
    let path: RoutePath
    let left: Bool
    let readCount: Int
    let isNext: Bool
    let onToggle: () -> Void
    private var covers: GuideCovers { GuideCovers.shared }

    var body: some View {
        let done = readCount >= block.count
        let coverWidth: CGFloat = block.isExtra ? 62 : 86
        let height: CGFloat = block.isExtra ? 128 : 172
        let firstID = route.items[block.indices[0]].cvID
        GeometryReader { geo in
            let width = geo.size.width
            let nodeX = left ? width * 0.27 : width * 0.73
            ZStack {
                StopTrail(nodeX: nodeX)
                    .stroke(readCount > 0 ? info.color : Theme.line,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                NavigationLink(value: CommunityRoute.guideBlock(route.id, block.id, path.rawValue)) {
                    cover(firstID: firstID, done: done)
                        .frame(width: coverWidth)
                }
                .buttonStyle(.plain)
                .position(x: nodeX, y: height / 2)

                label(done: done)
                    .frame(width: width * 0.44, alignment: left ? .leading : .trailing)
                    .position(x: left ? width * 0.73 : width * 0.27, y: height / 2)
            }
        }
        .frame(height: height)
        .onAppear { covers.want(firstID) }
    }

    private func cover(firstID: Int, done: Bool) -> some View {
        RemoteCover(url: covers.url(firstID))
            .grayscale(done || isNext || readCount > 0 ? 0 : 0.9)
            .opacity(done || isNext || readCount > 0 ? 1 : 0.8)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isNext ? Theme.yellow : (done ? info.color : .clear), lineWidth: 3))
            .shadow(color: isNext ? Theme.yellow.opacity(0.9) : .black.opacity(0.18), radius: isNext ? 12 : 4, y: 2)
            .overlay(alignment: .bottomTrailing) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, info.color)
                        .offset(x: 8, y: 8)
                } else if readCount > 0 {
                    Text("\(readCount)/\(block.count)")
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(info.color, in: Capsule())
                        .offset(x: 6, y: 6)
                }
            }
            .overlay(alignment: .top) {
                if isNext {
                    Text("SEGUÍ ACÁ")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color(hex: 0x17191E))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.yellow, in: Capsule())
                        .fixedSize()
                        .offset(y: -12)
                }
            }
    }

    private func label(done: Bool) -> some View {
        VStack(alignment: left ? .leading : .trailing, spacing: 3) {
            Text(block.series.label)
                .font(.system(size: block.isExtra ? 12 : 14, weight: block.isExtra ? .semibold : .heavy))
                .foregroundStyle(block.isExtra ? Theme.ink2 : Theme.ink)
                .multilineTextAlignment(left ? .leading : .trailing)
                .lineLimit(3)
            HStack(spacing: 4) {
                if block.isEvent {
                    Image(systemName: "bolt.fill").foregroundStyle(Color(hex: 0xE65C00))
                }
                Text(block.isExtra ? "\(block.numbersText) · extra" : block.numbersText)
                    .foregroundStyle(Theme.ink2)
            }
            .font(.caption.monospacedDigit())
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? info.color : Theme.ink2.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Desmarcar como leído" : "Marcar como leído")
        }
    }
}

private struct WayEnd: View {
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            DashedLine()
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                .frame(height: 30)
            Image(systemName: "trophy.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.yellow)
                .frame(width: 64, height: 64)
                .background(color, in: Circle())
            Text("+\(GuideProgress.pointsPerRoute) al terminar lo esencial")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Seguí por acá": la próxima parada para leer.
private struct NextUpCard: View {
    let route: RouteData
    let info: RouteInfo
    let block: RouteBlock
    let path: RoutePath
    let read: Set<Int>
    let onToggle: () -> Void
    private var covers: GuideCovers { GuideCovers.shared }

    var body: some View {
        let unread = block.indices.filter { !read.contains(route.items[$0].cvID) }
        let firstID = route.items[unread.first ?? block.indices[0]].cvID
        HStack(alignment: .center, spacing: 14) {
            NavigationLink(value: CommunityRoute.guideBlock(route.id, block.id, path.rawValue)) {
                RemoteCover(url: covers.url(firstID)).frame(width: 64)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text("SEGUÍ POR ACÁ")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Theme.ink2)
                Text("\(block.series.label) \(block.numbersText)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if unread.count < block.count {
                    Text("Te faltan \(unread.count) de \(block.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }
                Button(action: onToggle) {
                    Text("Ya lo leí").font(.caption.weight(.heavy))
                }
                .buttonStyle(.borderedProminent)
                .tint(info.color)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.yellow, lineWidth: 2))
        .onAppear { covers.want(firstID) }
    }
}

// MARK: - Ajustes de la ruta (ruedita de arriba a la derecha)

private struct RouteSettingsSheet: View {
    let route: RouteData
    /// Guarda el camino en Mis listas y devuelve el aviso para mostrar.
    let onSave: () -> String
    @State private var askSave = false
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let path = progress.path(route.id)
        NavigationStack {
            Form {
                Section {
                    Picker("Camino", selection: Binding(get: { progress.path(route.id) },
                                                        set: { progress.setPath($0, for: route.id) })) {
                        ForEach(RoutePath.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Camino")
                } footer: {
                    Text(path.explanation)
                }

                Section("Cómo verlo") {
                    Picker("Cómo verlo", selection: Binding(get: { progress.showsWay(route.id) },
                                                            set: { progress.setShowsWay($0, for: route.id) })) {
                        Text("Camino").tag(true)
                        Text("Bloques").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink {
                        StartPickerList(route: route)
                    } label: {
                        LabeledContent("Empezar desde", value: GuideLayout.startName(route, progress.start(route.id)))
                    }
                } header: {
                    Text("Punto de partida")
                } footer: {
                    Text("Lo que viene antes queda fuera del camino (si ya lo leíste, igual suma puntos).")
                }

                Section {
                    Button("Guardar este camino en Mis listas") { askSave = true }
                    if let notice {
                        Text(notice).font(.footnote).foregroundStyle(Theme.ink2)
                    }
                } footer: {
                    Text("Crea una lista en Biblioteca → Listas con los números de este camino, desde tu punto de partida.")
                }
            }
            .tint(Theme.magenta)
            .navigationTitle("Ajustes de la ruta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmationDialog("¿Guardar este camino en Mis listas?", isPresented: $askSave, titleVisibility: .visible) {
                Button("Guardar") { notice = onSave() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }
}

/// Lista de puntos de partida (dentro de los ajustes).
private struct StartPickerList: View {
    let route: RouteData
    @Environment(\.dismiss) private var dismiss
    private var progress: GuideProgress { GuideProgress.shared }

    var body: some View {
        let current = progress.start(route.id)
        List {
            Section {
                option(0, "Desde el principio", icon: "flag.checkered", color: Theme.ink2, current: current)
            } footer: {
                Text("¿Ya venís leyendo algo? Abrí esa parada en la ruta y tocá \"Empezar la ruta desde acá\".")
            }
            ForEach(Array(route.stages.indices), id: \.self) { index in
                let era = route.stages[index]
                let end = index + 1 < route.stages.count ? route.stages[index + 1].i : route.items.count
                let marks = route.marks.filter { $0.i >= era.i && $0.i < end }
                Section {
                    option(era.i, "Comienzo de \(era.t)", icon: "flag", color: Theme.ink2, current: current)
                    ForEach(marks.indices, id: \.self) { m in
                        let mark = marks[m]
                        if mark.isStart {
                            option(mark.i, mark.t, icon: "star.fill", color: Theme.magenta, current: current)
                        } else {
                            option(mark.i, "Evento: \(mark.t)", icon: "bolt.fill", color: Color(hex: 0xE65C00), current: current)
                        }
                    }
                } header: {
                    Text("\(era.t) · \(era.y)")
                }
            }
        }
        .navigationTitle("¿Por dónde empezás?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ index: Int, _ title: String, icon: String, color: Color, current: Int) -> some View {
        Button {
            progress.setStart(index, for: route.id)
            dismiss()
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
                Spacer()
                if index == current {
                    Image(systemName: "checkmark").foregroundStyle(Theme.magenta)
                }
            }
        }
    }
}

// MARK: - Detalle de una parada

struct GuideBlockView: View {
    let routeID: String
    let blockID: Int
    let pathRaw: String
    @State private var cheers = 0
    private var progress: GuideProgress { GuideProgress.shared }
    private var covers: GuideCovers { GuideCovers.shared }

    var body: some View {
        if let route = GuideRoutesStore.route(routeID),
           let block = GuideRoutesStore.blocks(route, path: RoutePath(rawValue: pathRaw) ?? .essential, from: blockID).first {
            content(route, block)
        } else {
            ContentUnavailableView("No se encontró esta parada", systemImage: "exclamationmark.triangle")
        }
    }

    private func content(_ route: RouteData, _ block: RouteBlock) -> some View {
        let read = progress.readSet()
        let info = RouteInfo.all.first { $0.id == routeID } ?? RouteInfo.all[0]
        let readCount = GuideLayout.readCount(route, block, read)
        let era = GuideRoutesStore.era(route, at: block.id)
        let ids = block.indices.map { route.items[$0].cvID }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(block.series.label) \(block.numbersText)")
                        .font(.title3.weight(.black))
                        .foregroundStyle(Theme.ink)
                    if let era {
                        Text("\(route.title) · \(era.t) (\(era.y))").font(.subheadline).foregroundStyle(Theme.ink2)
                    }
                    BlockBadges(route: route, block: block)
                    Text(block.isExtra
                         ? "Lectura extra (opcional): cada número vale \(GuideProgress.pointsPerExtra) puntos."
                         : "Cada número vale \(GuideProgress.pointsPerIssue) puntos.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                    Text("Leíste \(readCount) de \(block.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 4)
                Button {
                    progress.toggle(ids)
                    cheers += 1
                } label: {
                    Label(readCount >= block.count ? "Desmarcar todos" : "Marcar todos como leídos",
                          systemImage: readCount >= block.count ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                }
                .tint(info.color)
                Button {
                    progress.setStart(block.id, for: routeID)
                    cheers += 1
                } label: {
                    Label(progress.start(routeID) == block.id ? "Tu ruta empieza acá" : "Empezar la ruta desde acá",
                          systemImage: "flag.checkered")
                }
                .tint(Theme.magenta)
                .disabled(progress.start(routeID) == block.id)
            } footer: {
                Text("Los números que terminás en el lector se marcan solos (si su archivo tiene la ficha de Comic Vine).")
            }

            Section("Números") {
                ForEach(block.indices, id: \.self) { index in
                    issueRow(route, index, read: read, color: info.color)
                }
            }
        }
        .navigationTitle(block.series.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sensoryFeedback(.success, trigger: cheers)
    }

    private func issueRow(_ route: RouteData, _ index: Int, read: Set<Int>, color: Color) -> some View {
        let item = route.items[index]
        let name = route.series[item.series].name
        let done = read.contains(item.cvID)
        return HStack(spacing: 12) {
            Button {
                progress.toggle([item.cvID])
                if !done { cheers += 1 }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? color : Theme.ink2)
            }
            .buttonStyle(.plain)
            NavigationLink(value: CVRoute.issue(id: item.cvID, title: CVText.issueTitle(series: name, number: item.number))) {
                HStack(spacing: 10) {
                    RemoteCover(url: covers.url(item.cvID)).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(route.series[item.series].label) #\(item.number)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if item.isEvent {
                            Text("⚡ Evento").font(.caption2.weight(.bold)).foregroundStyle(Color(hex: 0xE65C00))
                        }
                    }
                }
            }
        }
        .onAppear { covers.want(item.cvID) }
    }
}
