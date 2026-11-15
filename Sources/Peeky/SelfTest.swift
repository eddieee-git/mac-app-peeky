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
        print("버전 비교")
        expect(Updater.isNewer("0.10.0", than: "0.9.1"), "0.10.0 > 0.9.1")
        expect(Updater.isNewer("1.0", than: "0.9.9"), "1.0 > 0.9.9")
        expect(!Updater.isNewer("0.1.0", than: "0.1"), "0.1.0 == 0.1")
        expect(!Updater.isNewer("0.1.0", than: "0.2.0"), "0.1.0 < 0.2.0")

        print("릴리스 응답 읽기")
        let json = """
        {"tag_name":"v0.2.0","assets":[
          {"name":"Peeky-0.2.0.dmg","browser_download_url":"https://example.com/Peeky-0.2.0.dmg","digest":"sha256:ABC"},
          {"name":"Peeky-0.2.0.dmg.sig","browser_download_url":"https://example.com/Peeky-0.2.0.dmg.sig"}]}
        """
        let release = Updater.parse(Data(json.utf8))
        expect(release?.version == "0.2.0", "태그에서 v를 뗀 버전")
        expect(release?.dmg?.lastPathComponent == "Peeky-0.2.0.dmg", "dmg 주소")
        expect(release?.sha256 == "abc", "SHA-256 소문자")
        expect(release?.signature?.lastPathComponent == "Peeky-0.2.0.dmg.sig", "서명 파일 주소")

        print("업데이트 서명")
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("peeky".utf8)
        let signature = Data(try! key.signature(for: data).base64EncodedString().utf8)
        expect(Updater.isSigned(data, signature: signature, publicKey: publicKey), "맞는 서명 통과")
        expect(!Updater.isSigned(Data("other".utf8), signature: signature, publicKey: publicKey), "다른 파일 거부")
        expect(!Updater.isSigned(data, signature: signature), "다른 키 거부")
        expect(Data(base64Encoded: Updater.publicKey)?.count == 32, "앱에 넣은 공개 키 형식")

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

        print("순서")
        let sorted = Preferences.ordered(["a", "b", "c", "d"], by: ["c", "a"]) { $0 }
        expect(sorted == ["c", "a", "b", "d"], "저장한 순서 먼저, 나머지는 원래 순서")

        print("바꿔 넣을 수 있는 위치")
        expect(!Updater.canReplace(URL(fileURLWithPath: "/Volumes/Peeky/Peeky.app")), "dmg 안에서는 안 됨")

        print(failures == 0 ? "모두 통과" : "실패 \(failures)개")
        return failures == 0
    }
}
