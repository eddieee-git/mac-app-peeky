import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ItemStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updater = AppUpdater.shared
    @State private var axTrusted = AX.isTrusted
    @State private var search = ""
    /// 메뉴바에서 안 보이는 Peeky 그룹 아이콘 이름들.
    @State private var hiddenIcons: [String] = []
    /// "system" | "ko" | "en". 문구는 시작할 때 한 번 정해지므로 바꾸면 다시 열어야 한다.
    @State private var language = UserDefaults.standard.string(forKey: "language") ?? "system"
    private let launchLanguage = UserDefaults.standard.string(forKey: "language") ?? "system"

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Form {
                if !hiddenIcons.isEmpty { hiddenIconSection }
                permissionsSection
                itemsSection
                generalSection
                updateSection
                AppAboutSections(appName: "Peeky", english: !Localization.isKorean)
            }
            .formStyle(.grouped)
            .tabItem { Text(L("기본 설정")) }
            .tag(0)

            Form {
                barSection
                menuBarSection
                groupsSection
                advancedSection
            }
            .formStyle(.grouped)
            .tabItem { Text(L("고급")) }
            .tag(1)
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("항목 검색"))
        .frame(minWidth: 500, minHeight: 560)
        .onAppear {
            store.refresh(full: true)
            hiddenIcons = StatusIconCheck.hiddenGroupNames()
        }
        .onReceive(poll) { _ in
            let hidden = StatusIconCheck.hiddenGroupNames()
            if hidden != hiddenIcons { hiddenIcons = hidden }
            let nowTrusted = AX.isTrusted
            if nowTrusted != axTrusted {
                axTrusted = nowTrusted
                store.refresh(full: true)
            }
        }
    }

    // MARK: Sections

    private var hiddenIconSection: some View {
        Section {
            Label(L("Peeky 아이콘이 메뉴바에서 안 보여요 (%@)", hiddenIcons.joined(separator: ", ")),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(prefs.hotKeyModifiers == .off
                 ? L("노치에 가려졌거나 메뉴바에 자리가 없어요. ⌘를 누른 채 다른 아이콘을 왼쪽으로 옮겨 자리를 만들고, Peeky 아이콘은 오른쪽 끝으로 옮겨 두세요. 그래도 안 보이면 시스템 설정 → 메뉴 막대에서 Peeky가 켜져 있는지 확인하세요.")
                 : L("노치에 가려졌거나 메뉴바에 자리가 없어요. 단축키 %@1로 바를 열 수 있어요. ⌘를 누른 채 다른 아이콘을 왼쪽으로 옮겨 자리를 만들고, Peeky 아이콘은 오른쪽 끝으로 옮겨 두세요. 그래도 안 보이면 시스템 설정 → 메뉴 막대에서 Peeky가 켜져 있는지 확인하세요.", prefs.hotKeyModifiers.symbol))
                .font(.callout).foregroundStyle(.secondary)
            Button(L("Peeky 아이콘을 오른쪽 끝으로 옮기기")) { StatusIconCheck.resetPositions() }
        }
    }

    private var permissionsSection: some View {
        Section(L("권한")) {
            permissionRow(title: L("손쉬운 사용 (필수)"),
                          detail: L("다른 앱의 메뉴바 항목을 찾고 클릭하는 데 필요해요."),
                          granted: axTrusted, showsRelaunch: false) {
                AX.requestTrust()
                AX.openAccessibilitySettings()
            }
            permissionRow(title: L("화면 기록 (선택)"),
                          detail: L("실제 아이콘 모양을 보여 줘요. 없으면 앱 아이콘으로 대신 보여요. 허용한 뒤 Peeky를 다시 열어야 적용돼요."),
                          granted: store.screenCaptureOK, showsRelaunch: true) {
                AX.requestScreenCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { store.checkScreenCapture() }
            }
        }
    }

    private var barSection: some View {
        Section(L("Peeky 바 모양")) {
            Picker(L("줄 수"), selection: $prefs.rowCount) {
                Text(L("한 줄")).tag(1)
                Text(L("두 줄")).tag(2)
                Text(L("세 줄")).tag(3)
            }
            .pickerStyle(.segmented)
            LabeledContent(L("바 최대 너비")) {
                HStack {
                    Slider(value: $prefs.maxStripWidth, in: 120...900, step: 20)
                        .frame(width: 180)
                    Text("\(Int(prefs.maxStripWidth))pt").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Picker(L("단축키"), selection: $prefs.hotKeyModifiers) {
                ForEach(HotKeyModifiers.allCases) { Text($0.title).tag($0) }
            }
            .help(L("그룹 단축키에 쓸 보조 키. 1~9는 각 그룹, B는 첫 그룹이에요."))
            LabeledContent(L("바 안의 순서")) {
                Button(L("순서 초기화")) { prefs.itemOrder = [] }
                    .disabled(prefs.itemOrder.isEmpty)
                    .help(L("바에서 끌어 바꾼 순서를 메뉴바 순서로 되돌려요"))
            }
        }
    }

    private var generalSection: some View {
        Section(L("일반")) {
            Toggle(L("로그인 시 실행"), isOn: Binding(get: { prefs.launchAtLogin },
                                                  set: { prefs.launchAtLogin = $0 }))
            Picker(L("언어"), selection: $language) {
                Text(L("시스템 설정 따르기")).tag("system")
                Text("한국어").tag("ko")
                Text("English").tag("en")
            }
            .onChange(of: language) { _, new in
                if new == "system" { UserDefaults.standard.removeObject(forKey: "language") }
                else { UserDefaults.standard.set(new, forKey: "language") }
            }
            if language != launchLanguage {
                HStack {
                    Text(L("언어를 바꾸면 Peeky를 다시 열어야 적용돼요.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Peeky 다시 열기")) { AppRelauncher.relaunch() }
                }
            }
        }
    }

    private var menuBarSection: some View {
        Section {
            LabeledContent(L("아이콘 자리가 고른 대로가 아니면")) {
                Button(L("다시 정리")) { StatusIconCheck.arrange() }
                    .disabled(!prefs.hideInMenuBar)
            }
            LabeledContent(L("Peeky 아이콘이 안 보이면")) {
                Button(L("Peeky 아이콘을 오른쪽 끝으로 옮기기")) { StatusIconCheck.resetPositions() }
            }
        } header: {
            Text(L("메뉴바 정리"))
        } footer: {
            Text(L("메뉴바에서 숨기기를 켜면 › 버튼이 생겨요. › 오른쪽 아이콘은 늘 보이고, 왼쪽 아이콘은 숨겨져요. ‹ ›를 누르면 잠깐 펼치거나 다시 숨겨요. 노치 뒤에 있어 잡을 수 없는 아이콘은 옮기지 못해요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var groupsSection: some View {
        Section {
            ForEach(Array(prefs.groups.enumerated()), id: \.element.id) { index, group in
                groupRow(group, index: index)
            }
        } header: {
            HStack {
                Text(L("그룹"))
                Spacer()
                Button { prefs.addGroup() } label: { Label(L("그룹 추가"), systemImage: "plus") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        } footer: {
            Text(L("그룹마다 메뉴바에 아이콘이 하나씩 생기고, 누르면 그 그룹의 항목만 바에 보여요. ⋯에서 그룹마다 줄 수와 표시 방식을 따로 정할 수 있어요."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("그룹은 Peeky 바에 보일 항목만 정해요. 메뉴바에서도 빼려면 「메뉴바 정리」에서 숨기기를 켜세요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var itemsSection: some View {
        Section {
            Toggle(isOn: $prefs.hideInMenuBar) {
                Text(L("「숨기기」 아이콘을 메뉴바에서 숨기기"))
                Text(L("켜면 Peeky가 아이콘 자리를 옮겨 정리해요. 정리하는 동안 마우스가 잠깐 움직여요."))
            }
            if !axTrusted {
                Text(L("손쉬운 사용 권한을 주면 항목 목록이 여기에 나타나요.")).foregroundStyle(.secondary)
            } else if filteredItems.isEmpty {
                Text(L("찾은 항목이 없어요.")).foregroundStyle(.secondary)
            } else {
                ForEach(filteredItems) { item in itemRow(item) }
            }
        } header: {
            HStack {
                Text(L("메뉴바 아이콘"))
                Spacer()
                Menu(L("모두")) {
                    Button(L("모두 보이기")) { filteredItems.forEach { prefs.assign($0.id, to: nil) } }
                    ForEach(prefs.groups) { group in
                        Button(prefs.groups.count == 1 ? L("모두 숨기기") : L("모두 숨기기 · %@", group.name)) {
                            filteredItems.forEach { prefs.assign($0.id, to: group.id) }
                        }
                    }
                }
                .fixedSize()
                Button { store.refresh(full: true) } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("새로고침"))
            }
            .buttonStyle(.borderless)
            .font(.callout)
        } footer: {
            Text(L("「보이기」는 메뉴바에 그대로 둬요. 「숨기기」는 메뉴바에서 빼고 Peeky 바에 모아요. Peeky 아이콘을 누르면 바가 열리고, 바에서 누르면 원래 메뉴가 열려요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var updateSection: some View {
        AppUpdaterSection(updater: updater)
    }

    private var advancedSection: some View {
        Section {
            Toggle(L("진단 로그 남기기"), isOn: $prefs.diagnosticLog)
            if prefs.diagnosticLog {
                Button(L("로그 파일 보기")) {
                    NSWorkspace.shared.selectFile(ItemStore.logPath, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.link)
            }
        } header: {
            Text(L("문제 해결"))
        } footer: {
            Text(L("권한이 인식되지 않을 때 원인을 찾는 데 써요. ~/Library/Logs/Peeky.log에 권한 상태만 기록하고, 끄면 파일을 지워요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filteredItems: [MenuBarItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Rows

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, showsRelaunch: Bool,
                               request: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(L("허용하기"), action: request)
                if showsRelaunch {
                    Button(L("다시 열기")) { AppRelauncher.relaunch() }
                        .help(L("시스템 설정에서 켠 뒤에는 Peeky를 다시 열어야 적용돼요"))
                }
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: ItemGroup, index: Int) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(get: { group.symbol },
                                          set: { symbol in editGroup(group.id) { $0.symbol = symbol } })) {
                ForEach(ItemGroup.symbols, id: \.self) { Image(systemName: $0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("", text: Binding(get: { group.name },
                                        set: { name in editGroup(group.id) { $0.name = name } }),
                      prompt: Text(L("그룹 이름")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Text(L("%ld개", store.items.filter { prefs.group(for: $0.id) == group.id }.count))
                .monospacedDigit().foregroundStyle(.secondary)
            if prefs.hotKeyModifiers != .off, index < 9 {
                Text("\(prefs.hotKeyModifiers.symbol)\(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            groupOptionsMenu(group)
            Button { prefs.removeGroup(group.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(prefs.groups.count <= 1)
                .help(prefs.groups.count <= 1 ? L("그룹은 하나 이상 있어야 해요") : L("그룹 삭제 (항목은 첫 그룹으로 이동)"))
        }
    }

    private func groupOptionsMenu(_ group: ItemGroup) -> some View {
        Menu {
            Picker(L("줄 수"), selection: Binding(get: { group.rowCount ?? 0 },
                                                set: { value in editGroup(group.id) { $0.rowCount = value == 0 ? nil : value } })) {
                Text(L("전체 설정 따르기")).tag(0)
                Text(L("한 줄")).tag(1)
                Text(L("두 줄")).tag(2)
                Text(L("세 줄")).tag(3)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("이 그룹만의 설정"))
    }

    private func editGroup(_ id: UUID, _ change: (inout ItemGroup) -> Void) {
        guard var group = prefs.groups.first(where: { $0.id == id }) else { return }
        change(&group)
        prefs.updateGroup(group)
    }

    @ViewBuilder
    private func itemRow(_ item: MenuBarItem) -> some View {
        HStack(spacing: 10) {
            itemIcon(item).frame(width: 34, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label).lineLimit(1)
                if item.label != item.appName {
                    Text(item.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let status = status(of: item) {
                Text(status.text)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                    .help(status.help)
            }
            if item.isFixed {
                Text(L("항상 보임")).foregroundStyle(.secondary)
                    .help(L("macOS가 이 아이콘은 옮기지 못하게 해서 늘 메뉴바에 보여요."))
            } else if prefs.groups.count == 1 {
                placementPicker(item).pickerStyle(.segmented).fixedSize()
            } else {
                placementPicker(item).pickerStyle(.menu).fixedSize()
            }
        }
    }

    /// 아이콘마다 「보이기」 또는 「숨기기(· 그룹)」
    private func placementPicker(_ item: MenuBarItem) -> some View {
        Picker("", selection: Binding(get: { prefs.group(for: item.id) },
                                      set: { prefs.assign(item.id, to: $0) })) {
            Text(L("보이기")).tag(UUID?.none)
            ForEach(prefs.groups) { group in
                Text(prefs.groups.count == 1 ? L("숨기기") : L("숨기기 · %@", group.name)).tag(Optional(group.id))
            }
        }
        .labelsHidden()
    }

    /// 메뉴바에서 안 보이는 이유를 짧게. 보이면 nil.
    private func status(of item: MenuBarItem) -> (text: String, help: String)? {
        guard item.isHiddenByNotch else { return nil }
        if let frame = item.frame, !NotchGeometry.isOffScreen(frame) {
            return (L("노치 뒤"), L("노치에 가려 메뉴바에서 안 보여요. Peeky 바에서 누를 수 있어요."))
        }
        if prefs.hideInMenuBar {
            return (L("숨겨 둠"), L("› 버튼 왼쪽에 있어서 메뉴바에서 숨겼어요. Peeky 바에서 누를 수 있어요."))
        }
        return (L("자리 없음"), L("메뉴바에 자리가 없어 밀려났어요. Peeky 바에서 누를 수 있어요."))
    }

    @ViewBuilder
    private func itemIcon(_ item: MenuBarItem) -> some View {
        if let image = store.image(for: item) {
            Image(nsImage: image).resizable().renderingMode(image.isTemplate ? .template : .original)
                .aspectRatio(contentMode: .fit)
        } else if let icon = item.appIcon {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
        }
    }
}
