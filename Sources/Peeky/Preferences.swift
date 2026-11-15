import Carbon
import Foundation
import ServiceManagement

/// A set of menu bar items that gets its own Peeky icon in the menu bar.
struct ItemGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    /// nil이면 전체 설정을 따른다.
    var rowCount: Int?
    var onlyNotchHidden: Bool?

    static let symbols = [
        "chevron.left.chevron.right", "square.grid.2x2", "star", "bolt", "wrench.and.screwdriver",
        "network", "speaker.wave.2", "bubble.left", "folder", "tray", "sparkles", "circle.hexagongrid",
    ]
}

/// 그룹 단축키에 쓰는 보조 키 묶음.
enum HotKeyModifiers: Int, CaseIterable, Identifiable {
    case controlOption, controlCommand, optionCommand, controlShift, off

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .controlOption: return "⌃⌥"
        case .controlCommand: return "⌃⌘"
        case .optionCommand: return "⌥⌘"
        case .controlShift: return "⌃⇧"
        case .off: return ""
        }
    }

    var carbonFlags: UInt32 {
        switch self {
        case .controlOption: return UInt32(controlKey | optionKey)
        case .controlCommand: return UInt32(controlKey | cmdKey)
        case .optionCommand: return UInt32(optionKey | cmdKey)
        case .controlShift: return UInt32(controlKey | shiftKey)
        case .off: return 0
        }
    }

    var title: String { self == .off ? L("끔") : symbol }
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

    /// 사용자가 바에서 끌어 정한 순서. 여기 없는 항목은 메뉴바 순서대로 뒤에 온다.
    @Published var itemOrder: [String] {
        didSet { defaults.set(itemOrder, forKey: "itemOrder") }
    }

    /// When on, the bar lists only items the notch is currently hiding (groups can override).
    @Published var onlyNotchHidden: Bool {
        didSet { defaults.set(onlyNotchHidden, forKey: "onlyNotchHidden") }
    }

    /// Maximum width (points) of the scrollable strip before arrows/scrolling kick in.
    @Published var maxStripWidth: Double {
        didSet { defaults.set(maxStripWidth, forKey: "maxStripWidth") }
    }

    /// How many rows the bar uses (1–3); groups can override.
    @Published var rowCount: Int {
        didSet { defaults.set(rowCount, forKey: "rowCount") }
    }

    /// 구분선 왼쪽에 둔 항목을 메뉴바에서 실제로 숨긴다.
    @Published var hideInMenuBar: Bool {
        didSet { defaults.set(hideInMenuBar, forKey: "hideInMenuBar") }
    }

    /// 노치에 마우스를 잠깐 올리면 첫 그룹의 바를 연다.
    @Published var hoverToOpen: Bool {
        didSet { defaults.set(hoverToOpen, forKey: "hoverToOpen") }
    }

    @Published var hotKeyModifiers: HotKeyModifiers {
        didSet { defaults.set(hotKeyModifiers.rawValue, forKey: "hotKeyModifiers") }
    }

    /// 권한 문제를 볼 때만 켜는 ~/Library/Logs/Peeky.log.
    @Published var diagnosticLog: Bool {
        didSet { defaults.set(diagnosticLog, forKey: "diagnosticLog") }
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
            ? [ItemGroup(id: UUID(), name: L("기본"), symbol: ItemGroup.symbols[0])]
            : savedGroups
        assignments = (defaults.data(forKey: "assignments"))
            .flatMap { try? JSONDecoder().decode([String: UUID].self, from: $0) } ?? [:]
        excludedIDs = Set(defaults.stringArray(forKey: "excludedIDs") ?? [])
        itemOrder = defaults.stringArray(forKey: "itemOrder") ?? []
        onlyNotchHidden = defaults.object(forKey: "onlyNotchHidden") as? Bool ?? false
        maxStripWidth = defaults.object(forKey: "maxStripWidth") as? Double ?? 320
        rowCount = min(3, max(1, defaults.object(forKey: "rowCount") as? Int ?? 1))
        hideInMenuBar = defaults.object(forKey: "hideInMenuBar") as? Bool ?? false
        hoverToOpen = defaults.object(forKey: "hoverToOpen") as? Bool ?? false
        hotKeyModifiers = HotKeyModifiers(rawValue: defaults.object(forKey: "hotKeyModifiers") as? Int ?? 0) ?? .controlOption
        diagnosticLog = defaults.object(forKey: "diagnosticLog") as? Bool ?? false
    }

    // MARK: Groups

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
        let group = ItemGroup(id: UUID(), name: L("그룹 %ld", groups.count + 1), symbol: symbol)
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

    func rowCount(for group: UUID?) -> Int {
        min(3, max(1, groups.first { $0.id == group }?.rowCount ?? rowCount))
    }

    func onlyNotchHidden(for group: UUID?) -> Bool {
        groups.first { $0.id == group }?.onlyNotchHidden ?? onlyNotchHidden
    }

    // MARK: Order

    /// 바에서 끌어 놓은 결과를 저장한다. `ids`는 한 그룹 바의 새 순서.
    func setOrder(_ ids: [String]) {
        let moved = Set(ids)
        itemOrder = ids + itemOrder.filter { !moved.contains($0) }
    }

    /// 저장된 순서대로 정렬한다. 순서가 없는 항목은 원래(메뉴바) 순서를 지킨다.
    func ordered<T>(_ list: [T], id: (T) -> String) -> [T] {
        Self.ordered(list, by: itemOrder, id: id)
    }

    nonisolated static func ordered<T>(_ list: [T], by order: [String], id: (T) -> String) -> [T] {
        guard !order.isEmpty else { return list }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return list.enumerated()
            .sorted { a, b in
                let ra = rank[id(a.element)] ?? Int.max, rb = rank[id(b.element)] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }
}
