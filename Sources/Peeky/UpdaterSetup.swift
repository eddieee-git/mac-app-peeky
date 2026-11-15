import Foundation

/// 공통 업데이트(AppUpdater.swift)에 Peeky 정보를 넣는다. AppUpdater.swift는 mac-app/shared에서 복사해 오므로 여기만 고친다.
extension AppUpdater {
    /// `~/.config/peeky/update-signing.key`의 공개 키 (scripts/sign-update.swift)
    nonisolated static let appPublicKey = "lKHkMa6qNWeTcsBM/gHZUT8bVtobjrZrSlFy4xjEExk="
    nonisolated static let appSignatureFormat = SignatureFormat.dmg

    static let shared = AppUpdater(.init(
        appName: "Peeky",
        repo: "eddieee-git/mac-app-peeky",
        publicKey: appPublicKey,
        signatureFormat: appSignatureFormat,
        isEnglish: { !Localization.isKorean },
        log: { ItemStore.log($0) }
    ))
}
