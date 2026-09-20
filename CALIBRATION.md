# Local color-temperature calibration

## Purpose

The generic Kelvin-to-RGB approximation describes an idealized RGB white.
Nanoleaf Desktop uses hardware-specific calibration, so the same nominal Kelvin
can look different. The CLI can use a local calibration snapshot to reproduce
that device-specific mapping without loading Desktop at runtime.

Normal commands do not import calibration automatically. When no matching local
calibration exists, they retain the generic approximation. `nanoleaf status`
reports which conversion is active; light-changing command output identifies
local calibration when used.

## Storage and format

File: `~/Library/Application Support/nanoleaf/calibration.json`.

The top-level JSON object maps device identifiers (the USB serial number when
available) to objects with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `source` | Nonempty string | Human-readable source/version of the calibration. |
| `hardwareVersion` | Nonempty string | Hardware revision used when generating it. Informational metadata, not a live hardware check. |
| `rgbByKelvin` | Array of 3,801 RGB triples | One triple for each integer Kelvin, from 2700 through 6500 inclusive. Channel values are integers 0–255 in **RGB** order, before brightness scaling. |

Device identity selects the entry. Use only samples appropriate for that
specific hardware. The CLI validates the selected entry before changing the
light. A malformed file or invalid selected entry causes an error rather than
silently reverting to generic color. A missing file or absent device entry uses
the generic approximation.

Data is held outside the Git repository. Profile defaults (`config.json`) and
last command state (`state.json`) remain separate. They are not changed by
creating a calibration file. Replacing or removing calibration changes the
RGB used the next time a command applies the remembered temperature.

## Rendering

For each calibrated RGB channel `c` and requested brightness `b`:

1. `scaled = round(c * b / 100)`
2. `encoded = round(15 + 240 * scaled / 255)`
3. Send channels in **GRB** order, repeated for every zone.

Zero brightness still produces `[15,15,15]`, the black frame. `on`, `off`,
`toggle`, `brightness`, `temp`, `day`, and `evening` all use the same conversion.

## Provenance and limitations

During local diagnosis, the installed official Desktop 2.5.0 calibration library
was queried once for a hardware 1.1.0 device (Desktop calibration type 2). Its
numeric output for every integer Kelvin from 2700 to 6500 was saved only in the
user's local calibration file. No library, table, or device identifier from that
snapshot is distributed with the project. The source tests use synthetic data.

The setup-time library access was a diagnostic step, not a runtime dependency or
an automatic import feature. Users supplying other calibration files are
responsible for their source and suitability. A firmware/hardware or Desktop
calibration change may require regenerating the local snapshot.

Matching Desktop's RGB output is not a colorimeter measurement. Reported Kelvin
remains a requested setting, not proof of the emitted light's physical CCT.
