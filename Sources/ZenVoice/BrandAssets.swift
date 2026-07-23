import AppKit
import Foundation

enum BrandAssets {
    static let zenLogo: NSImage? = {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ZenLogo.png"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/Brand/ZenLogo.png")
        ].compactMap { $0 }

        guard let url = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }()
}
