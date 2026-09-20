# nanoleaf

Native macOS Swift CLI for Nanoleaf PC Screen Mirror Lightstrip NL82K2 (USB 37FA:8202). No third-party package or Nanoleaf Desktop runtime dependency.

Independent project, not affiliated with or endorsed by Nanoleaf. Licensed under [MIT](LICENSE), with the retained attribution in [third-party notices](THIRD_PARTY_NOTICES.md).

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

Initial defaults: **day 4800 K/30%**, **evening 3500 K/30%**. Brightness accepts integers from 0 to 100; temperature accepts integers from 2700 to 6500 K. Kelvin is an approximate RGB white, not a calibrated color temperature.

| Command | Behavior |
| --- | --- |
| `on` | Restore the last CLI temperature and nonzero brightness. |
| `off` | Send black, retaining those settings for the next `on`. |
| `toggle` | Invert the saved CLI on/off state; fail if no state has been saved for this device. |
| `brightness N` | Positive values turn on at the remembered temperature. Zero sends black and retains the previous nonzero brightness. |
| `temp K` | Set the temperature and turn on at the remembered nonzero brightness. |
| `day` / `evening` | Apply that profile's saved values, with any supplied overrides. Positive brightness turns on; zero sends black. |
| `config` | Show effective profile defaults and their file path. Does not require the device. |
| `status` | Query the connected zone count and show the last saved CLI setting, including remembered on brightness. |
| `help`, `--help`, `-h`, or no arguments | Show help without accessing the device or configuration. |

All commands except help and `config` require a connected device. Help flags are top-level commands; `nanoleaf day --help` is not supported.

### Profiles and remembered settings

`--temp`, `--brightness`, and `--save` are available only for `day` and `evening`. Use separate arguments such as `--temp 5000`, not `--temp=5000`. Missing values, duplicate options, unknown options, and out-of-range values are rejected.

Unspecified profile values come from that profile's saved defaults, not the current light setting. For example, `nanoleaf evening --brightness 20` uses the saved evening temperature. Without `--save`, overrides affect this run and the remembered setting for `on`; the profile defaults stay unchanged. With `--save`, the resulting profile is applied and its defaults are saved. The other profile is preserved. Saving requires a successful frame acknowledgement and a successful restore-state save first.

A zero-brightness profile remembers its requested temperature and retains the previous nonzero brightness for the next `on`. It sends black directly, without a temporary bright frame.

Without saved state for this device, remembered settings start at **4800 K/30%**, independently of any customized day/evening defaults. Thus a first `brightness 10` uses 4800 K, a first `temp 3500` uses 30%, and a first `on` uses 4800 K/30%. `toggle` instead requires an earlier successful light-changing CLI command. Neither `config` nor `status` establishes restore state.

### Files and status

Files are under `~/Library/Application Support/nanoleaf/`:

- `config.json`: saved profile defaults. If absent, built-in defaults apply; the file is written by `--save`.
- `state.json`: last CLI settings, keyed by device serial when available. Written after successful light-changing commands.
- `.lock`: coordinates commands so they cannot interleave device transactions or saved-state updates. A concurrent command fails with a retry message.

JSON files are written atomically, but applying the frame, saving restore state, and saving profile defaults are separate operations. A save failure can leave the LEDs changed; the error message says which save failed. Invalid existing configuration/state is reported instead of silently overwritten.

`status` reports the **last CLI setting**, not a measurement of the LEDs. With no saved state it reports that the setting is unknown. Buttons, other controllers, unplugging, or power loss can make saved state stale; `toggle` still operates on that saved state. Commands cannot recover the color previously set by another app or a controller button. An acknowledged frame confirms delivery, not its physical appearance.

## Corrected USB behavior

The original implementation used the documented native power and brightness commands and plain RGB values. Those received valid acknowledgements but did **not** produce the intended LED output on this device. The earlier claim that those commands were physically verified was incorrect.

Inspection of the locally installed vendor app's USB implementation established its streaming convention:

- Channel order is **GRB**.
- Channel encoding is `round(15 + 240 × color/255 × brightness/100)`.
- Black is `[15,15,15]` for every zone.
- Brightness is scaled into every frame; the native brightness getter is not used as a proxy for emitted brightness.

The CLI sends complete solid-color frames using command 0x02, querying zone count with 0x03. It does not send 0x07/0x09 power or brightness writes. It retains the already working TLV framing and 64-byte HID report fragmentation. Black, day white at 30%, and day white at 10% were physically confirmed by the user during diagnosis. This implementation remains an approximate white conversion rather than Nanoleaf's proprietary hardware color calibration.

Protocol reference: [Nanoleaf USB Lightstrip Communication Protocol](https://nanoleaf.atlassian.net/wiki/spaces/nlapid/pages/2615574530/Nanoleaf+USB+Lightstrip+Communication+Protocol). The streaming details above come from the vendor implementation and device testing; the public protocol page alone does not establish them.

Quit other lighting controllers before use. The CLI opens the USB device directly and exits after its frame is acknowledged; no daemon is required. It refuses multiple matching devices rather than choosing one arbitrarily.

## Build and checks

Requires macOS 12 or later and Apple's Swift toolchain (Xcode or Command Line Tools). Run these commands from the project directory:

```sh
swift run --build-system native NanoleafChecks
swift build --build-system native -c release --product nanoleaf
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/nanoleaf "$HOME/.local/bin/nanoleaf"
```

`~/.local/bin` must be on your PATH. The native build-system flag matches the locally verified build; this Swift toolchain emits a deprecation warning for it.

The dependency-free checks work with Apple's Command Line Tools without XCTest. They cover argument ranges, configuration preservation, frame fixtures from the visual probes, zero/low brightness, off/on restoration across invocations, malformed replies, packet boundaries, and failed-write state preservation.

See `VERIFICATION.md` for the current verification evidence and limitations.

## License and attribution

Copyright (c) 2026 Alexander Vladimirov.

Project code is available under the [MIT License](LICENSE). The Kelvin-to-RGB
adaptation retains Tanner Helland's BSD 2-Clause notice; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Retain the applicable license
and attribution notices when redistributing source or binaries.
