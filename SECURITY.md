# 보안 · Security

[한국어](#한국어) · [English](#english)

## 한국어

### 지원하는 버전

가장 최근 릴리스만 고쳐요. Peeky는 하루에 한 번 새 버전을 확인하니 최신 버전으로 업데이트해 주세요.

### 취약점 알리기

보안 문제는 공개 이슈에 올리지 말고, 저장소의 **Security → Report a vulnerability**로 비공개로 알려 주세요. 다음을 적어 주시면 도움이 돼요.

- Peeky와 macOS 버전
- 무엇이 문제인지, 다시 일으키는 방법
- 예상되는 피해

혼자 만드는 무료 앱이라 답이 늦을 수 있지만, 확인되면 고친 버전을 릴리스하고 변경 기록에 적어요.

### Peeky가 지키는 것

- 메뉴바 항목과 화면 내용은 어디에도 보내지 않아요. 네트워크는 GitHub 업데이트 확인에만 써요.
- 진단 로그는 설정에서 켤 때만 남기고, 권한 상태만 적어요.
- 업데이트는 https GitHub 주소에서만 받고, GitHub가 알려 준 SHA-256과 만든 사람의 Ed25519 서명이 맞을 때만 설치해요.
- Apple 공증은 받지 않았어요. 처음 실행할 때 보안 경고가 나오는 이유예요([설치](README.md#설치)).

## English

### Supported versions

Only the latest release gets fixes. Peeky checks for a new version once a day, so please keep it up to date.

### Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately with **Security → Report a vulnerability** in this repository. It helps to include:

- Your Peeky and macOS versions
- What the problem is and how to reproduce it
- What an attacker could do

Peeky is a free app made by one person, so replies may take a while. Confirmed problems are fixed in a new release and noted in the changelog.

### What Peeky protects

- Menu bar items and screen contents are never sent anywhere. The network is used only to check GitHub for updates.
- The diagnostic log is written only when you turn it on, and records permission state only.
- Updates come only from https GitHub addresses and are installed only when they match the SHA-256 from GitHub and the developer's Ed25519 signature.
- Peeky isn't notarized by Apple, which is why macOS shows a security warning on first launch ([Install](README.en.md#install)).
