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

    /// 화면 기록 권한이 없을 때 대신 보여 줄 모양(SF Symbols). 없으면 앱 아이콘을 쓴다.
    /// 제어 센터 안의 항목은 앱 아이콘이 모두 같아서 구별이 안 되기 때문이다.
    static let symbols: [String: String] = [
        "keyboardbrightness": "light.max", "screenmirroring": "rectangle.on.rectangle",
        "nowplaying": "play.circle", "stagemanager": "square.on.square", "controlcenter": "switch.2",
        "bentobox": "switch.2", "timemachine": "clock.arrow.circlepath", "textinput": "keyboard",
        "accessibility": "accessibility", "battery": "battery.75percent", "wifi": "wifi",
        "bluetooth": "dot.radiowaves.left.and.right", "airdrop": "dot.radiowaves.up.forward",
        "focus": "moon", "display": "sun.max", "brightness": "sun.max", "sound": "speaker.wave.2",
        "volume": "speaker.wave.2", "clock": "clock", "siri": "mic", "spotlight": "magnifyingglass",
        "vpn": "network.badge.shield.half.filled", "hearing": "ear", "weather": "cloud.sun",
        "user": "person.crop.circle",
    ]

    /// macOS 기본 항목이면 맞는 모양의 이름. `texts`는 식별자·설명 등 항목을 알아볼 단서.
    static func symbol(bundleID: String, texts: [String?]) -> String? {
        guard bundleID.hasPrefix("com.apple.") else { return nil }
        if bundleID == "com.apple.TextInputMenuAgent" { return symbols["textinput"] }
        if bundleID == "com.apple.Spotlight" { return symbols["spotlight"] }
        for text in texts.compactMap({ $0 }) {
            let lower = text.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
            if let key = keywords.map(\.0).first(where: { lower.contains($0) }), let symbol = symbols[key] { return symbol }
        }
        return nil
    }

    /// 메뉴바 아이콘을 띄우는 도우미 프로세스의 이름 대신 쓸 앱 이름.
    static let helperAppNames: [String: String] = [
        "org.pqrs.Karabiner-Console-User-Server": "Karabiner-Elements",
        "org.pqrs.Karabiner-Menu": "Karabiner-Elements",
        "com.apple.TextInputMenuAgent": "입력 소스",
        "com.apple.Spotlight": "Spotlight",
    ]

    /// 앱이 붙였지만 뜻이 없는 이름. 이런 이름이면 앱 이름을 쓴다.
    static let genericNames: Set<String> = ["menu", "item", "status", "statusitem", "status item", "menubar", "icon", "button"]

    static func appName(bundleID: String, fallback: String) -> String {
        helperAppNames[bundleID].map { L($0) } ?? fallback
    }

    /// 항목에 보여 줄 이름을 고른다.
    static func label(bundleID: String, identifier: String?, description: String?, title: String?,
                      help: String?, appName: String, index: Int) -> String {
        let isApple = bundleID.hasPrefix("com.apple.")
        if isApple, let identifier, let name = match(identifier) { return L(name) }
        if bundleID == "com.apple.TextInputMenuAgent" { return L("입력 소스") }
        if let text = description ?? title ?? help, !genericNames.contains(text.lowercased()) { return text }
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
