import Foundation
import ServiceManagement

/// A set of menu bar items that gets its own Peeky icon in the menu bar.
struct ItemGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String

    static let symbols = [
        "chevron.left.chevron.right", "square.grid.2x2", "star", "bolt", "wrench.and.screwdriver",
        "network", "speaker.wave.2", "bubble.left", "folder", "tray", "sparkles", "circle.hexagongrid",
    ]
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    /// Groups, in the order their icons are created. Never empty.
    @Published var groups: [ItemGroup] {
        didSet { defaults.set(try? JSONEncoder().encode(groups), forKey: "groups") }
    }

    /// Which group each item belongs to. Items not listed here fall into the first group.
    @Published var assignments: [String: UUID] {
        didSet { defaults.set(try? JSONEncoder().encode(assignments), forKey: "assignments") }
    }

    /// Items the user turned off: they appear in no group.
    @Published var excludedIDs: Set<String> {
        didSet { defaults.set(Array(excludedIDs), forKey: "excludedIDs") }
    }

    /// When on, the bar lists only items the notch is currently hiding.
    @Published var onlyNotchHidden: Bool {
        didSet { defaults.set(onlyNotchHidden, forKey: "onlyNotchHidden") }
    }

    /// Maximum width (points) of the scrollable strip before arrows/scrolling kick in.
    @Published var maxStripWidth: Double {
        didSet { defaults.set(maxStripWidth, forKey: "maxStripWidth") }
    }

    /// How many rows the bar uses (1–3). Extra rows make the bar shorter and need less scrolling.
    @Published var rowCount: Int {
        didSet { defaults.set(rowCount, forKey: "rowCount") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Peeky: launch-at-login change failed: \(error)")
            }
        }
    }

    private init() {
        let savedGroups = (defaults.data(forKey: "groups")).flatMap { try? JSONDecoder().decode([ItemGroup].self, from: $0) } ?? []
        groups = savedGroups.isEmpty
            ? [ItemGroup(id: UUID(), name: "기본", symbol: ItemGroup.symbols[0])]
            : savedGroups
        assignments = (defaults.data(forKey: "assignments"))
            .flatMap { try? JSONDecoder().decode([String: UUID].self, from: $0) } ?? [:]
        excludedIDs = Set(defaults.stringArray(forKey: "excludedIDs") ?? [])
        onlyNotchHidden = defaults.object(forKey: "onlyNotchHidden") as? Bool ?? false
        maxStripWidth = defaults.object(forKey: "maxStripWidth") as? Double ?? 320
        rowCount = min(3, max(1, defaults.object(forKey: "rowCount") as? Int ?? 1))
    }

    /// The group an item shows in, or nil when the user turned it off.
    func group(for itemID: String) -> UUID? {
        guard !excludedIDs.contains(itemID) else { return nil }
        if let g = assignments[itemID], groups.contains(where: { $0.id == g }) { return g }
        return groups.first?.id
    }

    /// Puts an item into a group, or turns it off when `group` is nil.
    func assign(_ itemID: String, to group: UUID?) {
        if let group {
            excludedIDs.remove(itemID)
            assignments[itemID] = group
        } else {
            excludedIDs.insert(itemID)
        }
    }

    @discardableResult
    func addGroup() -> ItemGroup {
        let used = Set(groups.map(\.symbol))
        let symbol = ItemGroup.symbols.first { !used.contains($0) } ?? ItemGroup.symbols[0]
        let group = ItemGroup(id: UUID(), name: "그룹 \(groups.count + 1)", symbol: symbol)
        groups.append(group)
        return group
    }

    /// Removes a group; its items fall back to the first remaining group.
    func removeGroup(_ id: UUID) {
        guard groups.count > 1 else { return }
        groups.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
    }

    func updateGroup(_ group: ItemGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[i] = group
    }
}
