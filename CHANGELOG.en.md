# Changelog

Details for each version are in [docs/releases](docs/releases) and [GitHub Releases](https://github.com/eddieee-git/mac-app-peeky/releases). 한국어: [CHANGELOG.md](CHANGELOG.md)

## 0.2.0 (2026-11-14)

- Really hide items from the menu bar: items left of a divider are hidden, and clicking them in the Peeky bar briefly unfolds the menu bar to open their menus
- Drag to reorder icons in the bar; Reset order in settings
- Open the bar by hovering over the notch (off by default)
- Per-group rows and what to show
- Choose shortcut modifiers (⌃⌥ / ⌃⌘ / ⌥⌘ / ⌃⇧ / off)
- Names for unnamed built-in macOS items such as Battery, Wi-Fi and Sound
- New group icons are placed near the right so the notch doesn't hide them
- English interface (used when the system language isn't Korean)
- Lighter: opening the bar rescans only apps with menu bar items and captures only changed icons
- Diagnostic log only when turned on in settings; releases refuse to build unless signed with the certificate

## 0.1.0 (2026-11-14)

- First release
- A bar below the menu bar that shows icons hidden by the notch and opens their real menus
- Scroll with arrows, wheel or keyboard; one, two or three rows
- Groups: one menu bar icon per group, per-item group choice, ⌃⌥1–9 shortcuts
- Real icon images with Screen Recording permission
- Automatic in-app updates (Ed25519 `.sig`, SHA-256 and code signature checks)
