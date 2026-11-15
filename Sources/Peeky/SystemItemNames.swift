import Foundation

/// 이름이 없는 메뉴바 항목(주로 제어 센터에 들어 있는 macOS 기본 항목)에 알아보기 쉬운 이름을 붙인다.
enum SystemItemNames {
    /// 식별자·설명·제목에 이 낱말이 들어 있으면 그 이름을 쓴다. 더 구체적인 낱말을 앞에 둔다.
    static let keywords: [(String, String)] = [
        ("keyboardbrightness", "키보드 밝기"),
        ("screenmirroring", "화면 미러링"),
        ("nowplaying", "지금 재생 중"),
        ("stagemanager", "스테이지 매니저"),
        ("controlcenter", "제어 센터"),
        ("bentobox", "제어 센터"),
        ("timemachine", "Time Machine"),
        ("textinput", "입력 소스"),
        ("accessibility", "손쉬운 사용"),
        ("battery", "배터리"),
        ("wifi", "Wi-Fi"),
        ("bluetooth", "블루투스"),
        ("airdrop", "AirDrop"),
        ("focus", "집중 모드"),
        ("display", "디스플레이"),
        ("brightness", "디스플레이"),
        ("sound", "소리"),
        ("volume", "소리"),
        ("clock", "시계"),
        ("siri", "Siri"),
        ("spotlight", "Spotlight"),
        ("vpn", "VPN"),
        ("hearing", "청각"),
        ("weather", "날씨"),
        ("user", "사용자 전환"),
    ]

    /// 항목에 보여 줄 이름을 고른다.
    static func label(bundleID: String, identifier: String?, description: String?, title: String?,
                      help: String?, appName: String, index: Int) -> String {
        let isApple = bundleID.hasPrefix("com.apple.")
        if isApple, let identifier, let name = match(identifier) { return L(name) }
        if let text = description ?? title ?? help { return text }
        if isApple {
            // 이름도 식별자도 없는 기본 항목: 같은 이름이 여러 줄 반복되지 않게 번호를 붙인다.
            if let identifier { return prettify(identifier) }
            return L("%@ 항목 %ld", appName, index + 1)
        }
        return appName
    }

    static func match(_ text: String) -> String? {
        let lower = text.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        return keywords.first { lower.contains($0.0) }?.1
    }

    /// "com.apple.menuextra.something" → "Something"
    static func prettify(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return tail.prefix(1).uppercased() + tail.dropFirst()
    }
}
