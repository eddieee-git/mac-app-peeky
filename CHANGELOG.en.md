# Changelog

Details for each version are in [docs/releases](docs/releases) and [GitHub Releases](https://github.com/eddieee-git/mac-app-peeky/releases). 한국어: [CHANGELOG.md](CHANGELOG.md)

## 0.3.0 (2026-11-20)

- Choose “Show / Hide (· group)” per icon and Peeky moves menu bar icons into place like a ⌘-drag
- Only a ‹ › button in the menu bar: icons to its right always show, icons to its left are hidden
- Labels for why an icon isn't visible (behind notch / hidden / no room / always shown)
- Settings split into General and Advanced tabs; a shorter right-click menu
- Removed “Only items hidden by the notch” and notch hover; “Bar” renamed “Peeky bar”
- Apps that append a status to their name (such as Cloudflare One) and the input source icon are recognized consistently

## 0.2.6 (2026-11-20)

- Right-clicking the ‹ › button or the divider opens the menu (open groups, show/hide, settings, quit)

## 0.2.5 (2026-11-20)

- “Move Peeky icons to the right end” in Settings → Menu bar cleanup: puts the group icons, divider and ‹ › button back in place
- The same fix from the hidden-icon notice and the blocked-hiding alert, plus a `--reset-icons` launch option

## 0.2.4 (2026-11-20)

- The settings window warns at the top when the Peeky icon is behind the notch or has no room in the menu bar

## 0.2.3 (2026-11-19)

- The settings (⚙) button in the bar sits in the last slot after the icons
- Automatic installs are on by default; checking manually installs right away

## 0.2.2 (2026-11-16)

- Menu bar hiding: a ‹ / › button that stays visible while hidden, a guide when first turned on, and no hiding while a Peeky icon is left of the divider
- Icons are captured just before hiding, so hidden items keep their real look

## 0.2.1 (2026-11-15)

- Choose the language in Settings: System / 한국어 / English
- The option for items outside groups is now called “Menu bar only” to make its meaning clear
- Empty placeholder items from Control Center on macOS 26 are left out of the list
- Updates use the updater shared by all five apps: separate switches for automatic checks (on by default) and automatic installs (off by default), plus an update item in the menu bar menu
- Stronger update checks: installs only after the signature, SHA-256, bundle ID, version, and code signature are verified
- About section in Settings: version, GitHub, changelog, problem reports, and other apps

## 0.2.0 (2026-11-14, not released separately; included in 0.2.1)

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
