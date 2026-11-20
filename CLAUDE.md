> 문서·UI 규칙은 ../mac-app/STYLE.md를 따른다. 다르게 할 때는 여기에 이유를 적는다.

> 업데이트 코드(`AppUpdater.swift`)는 다섯 앱 공통이다. 여기서 고치지 않고 ../mac-app/shared/AppUpdater.swift를 고친 뒤 ../mac-app/scripts/sync-shared.sh로 복사한다. 이 앱에만 해당하는 값은 `UpdaterSetup.swift`에 있다. 시험할 때는 디버그 빌드에서 `-debugUpdateURL <주소>`, `-debugUpdatePublicKey <키>`, `-debugAppVersion <버전>`을 쓴다.

# Peeky 개발 메모

노치에 가려진 메뉴바 아이콘을 메뉴바 아래 바에 모아 보여 주는 macOS 메뉴바 앱. Swift Package 실행 파일 하나로,
Xcode 없이 Command Line Tools만으로 빌드한다. Apple 실리콘, macOS 14 이상. 저장소: `eddieee-git/mac-app-peeky` (공개).
번들 ID `com.eddieee.Peeky`.

## 지켜야 할 것

- **Apple 계정이 필요한 기능은 만들지 않는다.** 공증, Developer ID 서명 등. 앱은 이 Mac 전용 인증서(또는 임시) 서명이다.
- **다른 메뉴바 정리 앱의 이름이나 그 앱을 분석한 내용을 공개 문서·커밋 메시지에 쓰지 않는다.**
- **스크린샷에 개인 내용이 나오지 않게 한다.**
- 사용자 문구는 한국어, 말투는 "~해요". 문서는 README·CHANGELOG 한/영 두 벌.

## 명령

```bash
./scripts/test.sh                       # 빌드 + 자체 점검(--self-test). 실제 설정·권한은 건드리지 않음
./scripts/build-app.sh                  # build/Peeky.app + build/Peeky-<버전>.dmg (+ .sig)
PEEKY_DEBUG=1 ./scripts/build-app.sh    # 디버그 빌드, dmg 없음
./scripts/release.sh                    # 점검 → 빌드 → 태그 push → gh release create (dmg + .sig)
./scripts/make-signing-cert.sh          # (한 번) 이 Mac 전용 서명 인증서 "Peeky Local Signing"
swift scripts/make-icon.swift           # Resources/AppIcon.icns, docs/images/icon.png
swift scripts/sign-update.swift public  # 업데이트 서명 키의 공개 키 출력 (keygen | public | sign 파일)
```

## 권한 (손쉬운 사용 필수, 화면 기록 선택)

- macOS는 "번들 ID + 서명 인증서"로 앱을 알아본다. 인증서 없이 임시 서명하면 빌드할 때마다 권한이 풀린다.
- **인증서를 코드 서명용으로 신뢰해야 권한이 인식된다.** 신뢰하지 않은 인증서면 목록에서 켜도 계속 거부된다.
  `security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db <cert.pem>` (사용자가 직접, 암호 필요)
- 서명이나 번들 ID가 바뀐 뒤 목록의 옛 항목이 남아 있으면 `tccutil reset Accessibility|ScreenCapture com.eddieee.Peeky` 후 다시 허용.
- `CGPreflightScreenCaptureAccess()`는 믿지 않는다. 실제 `SCShareableContent` 호출로 확인한다(`ItemStore.checkScreenCapture`).
  사용자가 요청하기 전에는 이 호출을 하지 않는다(시스템 확인 창이 뜸). 화면 기록은 앱을 다시 열어야 적용된다.
- 문제를 볼 때는 진단 로그를 켜고 `~/Library/Logs/Peeky.log`(시작할 때 새로 씀)를 본다.
- 셸에서 `log`는 zsh 내장 명령과 겹친다. 시스템 로그는 `/usr/bin/log show`로 본다.

## 릴리스 순서

1. `Resources/Info.plist`의 `CFBundleShortVersionString`(그리고 `CFBundleVersion` +1)을 올린다.
2. `docs/releases/v<버전>.md`에 릴리스 노트를 쓴다(설치와 업데이트 → 새 기능 → 바뀐 점 → 알려진 제한 → `## English`).
3. README 두 개와 CHANGELOG 두 개를 함께 고친다.
4. 커밋하고 `main`을 push한 뒤 `./scripts/release.sh`.
5. 확인: `gh api repos/eddieee-git/mac-app-peeky/releases/latest --jq '.tag_name, .assets[].digest'`의 digest가 `shasum -a 256 build/Peeky-<버전>.dmg`와 같은지.

앱 안의 업데이트는 GitHub 최신 릴리스의 첫 `.dmg` 첨부와, 같은 이름에 `.sig`를 붙인 Ed25519 서명 파일을 쓴다.
dmg 안 앱 이름은 `Peeky.app`, 번들 ID와 버전은 태그와 맞아야 한다.

**업데이트 서명 키**
- 비밀 키는 저장소 밖 `~/.config/peeky/update-signing.key`(`PEEKY_UPDATE_KEY`로 바꿀 수 있음). 공개 키는 `UpdaterSetup.swift`의 `appPublicKey`.
- `build-app.sh`가 키가 있으면 `.sig`를 만들고, `release.sh`는 `.sig`가 없으면 멈춘다.
- **키를 잃어버리면 이미 설치된 앱은 새 버전을 자동으로 받지 못한다.** 따로 백업해 둔다.

## 구조 (Sources/Peeky)

| 파일 | 하는 일 |
|---|---|
| `main.swift` | 시작점. `--self-test`면 점검만 돌리고 끝냄 |
| `AppDelegate.swift` | 그룹마다 상태 아이콘, 단축키(보조 키 선택), 오른쪽 클릭 메뉴, 메뉴바 숨기기 켜고 끄기, 보이기/숨기기에 맞게 아이콘 정리(`arrangeMenuBar`), 앱 실행/종료 감지 |
| `ItemStore.swift` | 손쉬운 사용(`AXExtrasMenuBar`)으로 메뉴바 항목 수집(빠른 새로고침은 아는 앱만), 바뀐 아이콘만 캡처, 진단 로그 |
| `SystemItemNames.swift` | 이름 없는 macOS 기본 항목에 이름 붙이기(낱말 표, 구체적인 낱말이 앞) |
| `Taskbar.swift` | 바 패널. 그룹별 줄 수, 화살표·휠·키보드 스크롤, 끌어서 순서 바꾸기, 항목 클릭(숨긴 항목은 펼친 뒤 AXPress) |
| `MenuBarHider.swift` | 투명한 구분선과 ‹ › 버튼으로 메뉴바에서 숨기기, 새 아이콘 처음 자리(`StatusItemPlacement`), 아이콘 가려짐 확인(`StatusIconCheck`) |
| `ItemMover.swift` | ⌘ 끌기를 흉내 내 다른 앱 아이콘 옮기기 |
| `NotchGeometry.swift` | 노치 위치(`notchRect`), 항목이 가려졌는지·화면 밖인지 |
| `Preferences.swift` | 설정(UserDefaults): 그룹(그룹별 옵션), 항목별 그룹, 숨김, 순서, 표시, 단축키, 진단 로그 |
| `SettingsView.swift` | 설정 창(SwiftUI) |
| `Localization.swift` | `L()`과 영어 사전 |
| `AppUpdater.swift`(공통) / `UpdaterSetup.swift` | 최신 릴리스 확인 → dmg 내려받아 확인(Ed25519·SHA-256·번들 ID·버전·코드 서명) → 바꿔 넣고 다시 시작 |
| `HotKey.swift` | Carbon 전역 단축키(핸들러 하나를 id로 나눠 씀) |
| `AX.swift`, `AppRelauncher.swift` | 손쉬운 사용 도우미, 권한 요청, 다시 열기 |
| `SelfTest.swift` | 자체 점검 묶음 |

## 규칙과 함정

- macOS 26에서는 메뉴바 항목 창이 모두 Control Center 소유로 보인다. 어느 앱의 항목인지는 창 목록이 아니라 앱별 `AXExtrasMenuBar`로 알아낸다.
- 항목 id는 `번들ID|식별자`(식별자 → 설명 → 도움말 → 제목 순). 제목은 시계처럼 계속 바뀔 수 있어 마지막에 쓴다.
- 상태 아이콘에 `AXPress`를 하면 메뉴가 닫힐 때까지 돌아오지 않을 수 있어 메인 스레드 밖에서 부른다.
- `NSScreen`은 메인 스레드에서만 쓴다. 노치 판정은 백그라운드로 넘기기 전에 해 둔다.
- 설정 추가: `@Published var x { didSet { defaults.set(...) } }`, `init`에서 `defaults.object(forKey:) as? … ?? 기본값`.
- **번역**: 사용자 문구는 `L("한국어")`로 쓰고 `Localization.pairs`에 영어를 더한다. 같은 키가 두 번 들어가면 자체 점검이 실패한다.
- **구분선 숨기기**: 구분선 길이를 10,000pt로 늘려 왼쪽 항목을 화면 밖으로 민다. 앱이 끝날 때는 펼쳐 둔다(`applicationWillTerminate`).
- **새 상태 아이콘 자리**: `NSStatusItem Preferred Position <autosaveName>`을 처음 한 번만 넣는다. 사용자가 옮긴 값은 건드리지 않는다.
- **권한 확인 로그**는 설정 → 고급 → 진단 로그를 켜야 남는다(`defaults write com.eddieee.Peeky diagnosticLog -bool true`).
