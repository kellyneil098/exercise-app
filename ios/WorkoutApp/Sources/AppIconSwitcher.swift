import UIKit

/// Swaps the home-screen icon between the primary `AppIcon` (`nil`) and the alternates listed under
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in project.yml (currently `"AppIcon-Hunny"`).
enum AppIconSwitcher {
    static let hunny = "AppIcon-Hunny"

    @MainActor
    static func apply(_ name: String?) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != name else { return }
        app.setAlternateIconName(name) { _ in }   // best effort: a failed swap just keeps the current icon
    }
}
