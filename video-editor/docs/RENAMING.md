# Renaming ClipForge: what changes, and what must not

"ClipForge" is a working name (the owner: "too many ClipForge out there,
something to think about later"). Nothing is renamed yet. This page is the
plan for the day it is: which places a new name touches, in which order,
and above all **which names must stay exactly as they are**, because
changing them would turn the next version into a *different* app on
people's devices, or cut installed copies off from their updates.

Two different things are called "the name":

- **The display name**: what people read ("ClipForge" in the window title,
  the menus, the help, the website). This is what a rename changes.
- **The identifiers**: package id, signing key, installer id, file and
  folder names, the Claude server name. People never read most of them.
  **They stay**, unless this page says how to move them safely.

## 1. Must NOT change

| What | Where | Why it must stay |
|---|---|---|
| Android package id `com.ekcut.clipforge` | `android/app/build.gradle.kts` (`applicationId`, `namespace`), `MainActivity`'s package, `linux/CMakeLists.txt` (`APPLICATION_ID`), `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`) | Android (and macOS) know an app by this id. With another id the new version installs **next to** the old one as a second app, with none of the old projects, and the old one never updates again. |
| The Android signing key | repository secret used by the build workflow (see HANDOVER, "Missing files, signing, phone speed, music (1.8.0)") | An APK signed with another key is refused as an update ("App not installed"); people would have to uninstall, which deletes the app's own copies of their media. |
| Windows installer `AppId` `{7C1F4E0B-5B7A-4E63-9C5D-2F6A8D3B41C7}` | `windows/installer/clipforge.iss` | Inno Setup recognises an existing install by it. Kept, the renamed installer **updates** the old install; changed, it installs a second program and leaves the old one in the Start menu. |
| The program's file name `clipforge.exe` (and `clipforge` on Linux, the `.app`'s inner binary) | `windows/CMakeLists.txt`, `linux/CMakeLists.txt` (`BINARY_NAME`), `windows/runner/Runner.rc` (`OriginalFilename`, `InternalName`), the update scripts in `assets/update/` (`exeName`, default `clipforge.exe`), the installer script | The updater of an installed 1.12 - 1.16 app copies the new folder over the old one and then starts **`clipforge.exe`**. A new version whose program is called something else would be installed and never started; the old exe would stay behind. |
| The release file names `ClipForge-windows.zip`, `ClipForge-macos.zip`, `ClipForge-android.apk`, `ClipForge-Setup.exe`, `latest.json` | `tool/ci/release_assets.py` (THE list), `tool/ci/make_latest_json.py`, the workflow | Installed apps read `releases/latest/download/latest.json` and old download pages link to the fixed names. `latest.json` names its files itself, so the three updater files *could* be renamed later, but only after every link to the old names is gone; there is nothing to gain. |
| `ClipForge.app` at the top of the Mac zip | workflow (macOS job), `lib/core/update/update_install.dart` (`unpackMacUpdate`) | The Mac updater of installed versions looks for the `.app` at the top of the unpacked zip and swaps it for the one that is running. A differently named `.app` is handled (it takes the first `.app`), but the swapped-in app would keep the **old** name in Applications; see section 3 for the clean way. |
| The Claude helper's file name `clipforge-mcp` (`.exe`) | `bin/build_mcp.dart`, `lib/core/claude/helper_install.dart`, `lib/core/claude/connect.dart` (`looksLikeClipForgeHelper`) | People's Claude configuration starts this file by its full path. |
| The MCP server name `clipforge` | `lib/mcp/tools.dart` (`kServerName`), the key `"clipforge"` under `mcpServers` in people's `claude_desktop_config.json` / `.claude.json`, the `.mcpb` manifest (`docs/tools/build_claude_bundles.py`) | It is written into each person's Claude configuration by "Connect to Claude" and, for older setups, by hand. Under another name Claude would list a second server next to a dead one, and saved permissions ("always allow") are per server name. Tool names (`get_status`, ...) carry no product name and stay too. |
| The helper folder `<app data>/ClipForge/claude` | `lib/core/claude/helper_install.dart` | Same reason: the path is in people's Claude configuration. |
| The project file ending `.clipforge.zip` and the project format | `lib/ui/file_drop.dart` (`kProjectFileSuffix`), `lib/core/storage/project_bundle.dart` | Files people already saved or sent must keep opening. A new ending may be **added** (accept both, write the new one), never swapped. |
| Method channel names `clipforge/update`, `clipforge/device`, `clipforge/gallery`, `clipforge/long_jobs` | Dart and `MainActivity.kt` | Internal; changing them gains nothing and breaks silently if one side is missed. |
| The Dart package name `clipforge` | `pubspec.yaml` (`name:`), every `package:clipforge/...` import | Internal; never shown. |
| Settings keys in `settings.json` | `lib/ui/app_prefs.dart`, `lib/ui/app_settings.dart` | Renaming a key resets that setting for everyone. |

## 2. Keep, or migrate with care: where people's things are

| What | Today | On a rename |
|---|---|---|
| Projects | `<Documents>/ClipForge/projects/<id>/project.json` (`lib/core/storage/project_store.dart`; the MCP helper looks in the same place, `lib/mcp/environment.dart`) | **Simplest and recommended: keep the folder name.** It is a folder in Documents that works; the help says "in your Documents folder, in ClipForge". If it must follow the new name: at start, when `<Documents>/<New>/projects` does not exist and `<Documents>/ClipForge/projects` does, **rename the `ClipForge` folder** to the new name (one rename on the same disk, nothing is copied), and fall back to the old folder when the rename fails (open in another program, OneDrive busy). Do it only while no project is open, write the result into settings.json, and teach the MCP helper (`environment.dart`, "projectsDirAlsoChecked") to look in both. Never copy-then-delete: a full disk in the middle loses work. Project files hold absolute paths only to media, not to the project folder, so the move itself breaks nothing; media copied into the app's own media folder on Android is found through the app-support folder (next row). |
| App-support folder (settings.json, the app's own media copies, the update state and `update-log.txt`, speech packs) | What the system gives for the package id / executable: Android `/data/data/com.ekcut.clipforge/...`; Windows `%APPDATA%\com.ekcut\ClipForge`; macOS `~/Library/Application Support/com.ekcut.clipforge`; Linux `~/.local/share/com.ekcut.clipforge` | **Keep, by not touching the identifiers of section 1.** On Windows the folder comes from `CompanyName` and `ProductName` in `windows/runner/Runner.rc`: **`ProductName` therefore is an identifier here, not a display name. Leave `ProductName` "ClipForge" and `CompanyName` "com.ekcut"**, or settings, the update state and downloaded speech packs are "gone" after the update (they would have to be moved from the old folder at first start). Change `FileDescription` instead: that is the name Windows shows in Task Manager. |
| The install folder on Windows | Installer: `%LOCALAPPDATA%\Programs\ClipForge` (`DefaultDirName`); zip users: a folder they named themselves, "ClipForge" by default (`kTidyDefaultName` in `lib/core/update/tidy_up.dart`) | Keep both. With the same `AppId` the installer reuses the folder the old version is in whatever `DefaultDirName` says, so changing `DefaultDirName` only affects first installs; leaving it avoids two conventions. |
| Start-menu entries "ClipForge", "ClipForge read me" | `windows/installer/clipforge.iss` (`[Icons]`) | May change to the new name. Inno Setup removes the old entries only if the script says so: add the old names under `[InstallDelete]` (`{autoprograms}\ClipForge.lnk`, `{autoprograms}\ClipForge read me.lnk`, `{autodesktop}\ClipForge.lnk`) in the same change, and extend the installer test in the workflow, which checks these entries by name. |

## 3. What a rename does change (the display name)

Do these in one release. Section 4 gives the order.

**The app (code)**

- `kAppName` in `lib/core/links.dart`: the constant for the display name.
  New code uses it; today it feeds the window title (`MaterialApp.title`),
  the About box's title and the licence page.
- The literal "ClipForge" is still written out in about 390 places in
  `lib/` (it was not replaced by the constant in 1.16: it sits inside
  sentences, many of them `const`, and the tests compare the full
  sentences, so this is not a mechanical change). Counts by folder, from
  `grep -rho ClipForge <folder> | wc -l`: `lib/ui` 130, `lib/mcp` 144
  (answers Claude reads; also in `claude/guide/*.md`, regenerate with
  `dart run tool/gen_guide.dart`), `lib/core` 95, `lib/media` 23, `bin` 4.
  The steps: replace the display uses with `$kAppName` folder by folder,
  leaving every identifier of sections 1 and 2 alone (`ClipForge-…` file
  names, `ClipForge.app`, the `ClipForge` folder names, `kTidyDefaultName`,
  the User-Agent strings may change freely), then run the tests: the
  words test, the help-content test (bold labels must exist in `lib/ui`),
  the menu snapshot (`UPDATE_MENU_SNAPSHOT=1`), `about_test`.
- `BuildInfo.describe(name: 'ClipForge')` in `lib/core/build_info.dart`:
  the version line; CI compares `clipforge-mcp --version` with the line it
  computed (`.github/workflows/video-editor-build.yml`, job `check`).
- Help: `assets/help/help_en.md` (123), the tour texts
  (`lib/ui/help/tour.dart`), What moved, `CHANGELOG.md` (history: leave old
  entries, write the rename as an entry), `docs/FEATURES.md`.
- The update scripts' messages: `assets/update/clipforge-update.ps1`,
  `.cmd`, `.sh` (46; their **file names** stay).
- Claude: `claude/CLAUDE.md`, `claude/guide/`, the skill
  `claude/skill/clipforge-editing` (the skill's folder and `name:` are an
  identifier for people who installed it: keep), `docs/claude-setup.html`
  and its twin `site/claude-setup.html`.

**Every platform's manifest (display name only)**

| Platform | File | Field |
|---|---|---|
| Android | `android/app/src/main/AndroidManifest.xml` | `android:label="ClipForge"` |
| Windows | `windows/runner/main.cpp` | `window.Create(L"ClipForge", ...)` (the title bar) |
| Windows | `windows/runner/Runner.rc` | `FileDescription` only (see section 2 for `ProductName`) |
| Windows installer | `windows/installer/clipforge.iss` | `AppName`, the `[Icons]` names, messages. **Not** `AppId`. `OutputBaseFilename` stays `ClipForge-Setup` (a release file name). |
| macOS | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME` names the `.app` **and** its inner program. To show a new name without renaming the bundle, set `CFBundleDisplayName` in `macos/Runner/Info.plist` instead and leave `PRODUCT_NAME`; the menu bar and the Dock should then show the new name while the updater still finds `ClipForge.app` (not tried: check on a real Mac). Renaming the bundle itself needs an updater that renames the installed `.app` (not built). |
| Linux | `linux/runner/my_application.cc` | `gtk_window_set_title` |

**Addresses: one file**

- `tool/ci/links.json` is THE place for the site's address, its pages, the
  repository and the old Pages address. Edit it, copy the values into
  `lib/core/links.dart` (`test/core/links_test.dart` fails until they are
  equal, and fails if the address is written anywhere else in `lib/`,
  `tool/` or `web/`). The website, the read-me generator and
  `latest.json` read the file themselves.
- **Installed apps follow by themselves**: the next release's
  `latest.json` carries the new `links`, the app remembers them at its
  next update check and uses them for the download page, the website link
  and feedback. So publish the release that carries the new addresses
  **while the old site still answers**, and keep the old site (or a
  redirect from it) for as long as versions before that release are in
  use.
- The feedback address may only move to the new site's own host (or to a
  host listed in `feedback_api_hosts` in `links.json` **and** in
  `kFeedbackApiHosts` of an app version people already have); anything
  else is ignored by the app on purpose.

**GitHub**

- The repository may be renamed (or moved to another owner): GitHub
  redirects the old address, and
  `https://github.com/<old>/releases/latest/download/latest.json` keeps
  answering through that redirect, so installed apps keep finding updates.
  The redirect ends if someone creates a new repository under the old
  name: **never reuse the old name.** After the rename update
  `repository` in `links.json` and `kRepositoryUrl` / `kLatestJsonUrl` in
  `lib/core/links.dart`, so new versions ask the new address directly.
- GitHub Pages does **not** redirect after a repository rename: the old
  `…github.io/<old-name>/` address stops answering, and with it "Open the
  download page" of every app before 1.16 and the link in their read-me.
  If that matters at the time, keep a small repository under the old name
  whose only content is the Pages signpost (this conflicts with "never
  reuse the old name": then decide which of the two matters more; apps
  from 1.12 on update themselves and rarely need the page).
- `old_pages` in `links.json` names that address; `site/index.html` is the
  signpost it serves.

**Vercel (the website)**

- The project's name and its `…vercel.app` address, or a custom domain:
  Vercel settings, then `site` in `links.json` (and `NEXT_PUBLIC_SITE_URL`
  only if it was set by hand). Add the new domain **before** removing the
  old one and let Vercel redirect the old one, for the reason given under
  "Addresses".
- The site's words: `web/app/**` (79), `web/components` (9), `web/lib`
  (`TAGLINE`, mail subject `[ClipForge]` in `lib/feedback.ts`),
  `web/content/*.json`, the picture `app/opengraph-image.jpg` and its alt
  text. The help, What's new and feature pages follow the app's files at
  the next build.
- Resend: the sender name in `FEEDBACK_FROM` (a Vercel variable).

**Docs and tools**

`README.md` (root and `video-editor/`), `docs/HANDOVER.md`, this file,
`docs/testing/` (generated checklists: regenerate, do not edit),
`tool/ci/make_readme_html.py` (the read-me's sentences), the workflow's
artifact names (`CF_NAME`; internal, may stay).

## 4. Order of work for a rename

1. Decide the name; check it is free as a domain and on GitHub.
2. Website first: new Vercel domain next to the old one; `links.json`
   (+ `lib/core/links.dart`); deploy. Both addresses answer.
3. App: display name (section 3), manifests, installer `[InstallDelete]`,
   help, CHANGELOG entry "ClipForge is now called …". **Nothing from
   section 1.** `flutter test` (the tests named above), the Windows job's
   installer test (install the old release, then the new installer over
   it: one Start-menu entry, same folder, settings kept), a real Android
   phone (the update installs over the old app and the projects are
   there), a Mac (the update swaps the app; Claude still connects).
4. Release. Installed apps update themselves under the old identifiers and
   show the new name; their `latest.json` now carries the new addresses.
5. Only then, and optionally: rename the GitHub repository (then update
   `links.json` again), and retire the old site address once the versions
   that only know it are no longer in use.

## 5. What was prepared in 1.16

- `tool/ci/links.json` + `lib/core/links.dart`: one source for the outside
  addresses; `latest.json` carries them; the app remembers and checks them.
- `kAppName`: the constant exists and is used by the window title, About
  and the licence page; the rest of the literals are listed above.
- Tests that hold this together: `test/core/links_test.dart`,
  `tool/ci/links_test.py`, `web/tests/links.test.ts`.
