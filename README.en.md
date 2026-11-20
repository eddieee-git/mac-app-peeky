<p align="center">
  <img src="docs/images/icon.png" width="96" alt="Peeky icon">
</p>

<h1 align="center">Peeky</h1>

<p align="center">A macOS menu bar app that brings back the icons hidden behind the notch<br>Pick the ones you want, see them together, and flip through them with arrows — like the Windows taskbar overflow.</p>

<p align="center">
  <a href="https://github.com/eddieee-git/mac-app-peeky/releases/latest">Download the latest version</a> ·
  <a href="#install">Install</a> ·
  <a href="#shortcuts">Shortcuts</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="CHANGELOG.en.md">Changelog</a> ·
  <a href="README.md">한국어</a>
</p>

## Features

- **Click hidden icons**: a bar drops down below the menu bar, and even icons hidden behind the notch open their real menus.
- **Flip through**: with many icons, use the **‹ ›** arrows, mouse wheel or trackpad, or ← → on the keyboard.
- **One, two or three rows**: spread the bar over several rows to scroll less.
- **Groups**: each group gets its own icon in the menu bar and shows only the items you put in it — e.g. "Work" and "System". Rows and what to show can be set per group.
- **Really hide from the menu bar**: icons moved left of the divider disappear from the menu bar and only show in the Peeky bar.
- **Drag to reorder**: drag icons inside the bar into any order.
- **Hover over the notch**: optionally open the bar just by resting the pointer on the notch.
- **Real icon images**: with Screen Recording permission, items look exactly as they do in the menu bar (otherwise the app icon is shown).
- **Only what the notch hides**: optionally list just the items that are hidden right now.
- **Readable names**: built-in macOS items without a name get one — Battery, Wi-Fi, Sound and so on.
- **In-app updates**: tells you about new versions, checks the signature, and swaps them in.
- **English and Korean**: follows your Mac's language at first; change it in Settings.

## Install

1. Download `Peeky-x.y.z.dmg` from [Releases](https://github.com/eddieee-git/mac-app-peeky/releases/latest) and open it.
2. Drag **Peeky** into **Applications**.
3. Open Peeky. It has no Apple Developer signature, so macOS blocks the first launch. Click **Done**, then:
   - **macOS 15 (Sequoia) or later**: System Settings → Privacy & Security, scroll to the bottom, click **Open Anyway** next to Peeky, then **Open**.
   - **macOS 14 (Sonoma)**: right-click Peeky in Applications → **Open**.

   Or run `xattr -dr com.apple.quarantine /Applications/Peeky.app` in Terminal.
4. The settings window opens on first launch. Click **Allow** next to **Accessibility** and turn Peeky on in the list (required).
5. (Optional) **Screen Recording** → turn Peeky on → **Reopen** to show real icon images.

## Usage

1. Click the Peeky icon (`‹›`) in the menu bar or press **⌃⌥1**. The bar opens right below the menu bar.
2. Click an icon in the bar to open that app's menu. Right-click tries the secondary menu.
3. In settings → **General** → **Icons in the bar**, only icons whose switch is on appear in the Peeky bar. Labels like “Behind notch”, “Hidden” or “No room” tell you why an icon isn't visible in the menu bar right now.
4. To add groups: settings → **Advanced** → **Groups** → **＋ Add group**. With two or more groups, you pick a group per icon instead of a switch. Each group can have its own name and symbol, and **⋯** sets rows and what to show for that group.
5. Drag icons in the bar to reorder them. **Reset order** in settings → Advanced goes back to menu bar order.

### Hiding items from the menu bar

1. Settings → **Advanced** → **Menu bar cleanup** → turn on **Hide items from the menu bar**. A divider (╱) and a **›** button appear in the menu bar. Nothing is hidden yet.
2. Hold ⌘ and drag icons you want to hide to the **left** of the divider. Keep the Peeky icons to its **right**.
3. Items left of the divider disappear from the menu bar and only show in the Peeky bar. Clicking one in the bar briefly unfolds the menu bar to open its menu, then hides it again once the menu closes.
4. When you're done, click **›** to hide them. While hidden it turns into **‹**; click it to show them again. The Peeky icon's right-click menu does the same.
5. If a Peeky icon is left of the divider, Peeky keeps the menu bar unfolded and tells you.

If the Peeky icon itself is hidden by the notch, ⌘-drag it to the right; the position is remembered. Shortcuts always work.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥1 – ⌃⌥9 | Toggle the bar for group 1–9 |
| ⌃⌥B | Toggle the first group's bar |
| ← → | (while the bar is open) scroll left/right |
| esc | Close the bar |

The modifiers (⌃⌥) can be changed to ⌃⌘, ⌥⌘ or ⌃⇧, or turned off, in settings → **Shortcut**.

## Settings

| Setting | Description |
|---|---|
| Only items hidden by the notch | Shows only items currently under the notch or pushed off-screen (per group too) |
| Rows | One / two / three (per group too) |
| Open the bar when hovering over the notch | Notched displays only (off by default) |
| Shortcut | ⌃⌥ / ⌃⌘ / ⌥⌘ / ⌃⇧ / off |
| Hide items from the menu bar | Hides items left of the divider (off by default) |
| Max bar width | Beyond this width, use arrows and scrolling |
| Launch at login | Start automatically |
| Language | Follow system / 한국어 / English. Reopen Peeky to apply |
| Check for new versions automatically | Checks GitHub once a day (on by default) |
| Install new versions automatically | Installs a found update by itself and relaunches while you aren't using Peeky (on by default) |
| Keep a diagnostic log | Writes permission status to `~/Library/Logs/Peeky.log` (off by default; turning it off deletes the file) |

## FAQ

**I can't see the Peeky icon in the menu bar.**
It's behind the notch or there's no room for it. Open Peeky again from Applications: the settings window opens with a notice at the top. **⌃⌥1** opens the bar; hold ⌘ and drag other icons left to make room, then move the Peeky icon to the right end. **Move Peeky icons to the right end** in Settings → Advanced → Menu bar cleanup puts them back in place. On macOS 26, also check that Peeky is allowed in System Settings → Menu Bar.

**I turned the permission on but settings still shows orange.**
The Peeky entry in the list may belong to an older build. Remove it with − and click Allow again (turn on **Keep a diagnostic log** under Advanced → Troubleshooting to see what Peeky detects), or reset with `tccutil reset Accessibility com.eddieee.Peeky` (`ScreenCapture` for Screen Recording). Screen Recording takes effect after **Reopen**.

**What does it send?**
Only one request to GitHub's public API asking for the latest release when checking for updates. Menu bar items and screen contents are never sent anywhere. Turn off automatic checks in Settings and not even that is sent.

**Icons I hid from the menu bar don't come back.**
Click the **‹** button in the menu bar, or right-click a Peeky icon → **Show Hidden Icons**. Turning off **Hide items from the menu bar** removes the divider and brings everything back. Quitting Peeky also unfolds them.

**Does it work on Macs without a notch?**
Yes — it's still useful for grouping menu bar icons. "Only items hidden by the notch" only matters on a notched display.

## Uninstall

1. Right-click the Peeky icon (or the ‹ › button or the divider) → **Quit Peeky**
2. Move Peeky from Applications to the Trash
3. (Optional) `defaults delete com.eddieee.Peeky` for settings, `tccutil reset All com.eddieee.Peeky` for permission records

## Build it yourself

Requires an Apple silicon Mac, macOS 14+, and the Xcode Command Line Tools (Xcode itself is not needed).

```bash
./scripts/make-signing-cert.sh   # (optional, once) local certificate so permissions survive rebuilds
./scripts/test.sh                # self-test
./scripts/build-app.sh           # build/Peeky.app + build/Peeky-<version>.dmg
open build/Peeky.app
```

When signing with that certificate, macOS must trust it for code signing before permissions are recognized:

```bash
security find-certificate -c "Peeky Local Signing" -p > /tmp/peeky.pem && security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/peeky.pem
```

## License

[MIT](LICENSE)

<!-- more-apps:start -->
## More apps

| | App | |
|---|---|---|
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-clocky/main/docs/images/icon.png" width="32" alt=""> | [Clocky](https://github.com/eddieee-git/mac-app-clocky) | Flip-clock timers, alarms and calendar alerts from the menu bar |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-floaty/main/docs/images/icon.png" width="32" alt=""> | [Floaty](https://github.com/eddieee-git/mac-app-floaty) | Floating sticky notes, right from the menu bar |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-gitty/main/docs/images/icon.png" width="32" alt=""> | [Gitty](https://github.com/eddieee-git/mac-app-gitty) | Work with Git repositories like a file manager |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-grabby/main/docs/images/icon.png" width="32" alt=""> | [Grabby](https://github.com/eddieee-git/mac-app-grabby) | Capture, mark it up in place, and paste right away |
<!-- more-apps:end -->
