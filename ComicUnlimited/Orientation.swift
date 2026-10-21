import UIKit

// Girar el teléfono: la app va siempre derecha, salvo el lector de tus archivos,
// que deja ponerlo de costado (ahí se ven dos páginas juntas).

enum AppOrientation {
    /// true mientras el lector está abierto.
    static var allowLandscape = false
    /// Lectores abiertos (al pasar al siguiente número, por un momento puede haber dos).
    private static var openReaders = 0

    /// El lector se abrió: deja girar y, si querés, mantiene la pantalla encendida.
    static func readerOpened(keepAwake: Bool) {
        openReaders += 1
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        set(allowLandscape: true)
    }

    /// El lector se cerró: si no queda ninguno abierto, la app vuelve a quedar derecha.
    static func readerClosed() {
        openReaders = max(0, openReaders - 1)
        guard openReaders == 0 else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        set(allowLandscape: false)
    }

    /// Deja girar (lector abierto) o vuelve a poner la app derecha (lector cerrado).
    static func set(allowLandscape allow: Bool) {
        allowLandscape = allow
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !allow {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientation.allowLandscape ? .allButUpsideDown : .portrait
    }
}
