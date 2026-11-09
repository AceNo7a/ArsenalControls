Arsenal Controls 1.0.0-beta.3

A public beta of the SlimeUI interface and Roblox client controls.
The UI no longer requires Arsenal. Core aim, ESP and movement use standard
Humanoid characters; custom character systems may need additional support.
Other games can use standard Tool auto fire and autoplay. Custom weapon
frameworks may need a game-specific adapter; server damage is not guaranteed.
Silent aim, recoil and client ammo options still require Arsenal's adapter.
Tested with Madium on Windows; other executors are unverified. Arsenal client
updates may break compatibility. All active features start disabled, with
team check, wall check and target lock enabled as filters.

GETTING STARTED
1. Join a Roblox game. Arsenal weapon integration connects when available.
2. Run mainloader.lua for the latest release, or run the complete standalone
   dist/ArsenalControls.lua file directly. loader.lua is an equivalent alias.
3. Enable only the features you want. Weapon-dependent controls become
   available after the weapon adapter connects; see Visual for status.
4. Press F8 to stop every feature. Use About > Unload to remove the interface
   and restore owned local changes. Running the file again replaces this build.

CONTROLS
Right Shift: show or hide the window. The floating button also toggles it.
F8: stop aim, firing, autoplay, ESP and all movement/weapon overrides.
Aim activation: Always by default, or Hold right mouse in the Aim tab.
Flight: WASD, Space to ascend, Left Ctrl to descend.
About > Reset settings: stop features and restore every default value.

FEATURE NOTES
Camera aim: FOV radius in pixels; smoothing time in seconds (zero is instant).
Target lock retains a target while it remains eligible under the filters.
Camera aim and silent aim are exclusive; fly and autoplay are exclusive.
Auto fire requires an aim mode. Autoplay navigates and fires independently.
Outside Arsenal, equip a standard Tool for auto fire. Autoplay equips the
first available backpack Tool and pauses movement if none exists. Pulse mode
repeats activation; Hold mode maintains it until stopped or targeting pauses.
The Tool fire interval controls pulses; cooldowns remain under game control.
Autoplay stop distance applies outside Arsenal: use a short distance for melee
and a larger distance for ranged tools. Standard player Humanoids are required.
Weapons that read the cursor rather than camera direction may aim differently.
Custom weapons without Tool.Activated handlers are not supported automatically.
Automation pauses for focus loss, text entry, menus and invalid characters.
Autoplay navigation depends on map geometry and can become stuck.
Silent aim is experimental and limited to supported hitscan firing calls.
Server-accepted damage from this feature has not been validated for release.
Client ammo refill is experimental: changing local ammo state does not prove
unlimited server-accepted shots. No recoil restores the captured local value.
Movement changes may be corrected by the server; flight does not prevent damage.

CONTENTS AND PRIVACY
dist/ArsenalControls.lua: single-file executable release.
src/controller.luau: readable controller source.
src/tool-adapter.luau: standard Tool firing and equipment adapter.
mainloader.lua and loader.lua: equivalent latest-release loaders.
vendor/SlimeUI.lua: bundled interface library, with local modifications.
vendor/UPSTREAM.json: pinned upstream revision and modification notes.
licenses/SlimeUI-MIT.txt: required upstream license.
LICENSE: controller license. CHANGELOG.txt and VALIDATION.txt: scope and checks.
The optional loader resolves main through GitHub's public API and downloads
dist/ArsenalControls.lua from the resulting immutable commit URL. This uses
GitHub's unauthenticated API quota; a rate-limit or network error stops loading
with an error instead of silently falling back to an outdated copy.
The standalone build does not download additional Lua, use key verification
or enable telemetry. The upstream library can request Roblox avatar thumbnails and uses
normal Roblox assets. Its unused key-system/config APIs remain in vendor code.
Private game dumps, account names, test recordings and executor tools are not
included. Do not redistribute modified vendor code without its MIT notice.

BUILDING
Run: python build.py
Python 3.9+ and the included files are sufficient. No package install or
network access is required. The output is deterministic for identical sources.
Optional developer checks: StyLua 2.6.0 --syntax Luau --check src/controller.luau
vendor/SlimeUI.lua; official luau-compile --null dist/ArsenalControls.lua.
SHA256SUMS.txt lists file digests for this archive.

CREDITS
Interface: SlimeUI 1.2.0 by SlimexDev, MIT license.
https://github.com/SlimexDev/SlimeUI
Pinned revision: 80c4cae89d849ce84bb19a450c78989a94af944d
Local modifications reduce decorative animation and namespace the UI lifecycle.
This package is an independent community project, with no Roblox or Arsenal
endorsement. Report issues with the version, executor, reproduction steps and
console error text; omit account details and unrelated private data.
