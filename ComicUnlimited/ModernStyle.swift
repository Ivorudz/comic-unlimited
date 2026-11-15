import SwiftUI
import Combine
import UIKit

// Piezas del "Estilo moderno" (Personalizar → Estilo moderno): Rutas, Inicio y Biblioteca con
// fondo de colores que se mueve, vidrio, sombras suaves, entradas animadas y botones que se inclinan.
// Con el estilo apagado, todo se ve como antes. Con "Reducir movimiento" del iPhone, nada se mueve.

extension AppearanceSettings {
    /// Estilo moderno prendido (se guarda con la misma clave que "Rutas modernas").
    var modern: Bool { modernRoutes }

    /// Barra de pestañas flotante: se decide al abrir la app (si se cambia el estilo, se nota al volver a abrirla).
    static let floatingTabBar: Bool = AppearanceSettings.shared.modern
}

/// Botón de tarjeta: con el estilo moderno se achica, se inclina un poco y vibra al apretarlo;
/// con el estilo anterior queda quieto, como antes.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let modern = AppearanceSettings.shared.modern
        let pressed = configuration.isPressed && modern
        return configuration.label
            .scaleEffect(pressed ? 0.95 : 1)
            .rotation3DEffect(.degrees(pressed ? 5 : 0), axis: (x: 1, y: 0, z: 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, now in now && modern }
    }
}

/// Fondo de la pantalla: con el estilo moderno, manchas del color principal que se mueven despacio.
struct ModernScreenBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.paper
            if AppearanceSettings.shared.modern {
                RoutesBackdrop(colors: [Theme.magenta, Theme.cyan, Theme.magenta], still: reduceMotion)
                    .opacity(0.55)
            }
        }
        .ignoresSafeArea()
    }
}

/// Entrada animada: la parte aparece subiendo y aclarándose, un poco después que la anterior.
struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let animate = AppearanceSettings.shared.modern && !reduceMotion
        let visible = !animate || shown
        return content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 24)
            .onAppear {
                guard animate, !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(min(index, 6)) * 0.07)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Tarjeta: vidrio con borde de luz (estilo moderno) o la tarjeta de siempre.
    @ViewBuilder
    func modernCard(cornerRadius: CGFloat = 14) -> some View {
        if AppearanceSettings.shared.modern {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        } else {
            self
                .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.line))
        }
    }
}

// MARK: - Barra de pestañas flotante

/// Barra de abajo como cápsula de vidrio que flota sobre el contenido (estilo de las apps nuevas).
/// El resaltado de la pestaña elegida se desliza de una a otra.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var slider
    /// Con el teclado abierto la barra se esconde (como en las apps de Apple).
    @State private var keyboardOpen = false

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let icon: String
        let selectedIcon: String
        var id: AppTab { tab }
    }

    private static let items: [Item] = [
        Item(tab: .home, title: "Inicio", icon: "house", selectedIcon: "house.fill"),
        Item(tab: .library, title: "Biblioteca", icon: "books.vertical", selectedIcon: "books.vertical.fill"),
        Item(tab: .routes, title: "Rutas", icon: "map", selectedIcon: "map.fill"),
        Item(tab: .community, title: "Comunidad", icon: "bubble.left", selectedIcon: "bubble.left.fill"),
        Item(tab: .profile, title: "Perfil", icon: "person.crop.circle", selectedIcon: "person.crop.circle.fill"),
    ]

    var body: some View {
        Group {
            if !keyboardOpen { bar }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOpen = false
        }
    }

    private var bar: some View {
        HStack(spacing: 2) {
            ForEach(Self.items) { item in
                let selected = selection == item.tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected ? item.selectedIcon : item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Theme.magenta : Theme.ink.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.ink.opacity(0.09))
                                .matchedGeometryEffect(id: "tab", in: slider)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
