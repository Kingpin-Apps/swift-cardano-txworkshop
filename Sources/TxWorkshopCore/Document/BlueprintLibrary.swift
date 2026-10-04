import Foundation
import Observation

/// The blueprints kept in the app, for any document to use: one JSON file
/// each, in Application Support.
@MainActor
@Observable
public final class BlueprintLibrary {
    public private(set) var blueprints: [StoredBlueprint] = []
    public private(set) var lastError: String?
    private let folder: URL?

    /// The library in Application Support; `folder` overrides it (`nil` keeps
    /// it in memory only).
    public init(folder: URL? = BlueprintLibrary.defaultFolder) {
        self.folder = folder
        load()
    }

    public static func inMemory(_ blueprints: [StoredBlueprint] = []) -> BlueprintLibrary {
        let library = BlueprintLibrary(folder: nil)
        library.blueprints = blueprints
        return library
    }

    public nonisolated static var defaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Blueprints", directoryHint: .isDirectory)
    }

    /// Adds a blueprint; one already kept is left as it is.
    public func add(_ blueprint: StoredBlueprint) {
        guard !blueprints.contains(where: { $0.id == blueprint.id }) else { return }
        blueprints.append(blueprint)
        guard let folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(blueprint.json.utf8).write(to: file(blueprint.id, in: folder), options: .atomic)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func remove(_ id: String) {
        blueprints.removeAll { $0.id == id }
        guard let folder else { return }
        try? FileManager.default.removeItem(at: file(id, in: folder))
    }

    private func load() {
        guard let folder,
            let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        let dated = files.filter { $0.pathExtension == "json" }.compactMap { url -> (Date, StoredBlueprint)? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (date, StoredBlueprint(json: text))
        }
        blueprints = dated.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func file(_ id: String, in folder: URL) -> URL {
        folder.appending(path: "\(id).json")
    }
}
