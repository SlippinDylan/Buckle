<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>Everyday Mac tools, a click away.</p>
  <p><strong>English</strong> · <a href="docs/README.zh-CN.md">简体中文</a> · <a href="docs/README.zh-TW.md">繁體中文</a> · <a href="docs/README.ja.md">日本語</a> · <a href="docs/README.ko.md">한국어</a> · <a href="docs/README.de.md">Deutsch</a> · <a href="docs/README.fr.md">Français</a> · <a href="docs/README.es.md">Español</a></p>
</div>

Buckle is a native macOS menu-bar app for system tools, launching browsers in another language, and everyday Finder actions. It runs in the background without a Dock icon.

**[Download for macOS](https://github.com/SlippinDylan/Buckle/releases/latest)** · [Development guide](docs/development.md)

> [!NOTE]
> This README describes the current source code. Downloadable builds follow the features and limitations listed in their release notes.

## Install and first use

Requires **macOS 15 or later**, on Apple Silicon or Intel. CI builds target Universal 2.

1. Download `Buckle-<version>.dmg` from the [latest GitHub Release](https://github.com/SlippinDylan/Buckle/releases/latest). Choose the installer under **Assets**; the source-code archives are for development.
2. If upgrading, choose **Quit** from the running Buckle menu and wait for it to exit. Open the DMG and drag `Buckle.app` into **Applications**, replacing the previous copy if needed.
3. Open `/Applications/Buckle.app`. Buckle appears in the menu bar, without a Dock icon. Keep one installed copy.
4. Use the menu-bar menu to run tools or enable Finder actions. All five Finder actions are off on first use; your selections are saved.
5. Open **Settings → Permissions** to enable the Finder extension or grant requested access. Status refreshes automatically; green text and a checkmark indicate granted access or an enabled extension.

The setup guide appears once on a normal launch if you have not dismissed it before, including for existing users; it preserves your current settings. It introduces the menu-bar app, lets you choose Finder actions, and offers the permissions those actions need, launch at login, and automatic update checks. Changes are saved immediately. All five Finder actions remain off until you choose them. You can continue without granting access, or close the window; the guide will not reopen automatically after restarting or upgrading. For new users, skipping the update choice leaves automatic checks off; existing update preferences are preserved and manual checks remain available in builds that support updates. The final page celebrates completion; choose **Start Using Buckle** to open its menu. Permissions appear on a separate page before the feature switches.

> [!IMPORTANT]
> Builds use ad-hoc signing and are not notarized. A downloaded build may need approval in System Settings; system permissions may need to be granted again after an update.

Homebrew installation is not available yet. Use the DMG until the Buckle Cask is published in the [shared Tap](https://github.com/SlippinDylan/homebrew-tap).

## Uninstall and reinstall

Quit Buckle from its menu and wait for it to exit, then move `Buckle.app` to the Trash. Removing only the app preserves its settings and setup record, so replacing or reinstalling it does not show setup again.

To show setup after reinstalling, also run this command in Terminal after quitting Buckle:

```bash
defaults delete studio.slippindylan.Buckle onboarding.dismissed
```

This removes only the setup dismissal record, leaving other settings, Finder data, and system permissions unchanged. If the record does not exist, there is nothing to remove. After reinstalling, launch Buckle manually to see setup once; do not run this command for a normal upgrade.

## What you can do

<table>
  <tr>
    <td width="36%"><strong>System tools in the menu bar</strong><br><br>Open the system memory window, reset mouse utilities with progress and results, or restart the system menu bar. Finder actions can be toggled individually; a checkmark means enabled.</td>
    <td width="64%" align="center"><img src="docs/images/readme/menu-bar.png" width="310" alt="System tools in the menu bar"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Finder actions, where you need them</strong><br><br>Add AirDrop, Open in Terminal, Copy Path, Move Items Here, and New Text File directly to Finder’s context menu. Open Terminal in the selected folder or current folder; copy multiple paths as separate lines.</td>
    <td width="64%" align="center"><img src="docs/images/readme/finder-context-menu.png" width="285" alt="Finder actions, where you need them"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Launch browsers in eight languages</strong><br><br>Choose an installed browser, then a language. Buckle detects supported browsers whenever you open the menu. Launching uses app code, with no personal scripts required.</td>
    <td width="64%" align="center"><img src="docs/images/readme/browser-language.png" width="580" alt="Launch browsers in eight languages"></td>
  </tr>
</table>

The four custom Finder actions use matching color icons in Finder and Buckle’s menu-bar menu; AirDrop keeps its system icon.

**New Text File:** enable it in the menu-bar menu or setup, then right-click a single ordinary folder or its background. Buckle creates an empty `.txt` file with a localized name, adds a number if the name is taken without overwriting files, and selects it in Finder. This needs the Finder extension, without extra Accessibility or automation access. Automatic rename and native Finder Undo are not provided.

## Settings

Manage launch at login and app language under **Settings → General**. The interface follows macOS by default, or you can choose English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, or Spanish. Restart Buckle to apply a language change.

Under **Settings → General → Dock**, enable **Middle-click to quit apps** (off by default), then middle-click a running app icon in the Dock. The same enable switch is available in the menu bar. Its **Middle-click Action** submenu remembers either **Quit Normally** (default) or **Force Quit…**; clicks use this choice without opening an action menu. Normal quit allows save prompts or cancellation. Force Quit asks for confirmation each time and warns that unsaved changes may be lost; Cancel does nothing. After confirmation, Buckle revalidates the same app instance and force-quits only that app, without terminating helpers, automatic escalation, retries, or extra permissions. Finder, Dock, WindowManager, and Buckle are excluded. Accessibility access is required; if the mouse filter cannot start, the setting offers an explicit Input Monitoring request. Dragging does not quit; a fast first click may pass through while the icon is identified. These two new features still need testing in an installed build on supported macOS versions; macOS 15 is the minimum target, not a compatibility test result.

Under **Settings → Mouse Reset**, you can add or remove applications and set the delay before reopening them: 0–60 seconds, with a default of 3 seconds. Changes are saved automatically; editing is disabled during a reset.

<p align="center">
  <img src="docs/images/readme/general-settings.png" width="340" alt="General settings">
  <img src="docs/images/readme/permissions-settings.png" width="340" alt="Permission status">
</p>

Screenshots show the English interface and may differ from your installed version. Menus vary with installed browsers, enabled actions, and copied files.

## Before you use the tools

- **Memory window:** opens macOS LowMemoryPanel manually, including at normal memory usage. Its built-in “out of application memory” message is not a diagnosis. This uses a private system debug path. Buckle checks for the specific memory warning window, restores its temporary setting, and reports failure if it cannot confirm the window. Compatibility still requires testing on each macOS version. Accessibility and System Events automation access are required; there is no background memory monitoring.
- **Reset Mouse:** manage the application list under **Settings → Mouse Reset**; defaults are Moom, MonitorControl, BetterMouse, and iShot Pro. Each reset quits the running apps in your list, refreshes shared macOS preference and permission services, then reopens those apps. Only apps that were already running are reopened. Service refresh can briefly affect other apps and requires administrator authorization. Uninstalled apps are skipped; service refresh still runs when the list is empty. Pending recovery is saved: after an interruption, the next launch offers to reopen the apps; choosing Later keeps the record.
- **Restart System Menu Bar:** restarts your SystemUIServer without sudo. It may not fix icons owned by other apps.
- **Browser profiles:** uses the browser’s existing data and saved sign-ins, without creating a separate profile. Profile selection follows the browser’s own behavior. Quit the browser before changing its launch language; Buckle only shows a notice if it is already running. Japanese launches request the Tokyo time zone for the browser process, matching the original script; other languages keep the system time zone. This does not change macOS settings or your IP address, or guarantee a website’s language or regional formatting. Time-zone behavior has been verified only with Chrome Beta.
- **Finder:** Copy Path works in the extension and writes plain text, with multiple paths on separate lines; other actions launch Buckle when needed. For Move Items Here, first copy files in Finder, then right-click the destination folder or its background. Buckle opens that folder in Finder and triggers its native move command. Accessibility and automation access to Finder and System Events are required. Finder handles progress, name conflicts, and Undo; follow its dialogs for the result. Buckle does not wait for the transfer to finish. Finder controls menu placement. Custom Finder menu labels follow Buckle’s language after restarting Buckle; the native AirDrop label follows the system. The Permissions page reports Finder and System Events automation access separately. To avoid executing a remapped command, automatic moving is unavailable when Finder or global menu shortcuts are customized.
- **AirDrop:** opens the system sharing interface without waiting for the transfer to finish. One AirDrop session can be open at a time; other Finder actions remain available. Buckle does not delay quitting for AirDrop; keep it running while using the sharing window.
- **Updates:** Sparkle is integrated. Manual checks are under **Settings → About**, automatic checks under **General**. Development, CI validation, and test packages disable updates; official Release builds enable them. With packaging enabled, a successful full CI build on main automatically packages and publishes an unpublished version, then synchronizes the signed update feed and Homebrew Cask. Documentation and helper-only changes do not publish. Online updates require a published installer and signed feed.

## Build from source

<details>
<summary>Show source-build and development steps</summary>

Requires Xcode 26 or later, Node.js, and Python 3. Debug builds need no Apple developer account.

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

After building, choose one of the following workflows.

### Install for everyday use

Quit any running Buckle using **Quit** in its menu-bar menu and wait for it to exit. In Finder, move the entire `Buckle.app` from `build/DerivedData/Build/Products/Debug/` to `/Applications`; if replacing an installed copy, do so only after it has quit. Open `/Applications/Buckle.app` and keep one installed copy.

### Run for development

Quit any running Buckle using **Quit** and wait for it to exit before opening the build below. Alternatively, open `Buckle.xcodeproj` and run the `Buckle` scheme in Debug after quitting the existing app. Buckle allows only one running instance: a newly launched process exits if another copy is still running. During development, use the build you are testing rather than also opening the installed copy.

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

</details>

## Developer documentation

See the [development guide](docs/development.md) (Chinese) for architecture, checks, CI packaging, update publishing, signing, and on-device acceptance. [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases) contains published installers; [release notes](CHANGELOG.md) are maintained in English.
