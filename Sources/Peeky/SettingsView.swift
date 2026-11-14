import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ItemStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updater = Updater.shared
    @State private var axTrusted = AX.isTrusted
    @State private var search = ""

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("권한") {
                permissionRow(title: "손쉬운 사용 (필수)",
                              detail: "다른 앱의 메뉴 막대 항목을 찾고 클릭하는 데 필요해요.",
                              granted: axTrusted) {
                    AX.requestTrust()
                    AX.openAccessibilitySettings()
                }
                permissionRow(title: "화면 기록 (선택)",
                              detail: "실제 아이콘 모양을 보여줘요. 없으면 앱 아이콘으로 대신 표시해요. 허용한 뒤 Peeky를 다시 열어야 적용돼요.",
                              granted: store.screenCaptureOK) {
                    AX.requestScreenCapture()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { store.checkScreenCapture() }
                }
            }

            Section("바 표시") {
                Toggle("노치에 가려진 항목만 표시", isOn: $prefs.onlyNotchHidden)
                Picker("줄 수", selection: $prefs.rowCount) {
                    Text("한 줄").tag(1)
                    Text("두 줄").tag(2)
                    Text("세 줄").tag(3)
                }
                .pickerStyle(.segmented)
                LabeledContent("바 최대 너비") {
                    HStack {
                        Slider(value: $prefs.maxStripWidth, in: 120...900, step: 20)
                            .frame(width: 180)
                        Text("\(Int(prefs.maxStripWidth))pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Toggle("로그인 시 실행", isOn: Binding(get: { prefs.launchAtLogin },
                                                  set: { prefs.launchAtLogin = $0 }))
                LabeledContent("단축키") { Text("⌃⌥1~9 그룹 열기 · ⌃⌥B 첫 그룹 · ← → 이동 · esc 닫기").foregroundStyle(.secondary) }
            }

            Section {
                ForEach(Array(prefs.groups.enumerated()), id: \.element.id) { index, group in
                    groupRow(group, index: index)
                }
            } header: {
                HStack {
                    Text("그룹")
                    Spacer()
                    Button { prefs.addGroup() } label: { Label("그룹 추가", systemImage: "plus") }
                }
                .buttonStyle(.borderless)
                .font(.callout)
            } footer: {
                Text("그룹마다 메뉴 막대에 아이콘이 하나씩 생기고, 누르면 그 그룹의 항목만 바에 보여요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if !axTrusted {
                    Text("손쉬운 사용 권한을 주면 항목 목록이 여기에 나타나요.").foregroundStyle(.secondary)
                } else if filteredItems.isEmpty {
                    Text("찾은 항목이 없어요.").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredItems) { item in itemRow(item) }
                }
            } header: {
                HStack {
                    Text("항목별 그룹")
                    Spacer()
                    Menu("모두 옮기기") {
                        ForEach(prefs.groups) { group in
                            Button(group.name) { filteredItems.forEach { prefs.assign($0.id, to: group.id) } }
                        }
                        Divider()
                        Button("숨김") { filteredItems.forEach { prefs.assign($0.id, to: nil) } }
                    }
                    .fixedSize()
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help("새로고침")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            } footer: {
                Text("각 항목이 어느 그룹 바에 보일지 고르세요. 「숨김」은 어느 바에도 안 나와요. 바의 항목을 클릭하면 실제 메뉴가 열리고, 오른쪽 클릭은 보조 메뉴를 시도해요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("업데이트") {
                LabeledContent("버전") { Text(updater.currentVersion).monospacedDigit() }
                Toggle("새 버전이 나오면 자동으로 설치", isOn: $updater.autoInstall)
                HStack {
                    Text(updateStatus).foregroundStyle(.secondary)
                    Spacer()
                    if case .available = updater.state {
                        Button("지금 설치") { updater.installPending() }
                    }
                    Button("지금 확인") { updater.checkNow() }
                        .disabled(updater.state == .checking)
                }
                Link("릴리스 노트 보기", destination: Updater.releasesPage).font(.callout)
            }
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbar, prompt: "항목 검색")
        .frame(minWidth: 480, minHeight: 560)
        .onAppear { store.refresh() }
        .onReceive(poll) { _ in
            let nowTrusted = AX.isTrusted
            if nowTrusted != axTrusted {
                axTrusted = nowTrusted
                store.refresh()
            }
        }
    }

    private var updateStatus: String {
        switch updater.state {
        case .idle: return "하루에 한 번 GitHub에서 새 버전을 확인해요"
        case .checking: return "확인하는 중…"
        case .upToDate: return "최신 버전이에요"
        case .available(let v): return "새 버전 \(v)이 있어요"
        case .installing(let v): return "\(v) 설치하는 중… 곧 다시 시작돼요"
        case .failed(let message): return message
        }
    }

    private var filteredItems: [MenuBarItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("허용하기", action: request)
                if title.hasPrefix("화면") {
                    Button("다시 열기") { AppRelauncher.relaunch() }
                        .help("시스템 설정에서 켠 뒤에는 Peeky를 다시 열어야 적용돼요")
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
                      prompt: Text("그룹 이름"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Text("\(store.items.filter { prefs.group(for: $0.id) == group.id }.count)개")
                .monospacedDigit().foregroundStyle(.secondary)
            if index < 9 {
                Text("⌃⌥\(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            Button { prefs.removeGroup(group.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(prefs.groups.count <= 1)
                .help(prefs.groups.count <= 1 ? "그룹은 하나 이상 있어야 해요" : "그룹 삭제 (항목은 첫 그룹으로 이동)")
        }
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
                Text("가려짐")
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
                Text("숨김").tag(UUID?.none)
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
