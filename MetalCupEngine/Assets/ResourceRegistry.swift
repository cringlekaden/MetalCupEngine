import Foundation
import MetalKit

public enum ResourceRegistry {
    // The MTLLibrary that contains compiled shader functions (usually from the app target)
    public static var defaultLibrary: MTLLibrary?

    // Root URL for app resources (e.g., /Assets/Resources/). If nil, fall back to Bundle.main.
    public static var resourcesRootURL: URL?

    // Resolve a resource URL by name and extension. Looks under resourcesRootURL first, then Bundle.main.
    public static func url(forResource name: String, withExtension ext: String?) -> URL? {
        if let root = resourcesRootURL {
            let url = ext != nil ? root.appendingPathComponent("\(name).\(ext!)") : root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}
