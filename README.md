# nanoleaf

Native macOS Swift CLI for Nanoleaf PC Screen Mirror Lightstrip NL82K2 (USB 37FA:8202). No third-party package or Nanoleaf Desktop runtime dependency.

Independent project, not affiliated with or endorsed by Nanoleaf. Licensed under [MIT](LICENSE), with the retained attribution in [third-party notices](THIRD_PARTY_NOTICES.md).

## Development and verification

This project was entirely vibe-coded with OpenAI Codex. The only human
verification was testing the actual CLI during regular, everyday use. The code,
automated tests, and documentation were AI-generated; passing automated checks
does not constitute independent human review. See [verification details](VERIFICATION.md).

## Usage

```sh
nanoleaf day
nanoleaf evening
nanoleaf off
nanoleaf on
nanoleaf toggle
nanoleaf brightness 10
nanoleaf temp 4800
nanoleaf config
nanoleaf status

# One-time overrides
nanoleaf day --temp 5200 --brightness 40

# Apply and change this profile's saved defaults
nanoleaf evening --temp 3300 --brightness 20 --save
```

Initial defaults: **day 4800 K/30%**, **evening 3500 K/30%**. Brightness accepts integers from 0 to 100; temperature accepts integers from 2700 to 6500 K. Kelvin uses a calibration matching the connected model and hardware revision when available; otherwise it uses a generic RGB approximation. Neither mode establishes instrument-measured color temperature.

| Command | Behavior |
| --- | --- |
| `on` | Restore the last CLI temperature and nonzero brightness. |
| `off` | Send black, retaining those settings for the next `on`. |
| `toggle` | Invert the saved CLI on/off state; fail if no state has been saved for this device. |
| `brightness N` | Positive values turn on at the remembered temperature. Zero sends black and retains the previous nonzero brightness. |
| `brightness up` / `down` | Adjust by 5 percentage points. Up from off starts at 5%; down from off does nothing. |
| `temp up` / `down` | Adjust cooler/warmer by 100 K, preserving brightness and on/off state. |
| `temp K` | Set the temperature and turn on at the remembered nonzero brightness. |
| `day` / `evening` / `night` | Apply that profile's saved values, with any supplied overrides. Positive brightness turns on; zero sends black. |
| `config` | Show effective profile defaults and their file path. Does not require the device. |
| `status` | Show connected zone count, calibration, and the last saved CLI setting. |
| `schedule enable` / `disable` / `status` | Manage the local evening transition; requires the service to apply it. |
| `service enable` / `disable` / `status` | Manage optional background control and login startup. |
| `help`, `--help`, `-h`, or no arguments | Show help without accessing the device or configuration. |

Light commands and `status` require a connected device. Help, `config`, and service management work without one. Help flags are top-level commands; `nanoleaf day --help` is not supported.

### Profiles and remembered settings

`night` is an alias for `evening`, including overrides and `--save`. Both use
the same saved evening profile.

`--temp`, `--brightness`, and `--save` are available only for `day` and `evening`. Use separate arguments such as `--temp 5000`, not `--temp=5000`. Missing values, duplicate options, unknown options, and out-of-range values are rejected.

Unspecified profile values come from that profile's saved defaults, not the current light setting. For example, `nanoleaf evening --brightness 20` uses the saved evening temperature. Without `--save`, overrides affect this run and the remembered setting for `on`; the profile defaults stay unchanged. With `--save`, the resulting profile is applied and its defaults are saved. The other profile is preserved. Saving requires a successful frame acknowledgement and a successful restore-state save first.

A zero-brightness profile remembers its requested temperature and retains the previous nonzero brightness for the next `on`. It sends black directly, without a temporary bright frame.

Without saved state for this device, remembered settings start at **4800 K/30%**, independently of any customized day/evening defaults. Thus a first `brightness 10` uses 4800 K, a first `temp 3500` uses 30%, and a first `on` uses 4800 K/30%. `toggle` instead requires an earlier successful light-changing CLI command. Neither `config` nor `status` establishes restore state.

### Files and status

Files are under `~/Library/Application Support/nanoleaf/`:

- `config.json`: saved profile defaults. If absent, built-in defaults apply; the file is written by `--save`.
- `state.json`: last CLI settings, keyed by device serial when available. Written after successful light-changing commands.
- `calibration.json`: optional hardware-profile overrides. The executable includes the NL82K2 hardware 1.1.0 profile; no local file is required. See [calibration](CALIBRATION.md).
- `.lock`: coordinates commands so they cannot interleave device transactions or saved-state updates. A concurrent command fails with a retry message.

JSON files are written atomically, but applying the frame, saving restore state, and saving profile defaults are separate operations. A save failure can leave the LEDs changed; the error message says which save failed. Invalid existing configuration/state is reported instead of silently overwritten.

`status` identifies the active color conversion and reports the **last CLI setting**, not a measurement of the LEDs. With no saved state it reports that the setting is unknown. Buttons, other controllers, unplugging, or power loss can make saved state stale; `toggle` still operates on that saved state. Commands cannot recover the color previously set by another app or a controller button. An acknowledged frame confirms delivery, not its physical appearance.

## Optional background service

Enable physical buttons, keyboard shortcuts, and automatic screensaver/display-sleep blanking:

```sh
nanoleaf service enable
nanoleaf service status
nanoleaf service disable
```

The service runs a copy of the same executable as a per-user macOS LaunchAgent
and starts at login. `service enable` creates a locally signed app wrapper at
`~/Library/Application Support/nanoleaf/Nanoleaf.app`, which gives macOS an app
identity for location permission. Only the CLI binary needs to be copied to
another Mac; enabling the service creates its wrapper there. It needs no administrator access. Normal light commands automatically
route through a private local Unix socket to the service, which owns the USB
connection. There is no network listener.

While connected, a three-second keepalive maintains online mode. Physical power
presses toggle black and the remembered CLI color/brightness, updating saved
state. Mode/scene-button presses alternate between the saved day and evening
profiles, applying both temperature and brightness. The first press selects day
if no profile has been selected; thereafter it selects the opposite of the last
successful day/evening selection, including selections made through the CLI.
That selection survives service restarts and USB reconnection. Power toggles
and individual temperature/brightness adjustments do not reset the cycle.
Mode presses apply the profile even while off (positive brightness turns it on).
One-time CLI overrides do not change the saved defaults used by the button.

Entering online mode stops built-in color cycling; use `service disable` to return to the strip's standalone controls.

After detecting a USB disconnect and reconnect, the service turns the strip on
at the remembered CLI temperature and nonzero brightness, even if it was turned
off using its physical button while the Mac was disconnected. The last selected
day/evening profile is preserved. With no saved state, reconnect uses 4800 K/30%.

Service startup and recovery from a USB error preserve saved on/off state.
Without saved state, service startup leaves the strip off with 4800 K/30% remembered.
It uses a timer and USB callbacks, stops keepalives when disconnected or asleep,
and reconnects after wake. It does not prevent Mac sleep. Physical controls
revert to device behavior when the service cannot keep the strip online.

Quit Nanoleaf Desktop before enabling the service, and disable the service before
using another lighting controller. If another process holds the device, the
service reports the error and retries every 30 seconds while the device is present.
An enabled but unreachable service produces an error instead of silently opening
a competing USB connection.

The login configuration is
`~/Library/LaunchAgents/io.github.sashusha.nanoleaf.plist`.
It records the generated app's executable path. Rerun `service enable` after
replacing the CLI to update the service's copy. Runtime files `service.sock`, `.service-lock`, and
`service.log` are under the configuration directory. The log records errors, not
routine keepalives. Disabling removes the login configuration and preserves settings and the app wrapper.

## Screensaver and display sleep

The service temporarily blanks the strip when the screensaver starts or the
displays sleep. It restores the saved on/off state, temperature, and brightness
once both conditions clear. A strip already off stays off. Temporary blanking
does not overwrite saved state or profile defaults.

Keepalives continue during screensaver/display sleep while the Mac is awake,
so the controller stays in online mode. Before system sleep the service attempts
to blank the strip and releases USB; it reconnects on wake. Once the Mac is asleep
or USB is disconnected, firmware controls the strip and continued darkness cannot
be guaranteed. A USB reconnect while idle stays blank until activity resumes;
the normal reconnect turn-on policy then applies.

While temporarily blanked, physical controller buttons are ignored and light-changing
CLI commands are rejected except `off`, which also cancels the saved on state.
`service status` reports idle blanking; `status` continues to report saved settings.
These event-based rules apply while the service is running. Screensaver detection
uses macOS distributed notifications, verified on the development Mac but not a
publicly documented Apple contract. Restart the service while the Mac is active.

## Automatic evening transition

```sh
nanoleaf schedule enable
nanoleaf schedule status
nanoleaf schedule disable
```

With the service running, the optional schedule blends the saved day temperature
and brightness into the saved evening values between **sunset and the end of
civil twilight at your system-provided location**. There is no automatic morning switch; use `day`
when wanted. `night` and `evening` remain manual profile commands.

The service requests permission from macOS Location Services when the schedule
is enabled. Allow Nanoleaf in System Settings → Privacy & Security → Location
Services. The service app wrapper contains the purpose message macOS uses for
the consent dialog. Each Mac grants its own permission.

An approximate system location is requested hourly. Coordinates stay in memory,
are never written to configuration or logs, and expire after two hours. Disabling
the schedule clears them. Without permission or a usable location, automatic
transitions pause; manual controls continue to work. `service status` reports
location availability. There is no fixed-city fallback. Location Services itself
may need connectivity; Nanoleaf makes no network request for the calculation.

Dates and displayed times follow the Mac's automatically updating time zone.
Sunset and civil dusk are calculated locally using
[NOAA's solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF).
If either event does not occur at the current location that day, such as during
polar day or night, the schedule leaves the light unchanged.

The service checks the transition about every 12 seconds using its existing
keepalive timer and sends only changed settings. After dusk it uses the evening
profile; before sunset it leaves the current setting alone. Manual CLI, keyboard,
and controller-button changes pause automation until the next sunset. Changes
made during twilight cancel the rest of that day's transition. The override is
saved in `state.json` and survives restarts.

The schedule never turns an off strip on and does not override screensaver or
display-sleep blanking. After wake or USB reconnection it catches up to the current
transition point, unless a manual override is active. Normal USB reconnect power
behavior still applies. Profile defaults remain unchanged. Enabling/disabling
is saved as `sunsetAutomation` in `config.json`; it is disabled by default.

## Keyboard brightness and temperature shortcuts

With the service running, **Shift + display Brightness Up/Down** changes the strip
by 5 percentage points, clamped to 0–100. Allow `~/Library/Application Support/nanoleaf/Nanoleaf.app`
in System Settings → Privacy & Security → Accessibility, then run
`nanoleaf service status` to activate the listener and check its status.
Brightness shortcuts need no Keychron remapping.

For display-brightness keys, only the Shift combination is intercepted; plain
presses and combinations with Control, Option, Command, or Fn pass through.
Captured presses are consumed so they do not also adjust the display.
On macOS 26 and later, the indicator uses Apple’s clear Liquid Glass material;
older versions use a rounded translucent HUD material.

After a successful keyboard adjustment, a translucent Nanoleaf indicator shows
the adjusted brightness percentage or Kelvin value at the center of the display containing
the pointer. It fades after 2.2 seconds without another adjustment and does not
take focus or capture clicks. A disconnected strip shows “Disconnected”; other
failed adjustments show an error instead of a success percentage. Ordinary CLI
commands do not show this indicator.

Holding a key repeats the adjustment. The function row must emit brightness
keys rather than F1/F2. The shortcuts apply across keyboards.

`nanoleaf brightness up` and `nanoleaf brightness down` perform the same steps
without needing keyboard permission. Up from off turns on at 5%; down from off
has no effect. Temperature and saved profile defaults are preserved.
Without Accessibility permission, USB service and CLI commands still work.
After updating the service, macOS may require you to remove and re-add
`Nanoleaf.app` in Accessibility, even if its existing switch is enabled. Then run
`nanoleaf service status` to activate shortcuts.

F18/F19 (without Shift, Control, Option, or Command) adjust
temperature warmer/cooler in 100 K steps, bounded to 2700–6500 K. They preserve
brightness and on/off state and show Kelvin with a warm-to-cool indicator.
These bindings consume F18/F19 across keyboards. On the tested Keychron V10 Ultra,
use Launcher → Custom → Any to assign `KC_F18` and `KC_F19` to the desired keys.
`nanoleaf temp down|up` provides the same relative adjustment from the CLI.

## USB operation

The CLI sends solid-color frames using command `0x02` and queries the zone count
with `0x03`. Frames use GRB channel order, a channel range of 15–255, and
brightness scaled into each frame. `[15,15,15]` per zone produces black.
See [calibration](CALIBRATION.md) for color conversion and rounding.

Messages use TLV framing and 64-byte HID reports. Protocol reference:
[Nanoleaf USB Lightstrip Communication Protocol](https://nanoleaf.atlassian.net/wiki/spaces/nlapid/pages/2615574530/Nanoleaf+USB+Lightstrip+Communication+Protocol).
Streaming conventions are based on the vendor implementation and device testing.

In standalone mode the CLI opens the USB device directly and exits after its
frame is acknowledged. The optional service keeps the connection open. Both refuse
multiple matching devices rather than choosing one arbitrarily.

## Download

Download `nanoleaf-macos-arm64.zip` from [GitHub Releases](https://github.com/sashusha/nanoleaf/releases/latest).
It includes the executable and license notices. The build targets Apple silicon
(M1 or later) and macOS 12 or later; older macOS versions have not been physically
tested. Intel Macs must build from source. A SHA-256 checksum is included with
the release.

Extract the archive, then install from its directory:

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 nanoleaf "$HOME/.local/bin/nanoleaf"
nanoleaf service enable
```

Ensure `~/.local/bin` is on your PATH. The executable is not Apple-notarized.
If macOS blocks it, attempt to run it, then approve Nanoleaf under System Settings
→ Privacy & Security → Open Anyway. A managed Mac may require IT approval.
Enable the service while the Mac is active; grant the generated `Nanoleaf.app`
Accessibility permission for shortcuts and Location Services permission for
`nanoleaf schedule enable`.

## Build and checks

Requires macOS 12 or later and Apple's Swift toolchain (Xcode or Command Line Tools). Run these commands from the project directory:

```sh
swift run --build-system native NanoleafChecks
swift build --build-system native -c release --product nanoleaf
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/nanoleaf "$HOME/.local/bin/nanoleaf"
```

For background control, run `nanoleaf service enable` after installation or
replacement, while the Mac is active. This updates the local app wrapper and
restarts the service. Keyboard shortcuts also require Accessibility permission.

To use another Mac, build there or copy an executable compatible with its macOS
version and processor architecture, then follow the same installation steps.
Calibration is embedded; profile defaults and remembered settings are local to
each Mac.

`~/.local/bin` must be on your PATH. The native build-system flag matches the locally verified build; this Swift toolchain emits a deprecation warning for it.

The dependency-free checks work with Apple's Command Line Tools without XCTest. They cover argument ranges, configuration preservation, reference frame fixtures, zero/low brightness, off/on restoration across invocations, malformed replies, packet boundaries, and failed-write state preservation.

See [VERIFICATION.md](VERIFICATION.md) for the current verification evidence and limitations.

## License and attribution

Copyright (c) 2026 Alexander Vladimirov.

Project code is available under the [MIT License](LICENSE). The Kelvin-to-RGB
adaptation retains Tanner Helland's BSD 2-Clause notice; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Retain the applicable license
and attribution notices when redistributing source or binaries.

## Matching Desktop white temperature

The CLI includes a profile for **NL82K2 hardware 1.1.0**, tested on firmware
**1.5.0**. It reads the connected device's revision and applies only an exact
hardware match. Every light-changing command and `status` identify the selected
profile and whether the connected firmware is listed as tested. Other revisions
fall back to the generic approximation with an explicit message.

Profiles are shared by hardware revision. See [CALIBRATION.md](CALIBRATION.md)
for the schema, optional local overrides, rebuilding embedded profiles, provenance,
and limitations. Matching profiles are embedded in the executable; installing
Nanoleaf Desktop or a separate calibration file is not required.
