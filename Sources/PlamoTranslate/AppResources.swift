import Foundation

enum AppResources {
    static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("PlamoTranslate_PlamoTranslate.bundle")) {
            return packaged
        }
        return .module
    }
}
