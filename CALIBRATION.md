# Hardware color-temperature calibration

## Included profile and selection

The repository includes [NL82K2 hardware 1.1.0](calibrations/nl82k2-hw-1.1.0.json).
It was physically checked on one lightstrip with firmware 1.5.0. Other units of
the same revision have not yet been independently tested.

The CLI reads the connected model and hardware revision and selects an **exact**
model, USB vendor/product ID, and hardware revision match. It does not assume that
a calibration for hardware 1.1.0 works on hardware 1.0.0. Firmware versions are
listed as **tested**, not used as a hard compatibility requirement.

Example command output:

```text
On: 4000 K, 30%
Calibration: NL82K2 hardware 1.1.0 [nl82k2-hw-1.1.0]
Firmware: 1.5.0 (tested)
```

With no exact match, the command reports the connected model/revision and uses
the generic RGB approximation. If reading the revision fails, it reports that
failure and uses the generic approximation. An unreadable firmware version does
not prevent a hardware match; a readable but unlisted firmware version is
explicitly reported as not listed as tested.

## File format

Each file in `calibrations/` is one profile with:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `1`. Unsupported versions are rejected. |
| `id` | Stable profile ID, such as `nl82k2-hw-1.1.0`. |
| `device.model` | Exact device model, currently `NL82K2`. |
| `device.vendorId` / `device.productId` | USB IDs as hex strings: `0x37FA` / `0x8202`. |
| `device.hardwareVersion` | Exact hardware revision, such as `1.1.0`. |
| `testedFirmwareVersions` | Firmware versions physically tested with the profile. |
| `temperatureRange` | `min: 2700`, `max: 6500`, `step: 1`. |
| `rgbByKelvin` | 3,801 RGB triples, one per integer Kelvin from 2700 through 6500. Each channel is an integer 0–255, before brightness scaling. |

Profiles can be shared between units with the same hardware revision. Command
output identifies the selected profile, hardware revision, and tested firmware.

## Standalone builds

Profiles are embedded in the executable, so copying only the built `nanoleaf`
binary is sufficient. No resource bundle, downloaded data, or Nanoleaf Desktop
installation is needed at runtime.

After editing or adding a canonical JSON profile, regenerate the embedded copy:

```sh
python3 Scripts/generate-calibrations.py
swift run --build-system native NanoleafChecks
swift build --build-system native -c release --product nanoleaf
```

Commit the JSON and `Sources/NanoleafCore/BundledCalibrations.generated.swift`
together. Generation is deterministic. Do not edit the generated file directly.

## Optional local overrides

`~/Library/Application Support/nanoleaf/calibration.json` may hold one profile
object or an array of profile objects in the same format. An exact matching local
profile takes precedence over the embedded profile. If none matches, the CLI
tries embedded profiles; if neither matches, it uses the generic approximation.
Multiple exact matches within a set are rejected rather than selected arbitrarily.
Malformed files/profiles are reported rather than silently ignored.

Profiles do not change `config.json` defaults or `state.json` restore settings.
Changing a calibration changes the rendered RGB the next time a command applies
the remembered temperature. `status` identifies the current matching profile,
not the profile necessarily used when the saved setting was last rendered.

## Rendering and limits

For each calibrated RGB channel `c` and brightness `b`:

1. `scaled = round(c * b / 100)`
2. `encoded = round(15 + 240 * scaled / 255)`
3. Send channels in **GRB** order for every zone.

Zero brightness produces `[15,15,15]`, the black frame. All light-changing
commands share this conversion. Without calibration, the generic approximation uses single-stage rounding:
`encoded = round(15 + 240 * c / 255 * b / 100)`.

The profile's numerical values were sampled from the installed Desktop 2.5.0
calibration implementation for this hardware. This repository does not include
Nanoleaf application code or libraries. The project's MIT license does not itself
establish rights in third-party material.

Matching Desktop's output is not a colorimeter measurement. Kelvin remains a
requested setting, not proof of the emitted light's physical CCT. Hardware,
firmware, or calibration changes may require an updated profile.
