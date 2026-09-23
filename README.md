# nanoleaf

Native macOS CLI for the Nanoleaf PC Screen Mirror Lightstrip NL82K2
(USB 37FA:8202). No third-party packages or Nanoleaf Desktop runtime dependency.
Independent project; not affiliated with Nanoleaf. [MIT license](LICENSE) and
[third-party notices](THIRD_PARTY_NOTICES.md).

Entirely vibe-coded with OpenAI Codex. The only human verification was testing
the CLI during everyday use; the code, tests, and docs were AI-generated.
See [tested behavior and limits](VERIFICATION.md).

## Install or update

Download `nanoleaf-macos-arm64.zip` from [Releases](https://github.com/sashusha/nanoleaf/releases/latest),
extract it, and run this in the extracted directory:

```sh
./install.sh
```

Requires Apple silicon and macOS 12+. Intel Macs must [build from source](#build-from-source).
The installer enables login startup, installs `Nanoleaf.app` under
`~/Library/Application Support/nanoleaf/`, and links `~/.local/bin/nanoleaf` to it.
Add `~/.local/bin` to PATH. Use the installer again for updates; keep the app intact.

The release is self-signed, not Apple-notarized. If blocked, attempt to run the
app, then use **System Settings → Privacy & Security → Open Anyway**. Managed
Macs may require IT approval.

In **Privacy & Security**, authorize the installed `Nanoleaf.app` for:

- **Accessibility:** intercept brightness/temperature shortcuts.
- **Location Services:** calculate sunset when scheduling is enabled.

Run `nanoleaf service status` afterward to activate/check shortcuts. Changing
signing identity requires new authorization; same-certificate updates retained
both permissions on the development Mac. If shortcuts remain unavailable,
remove and re-add the installed app in Accessibility.

## Commands

| Command | Behavior |
| --- | --- |
| `on` / `off` | Restore remembered temperature/nonzero brightness, or go dark while retaining them. |
| `toggle` | Invert saved on/off state; requires an earlier light command. |
| `brightness N` | Set 0–100%. Positive values turn on; zero retains the previous nonzero brightness. |
| `brightness up` / `down` | Adjust by 5 percentage points. Up from off starts at 5%; down from off does nothing. |
| `temp K` | Set 2700–6500 K and turn on at remembered brightness. |
| `temp up` / `down` | Cooler/warmer by 100 K; preserve brightness and on/off state. |
| `day` / `evening` | Apply saved profile defaults. Initially 4800 K/30% and 3500 K/30%. |
| `night` | Alias for `evening`, including its defaults and options. |
| `config` | Show profile defaults, schedule configuration, and config path. |
| `status` | Show device zones, calibration, and last saved settings—not measured LED output. |
| `service enable` / `disable` / `status` | Manage background control and login startup. |
| `schedule enable` / `disable` / `status` | Manage the optional sunset transition. |
| `help`, `--help`, `-h`, or no arguments | Show brief help. |

Light commands and `status` require a connected strip. Only one strip is supported.
Quit Nanoleaf Desktop or other lighting controllers before use.

### Profiles

```sh
nanoleaf day --temp 5200 --brightness 40          # One-time override
nanoleaf night --temp 3300 --brightness 20 --save # Apply and save defaults
```

Profile options use separate values (`--temp 5000`). Omitted values come from the
saved profile. Overrides update the remembered setting for `on`; only `--save`
changes profile defaults. A zero-brightness profile remembers its temperature
while retaining the previous nonzero brightness. Without prior device state,
remembered settings start at 4800 K/30%, independently of profile defaults.

## Background behavior

The service owns the USB connection; CLI commands reach it through a private
local socket. Without the service, commands open USB directly and exit.

- A three-second keepalive maintains online mode. Physical power toggles the
  remembered setting; mode alternates saved day/evening profiles, starting with
  day if none was selected. CLI profile selections participate in that cycle.
- USB reconnect turns the strip on at remembered color/brightness, even after
  it was switched off while disconnected. Startup and USB-error recovery preserve
  saved on/off state; initial startup with no state leaves it off.
- Screensaver/display sleep temporarily blanks the strip and restores it after
  both clear. While blanked, controller buttons are ignored and only `off` and
  `status` light commands are accepted. A reconnect while idle waits to turn on.
- System sleep attempts to blank the strip, then releases USB. While asleep or
  disconnected, firmware controls the strip; continued darkness is not guaranteed.
- Disabling the service restores standalone controller behavior after its online
  timeout. Do this before using another lighting controller.

Enable/restart while the Mac is active: idle detection depends on notifications
received while running. USB contention/errors retry every 30 seconds while the
device is present. An unreachable enabled service reports an error instead of
opening a competing USB connection.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Shift + display Brightness Up/Down | Brightness ±5 percentage points. |
| F18 / F19 | Warmer/cooler by 100 K, preserving brightness and on/off state. |

Shortcuts apply across keyboards and consume the matching presses. Other
modifiers pass through; F18/F19 require no Shift, Control, Option, or Command.
Brightness keys must emit brightness events, not F1/F2. On Keychron V10 Ultra,
Launcher → Custom → Any accepts `KC_F18` and `KC_F19` for remapping.

A passive indicator shows the result at the center of the display containing
the pointer, then fades after 2.2 seconds. Ordinary CLI commands show no indicator
and need no Accessibility permission.

## Sunset schedule

Enable with `nanoleaf schedule enable`; disable with `nanoleaf schedule disable`.
It is off by default and requires the service and Location permission.

From local sunset to civil dusk, the service blends saved day temperature and
brightness into evening values, checking about every 12 seconds. After dusk it
uses evening; before sunset it leaves the setting alone. **There is no morning
switch**—use `day`. Manual CLI, keyboard, or controller changes override automation
until the next sunset, including across restarts.

Scheduling never turns an off strip on or overrides idle blanking. After wake or
reconnect it catches up unless a manual override applies; the normal reconnect
power rule still applies.

Location comes from macOS approximately hourly, stays only in memory, and expires
after two hours. Dates/times follow the system time zone. Missing permission,
missing location, or no sunset/civil-dusk crossing pauses automation. Calculations
use [NOAA's solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF) locally;
macOS Location Services may need connectivity.

## Configuration and troubleshooting

Files under `~/Library/Application Support/nanoleaf/`:

| File | Purpose |
| --- | --- |
| `config.json` | Saved profiles and `sunsetAutomation` flag. |
| `state.json` | Last settings, selected profile, and manual-override time per device. |
| `calibration.json` | Optional override for the embedded [hardware calibration](CALIBRATION.md). |
| `service.log` | Service errors. |
| `Nanoleaf.app` | Installed service and its permission identity. |

Login startup is registered in
`~/Library/LaunchAgents/io.github.sashusha.nanoleaf.plist`.
`service disable` removes that registration but keeps the app and settings.

`service status` checks USB, idle blanking, shortcuts, and location. Saved state
can differ from visible light after another controller acts or power is lost.
JSON writes are atomic, but device output and file saves are separate: a save
error may leave the LEDs changed. Errors identify the failed operation.

## Build from source

Requires Apple's Swift toolchain (Xcode or Command Line Tools):

```sh
git clone https://github.com/sashusha/nanoleaf.git
cd nanoleaf
swift run --build-system native NanoleafChecks
swift build --build-system native -c release --product nanoleaf
./.build/release/nanoleaf --help
```

For an installable app with a persistent signing identity, follow
[Build and self-sign](SIGNING.md). A bare build can run standalone or create an
ad-hoc service via `service enable`, but changed builds may require permissions
again. Do not overwrite the executable inside an already signed app.
