import CryptoKit
import Foundation

/// `scripts/test.sh`가 돌리는 자체 점검. 실제 설정·권한·메뉴 막대는 건드리지 않는다.
enum SelfTest {
    private static var failures = 0

    private static func expect(_ condition: Bool, _ name: String) {
        print(condition ? "  ✓ \(name)" : "  ✗ \(name)")
        if !condition { failures += 1 }
    }

    static func run() -> Bool {
        print("업데이트 (공통)")
        let updateFailures = AppUpdater.selfTest(appName: "Peeky", publicKey: AppUpdater.appPublicKey, format: AppUpdater.appSignatureFormat)
        updateFailures.forEach { expect(false, $0) }
        expect(updateFailures.isEmpty, "공통 업데이트 점검")

        print("번역")
        expect(Localization.duplicateKeys.isEmpty, "사전에 같은 키 없음 \(Localization.duplicateKeys)")
        expect(Localization.english["그룹 %ld"] == "Group %ld", "영어 사전 읽기")

        print("기본 항목 이름")
        expect(SystemItemNames.match("com.apple.menuextra.battery") == "배터리", "배터리")
        expect(SystemItemNames.match("com.apple.menuextra.keyboard-brightness") == "키보드 밝기", "키보드 밝기가 디스플레이보다 먼저")
        expect(SystemItemNames.match("com.apple.menuextra.screenmirroring") == "화면 미러링", "화면 미러링이 디스플레이보다 먼저")
        expect(SystemItemNames.match("com.example.unknown") == nil, "모르는 식별자")
        let unnamed = SystemItemNames.label(bundleID: "com.apple.controlcenter", identifier: nil, description: nil,
                                            title: nil, help: nil, appName: "Control Center", index: 2)
        expect(unnamed != "Control Center", "이름 없는 기본 항목에 번호")
        let thirdParty = SystemItemNames.label(bundleID: "com.example.app", identifier: "x", description: "Sync",
                                               title: nil, help: nil, appName: "Example", index: 0)
        expect(thirdParty == "Sync", "다른 앱은 설명 그대로")

        print("항목 이름")
        expect(firstLine("Cloudflare One Client\n\nAttention - Disconnected") == "Cloudflare One Client",
               "상태가 덧붙은 도움말은 첫 줄만")
        expect(firstLine("  \n") == nil, "빈 문자열은 없음")

        print("순서")
        let sorted = Preferences.ordered(["a", "b", "c", "d"], by: ["c", "a"]) { $0 }
        expect(sorted == ["c", "a", "b", "d"], "저장한 순서 먼저, 나머지는 원래 순서")

        print(failures == 0 ? "모두 통과" : "실패 \(failures)개")
        return failures == 0
    }
}
