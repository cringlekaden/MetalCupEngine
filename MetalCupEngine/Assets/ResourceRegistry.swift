import Foundation
import MetalKit

public enum ResourceRegistry {
    // The MTLLibrary that contains compiled shader functions (usually from the app target)
    public static var defaultLibrary: MTLLibrary?

    // Root URL for app resources (e.g., /Assets/Resources/). If nil, fall back to Bundle.main.
    public static var resourcesRootURL: URL?

    // Optional shader roots (highest priority) for runtime compilation.
    public static var shaderRootURLs: [URL] = []

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

    private static var didAttemptRuntimeCompile: Bool = false

    public static func buildDefaultLibraryIfNeeded(device: MTLDevice, force: Bool = false) {
        if defaultLibrary != nil && !force { return }
        if let lib = loadLibraryFromBundle(device: device) {
            defaultLibrary = lib
            return
        }
        guard let lib = buildLibraryFromResources(device: device) else {
            print("RESOURCE_REGISTRY::No shader library built from resources.")
            return
        }
        defaultLibrary = lib
    }

    public static func resolveFunction(_ name: String, device: MTLDevice) -> MTLFunction? {
        let primary = defaultLibrary ?? Engine.DefaultLibrary
        if let fn = primary?.makeFunction(name: name) {
            return fn
        }

        if !didAttemptRuntimeCompile {
            didAttemptRuntimeCompile = true
            buildDefaultLibraryIfNeeded(device: device, force: true)
        }

        let fallback = defaultLibrary ?? Engine.DefaultLibrary
        return fallback?.makeFunction(name: name)
    }

    private static func buildLibraryFromResources(device: MTLDevice) -> MTLLibrary? {
        var candidateRoots: [URL] = []
        if let root = resourcesRootURL {
            candidateRoots.append(root)
        }
        if let bundleRoot = Bundle.main.resourceURL {
            let metalCupEditorRoot = bundleRoot.appendingPathComponent("MetalCupEditor", isDirectory: true)
            if FileManager.default.fileExists(atPath: metalCupEditorRoot.path) {
                candidateRoots.append(metalCupEditorRoot)
            }
        }
        if candidateRoots.isEmpty { return nil }

        var shaderRoots = shaderRootURLs
        shaderRoots.append(contentsOf: candidateRoots.flatMap { root in
            [
                root.appendingPathComponent("Shaders", isDirectory: true),
                root.appendingPathComponent("Assets/Shaders", isDirectory: true),
                root.appendingPathComponent("Projects/Sandbox/Assets/Shaders", isDirectory: true)
            ]
        })
        let fm = FileManager.default
        print("RESOURCE_REGISTRY::Resource root candidates:")
        for root in candidateRoots {
            print(" - \(root.path)")
        }
        print("RESOURCE_REGISTRY::Shader root candidates:")
        for root in shaderRoots {
            print(" - \(root.path)")
        }
        let existingRoot = shaderRoots.first { fm.fileExists(atPath: $0.path) }
        guard let shaderRoot = existingRoot else { return nil }
        print("RESOURCE_REGISTRY::Using shader root: \(shaderRoot.path)")

        guard let enumerator = fm.enumerator(at: shaderRoot, includingPropertiesForKeys: nil) else { return nil }
        var shaderFiles: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "metal" {
                shaderFiles.append(url)
            }
        }
        if shaderFiles.isEmpty { return nil }
        print("RESOURCE_REGISTRY::Found \(shaderFiles.count) .metal files.")

        shaderFiles.sort { $0.path < $1.path }
        let fileLookup = buildFileLookup(shaderFiles: shaderFiles)
        var combinedSource = ""
        var includedFiles = Set<String>()
        for url in shaderFiles {
            combinedSource.append(expandIncludes(url: url, fileLookup: fileLookup, includedFiles: &includedFiles))
            combinedSource.append("\n\n")
        }

        do {
            let options = MTLCompileOptions()
            if #available(macOS 15.0, *) {
                options.mathMode = .fast
            } else {
                options.fastMathEnabled = true
            }
            return try device.makeLibrary(source: combinedSource, options: options)
        } catch {
            print("RESOURCE_REGISTRY::Failed to compile shader library: \(error)")
            return nil
        }
    }

    private static func buildFileLookup(shaderFiles: [URL]) -> [String: URL] {
        var lookup: [String: URL] = [:]
        for url in shaderFiles {
            lookup[url.lastPathComponent] = url
        }
        return lookup
    }

    private static func expandIncludes(url: URL, fileLookup: [String: URL], includedFiles: inout Set<String>) -> String {
        if includedFiles.contains(url.path) { return "" }
        includedFiles.insert(url.path)

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }

        var output = "// \(url.lastPathComponent)\n"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            if let includeName = parseInclude(from: String(line)),
               let includeURL = fileLookup[includeName] {
                output.append(expandIncludes(url: includeURL, fileLookup: fileLookup, includedFiles: &includedFiles))
            } else {
                output.append(String(line))
                output.append("\n")
            }
        }
        return output
    }

    private static func parseInclude(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#include") else { return nil }
        guard let quoteStart = trimmed.firstIndex(of: "\""),
              let quoteEnd = trimmed[trimmed.index(after: quoteStart)...].firstIndex(of: "\"") else {
            return nil
        }
        let name = trimmed[trimmed.index(after: quoteStart)..<quoteEnd]
        return name.isEmpty ? nil : String(name)
    }

    private static func loadLibraryFromBundle(device: MTLDevice) -> MTLLibrary? {
        let fm = FileManager.default
        for root in shaderRootURLs {
            if let lib = loadLibrary(from: root, device: device) {
                return lib
            }
        }

        let bundles: [Bundle] = [Bundle.main, Bundle(for: Renderer.self)]
        let candidateRoots = bundles.compactMap { $0.resourceURL }
        let shaderRoots = candidateRoots.flatMap { root in
            [
                root,
                root.appendingPathComponent("MetalCupEditor", isDirectory: true),
                root.appendingPathComponent("MetalCupEditor/Projects/Sandbox/Assets/Shaders", isDirectory: true),
                root.appendingPathComponent("Projects/Sandbox/Assets/Shaders", isDirectory: true),
                root.appendingPathComponent("Shaders", isDirectory: true)
            ]
        }

        for root in shaderRoots {
            guard fm.fileExists(atPath: root.path) else { continue }
            if let lib = loadLibrary(from: root, device: device) {
                return lib
            }
        }
        return nil
    }

    private static func loadLibrary(from directory: URL, device: MTLDevice) -> MTLLibrary? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        let metallibs = items.filter { $0.pathExtension.lowercased() == "metallib" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for libURL in metallibs {
            if let lib = try? device.makeLibrary(URL: libURL) {
                print("RESOURCE_REGISTRY::Loaded metallib: \(libURL.path)")
                return lib
            }
        }
        return nil
    }
}
