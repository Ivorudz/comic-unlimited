import UIKit

// Girar el teléfono: la app va siempre derecha, salvo el lector de tus archivos,
// que deja ponerlo de costado (ahí se ven dos páginas juntas).

enum AppOrientation {
    /// true mientras el lector está abierto.
    static var allowLandscape = false

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
