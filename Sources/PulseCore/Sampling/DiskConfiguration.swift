import Foundation

struct DiskConfiguration: Decodable {
    let extraRoots: [String]
    static func roots(home: URL) -> [URL] {
        let file = home.appendingPathComponent("Library/Application Support/Pulse/config.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 65_536,
              let data = try? Data(contentsOf: file), data.count <= 65_536,
              let config = try? JSONDecoder().decode(Self.self, from: data), config.extraRoots.count <= 128 else { return [] }
        return config.extraRoots.compactMap { path in
            if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
        }
    }
}
