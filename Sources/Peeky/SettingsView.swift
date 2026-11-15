import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ItemStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updater = AppUpdater.shared
    @State private var axTrusted = AX.isTrusted
    @State private var search = ""

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            permissionsSection
            barSection
            menuBarSection
            groupsSection
            itemsSection
            updateSection
            advancedSection
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbar, prompt: L("항목 검색"))
        .frame(minWidth: 500, minHeight: 560)
        .onAppear { store.refresh(full: true) }
        .onReceive(poll) { _ in
            let nowTrusted = AX.isTrusted
            if nowTrusted != axTrusted {
                axTrusted = nowTrusted
                store.refresh(full: true)
            }
        }
    }

    // MARK: Sections

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
        Section(L("바 표시")) {
            Toggle(L("노치에 가려진 항목만 표시"), isOn: $prefs.onlyNotchHidden)
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
            Toggle(L("노치에 마우스를 올리면 첫 그룹 바 열기"), isOn: $prefs.hoverToOpen)
                .disabled(NotchGeometry.notchScreen == nil && !prefs.hoverToOpen)
                .help(NotchGeometry.notchScreen == nil ? L("노치가 있는 화면에서만 동작해요") : "")
            Picker(L("단축키"), selection: $prefs.hotKeyModifiers) {
                ForEach(HotKeyModifiers.allCases) { Text($0.title).tag($0) }
            }
            .help(L("그룹 단축키에 쓸 보조 키. 1~9는 각 그룹, B는 첫 그룹이에요."))
            Toggle(L("로그인 시 실행"), isOn: Binding(get: { prefs.launchAtLogin },
                                                  set: { prefs.launchAtLogin = $0 }))
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle(L("메뉴바에서 항목 숨기기"), isOn: $prefs.hideInMenuBar)
        } header: {
            Text(L("메뉴바 정리"))
        } footer: {
            Text(L("켜면 메뉴바에 구분선(╱)이 생겨요. ⌘를 누른 채 숨길 아이콘을 구분선 왼쪽으로 끌어다 놓으세요. 구분선 왼쪽 항목은 메뉴바에서 사라지고 Peeky 바에서만 보여요. Peeky 아이콘은 구분선 오른쪽에 두세요. 구분선을 누르면 펼치거나 접어요."))
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
        }
    }

    private var itemsSection: some View {
        Section {
            if !axTrusted {
                Text(L("손쉬운 사용 권한을 주면 항목 목록이 여기에 나타나요.")).foregroundStyle(.secondary)
            } else if filteredItems.isEmpty {
                Text(L("찾은 항목이 없어요.")).foregroundStyle(.secondary)
            } else {
                ForEach(filteredItems) { item in itemRow(item) }
            }
        } header: {
            HStack {
                Text(L("항목별 그룹"))
                Spacer()
                Menu(L("모두 옮기기")) {
                    ForEach(prefs.groups) { group in
                        Button(group.name) { filteredItems.forEach { prefs.assign($0.id, to: group.id) } }
                    }
                    Divider()
                    Button(L("메뉴바에만")) { filteredItems.forEach { prefs.assign($0.id, to: nil) } }
                }
                .fixedSize()
                Button(L("순서 초기화")) { prefs.itemOrder = [] }
                    .disabled(prefs.itemOrder.isEmpty)
                    .help(L("바에서 끌어 바꾼 순서를 메뉴바 순서로 되돌려요"))
                Button { store.refresh(full: true) } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("새로고침"))
            }
            .buttonStyle(.borderless)
            .font(.callout)
        } footer: {
            Text(L("각 항목이 어느 그룹 바에 보일지 고르세요. 「메뉴바에만」은 Peeky 바에 넣지 않고 메뉴바에 그대로 둬요. 바의 항목을 클릭하면 실제 메뉴가 열리고, 오른쪽 클릭은 보조 메뉴를 시도해요. 바에서 항목을 끌면 순서를 바꿀 수 있어요."))
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
            Text(L("고급"))
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
            Picker(L("표시할 항목"), selection: Binding(get: { group.onlyNotchHidden.map { $0 ? 1 : 2 } ?? 0 },
                                                   set: { value in editGroup(group.id) { $0.onlyNotchHidden = value == 0 ? nil : value == 1 } })) {
                Text(L("전체 설정 따르기")).tag(0)
                Text(L("노치에 가려진 항목만")).tag(1)
                Text(L("그룹의 모든 항목")).tag(2)
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
            if item.isHiddenByNotch {
                Text(L("가려짐"))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
            Picker("", selection: Binding(get: { prefs.group(for: item.id) },
                                          set: { prefs.assign(item.id, to: $0) })) {
                ForEach(prefs.groups) { group in
                    Label(group.name, systemImage: group.symbol).tag(Optional(group.id))
                }
                Divider()
                Text(L("메뉴바에만")).tag(UUID?.none)
            }
            .labelsHidden()
            .fixedSize()
        }
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
