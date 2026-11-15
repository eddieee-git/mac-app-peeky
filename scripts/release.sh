#!/bin/zsh
# GitHub 릴리스를 만든다: 점검 → 빌드(dmg) → 태그 → 릴리스에 dmg 첨부.
# 버전은 Resources/Info.plist의 CFBundleShortVersionString을 쓴다. 릴리스 노트는 docs/releases/v<버전>.md.
# 사용: ./scripts/release.sh
set -e
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
notes="docs/releases/$tag.md"

if [[ ! -f "$notes" ]]; then
    echo "릴리스 노트가 없어요: $notes"
    exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "이미 있는 태그예요: $tag (Info.plist의 버전을 올려 주세요)"
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "커밋하지 않은 변경이 있어요. 먼저 커밋해 주세요."
    exit 1
fi

./scripts/test.sh
./scripts/build-app.sh
# 배포본은 늘 인증서로 서명한다. 임시 서명은 번들 ID만 확인하므로 같은 ID를 흉내 낸 앱이 권한을 이어받을 수 있다.
if ! codesign -dv build/Peeky.app 2>&1 | grep -q "Authority=Peeky Local Signing"; then
    echo "Peeky Local Signing 인증서로 서명되지 않았어요. ./scripts/make-signing-cert.sh를 먼저 실행해 주세요."
    exit 1
fi
if [[ ! -f "build/Peeky-$version.dmg.sig" ]]; then
    echo "업데이트 서명(.sig)이 없어요. ~/.config/peeky/update-signing.key를 확인해 주세요."
    exit 1
fi

git tag -a "$tag" -m "Peeky $version"
git push origin "$tag"
# 릴리스 노트 끝에 dmg의 SHA-256을 붙여 올린다(저장소의 노트 파일은 그대로 둔다).
body=$(mktemp)
cat "$notes" > "$body"
printf '\n## SHA-256\n\n```\n%s  Peeky-%s.dmg\n```\n' "$(shasum -a 256 "build/Peeky-$version.dmg" | cut -d' ' -f1)" "$version" >> "$body"
gh release create "$tag" "build/Peeky-$version.dmg" "build/Peeky-$version.dmg.sig" --title "Peeky $version" --notes-file "$body"
rm -f "$body"
echo "릴리스를 만들었어요: $tag"
