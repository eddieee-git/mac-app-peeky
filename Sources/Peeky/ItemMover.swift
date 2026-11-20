import AppKit

/// 다른 앱의 메뉴바 아이콘을 옮긴다. 사용자가 ⌘를 누른 채 끄는 동작을 그대로 흉내 낸다
/// (macOS가 다른 앱의 상태 아이콘 자리를 바꾸는 다른 방법을 주지 않는다). 손쉬운 사용 권한이 필요하다.
enum ItemMover {
    struct Move {
        /// 옮길 아이콘의 현재 자리(CG 전역 좌표, 왼쪽 위 원점)
        let from: CGRect
        /// 놓을 x 좌표(전역)
        let toX: CGFloat
    }

    /// 순서대로 끌어 옮긴 뒤 마우스를 원래 자리로 돌려놓고 `completion`을 메인 스레드에서 부른다.
    static func perform(_ moves: [Move], completion: @escaping @Sendable () -> Void) {
        guard !moves.isEmpty else { completion(); return }
        let original = CGEvent(source: nil)?.location
        DispatchQueue.global(qos: .userInitiated).async {
            for move in moves { drag(move) }
            if let original {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: original,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private static func drag(_ move: Move) {
        let src = CGEventSource(stateID: .hidSystemState)
        let start = CGPoint(x: move.from.midX, y: move.from.midY)
        let end = CGPoint(x: move.toX, y: move.from.midY)
        func post(_ type: CGEventType, _ point: CGPoint, command: Bool) {
            let event = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            if command { event?.flags = .maskCommand }
            event?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start, command: false)
        usleep(30_000)
        post(.leftMouseDown, start, command: true)
        usleep(150_000)
        // 조금씩 움직여야 메뉴바가 끌기로 알아본다.
        let steps = 12
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y), command: true)
            usleep(20_000)
        }
        usleep(120_000)
        post(.leftMouseUp, end, command: true)
        usleep(250_000)
    }
}
