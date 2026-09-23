# Hardware calibration

The embedded [NL82K2 hardware 1.1.0 profile](calibrations/nl82k2-hw-1.1.0.json)
was checked on one strip with firmware 1.5.0. Its samples came from Desktop 2.5.0's
calibration implementation. No Nanoleaf application code or libraries are included;
the project's MIT license does not establish rights in third-party material.
Matching Desktop is not a colorimeter measurement.

## Selection

Model, USB IDs, and hardware revision must match exactly. Firmware is reported
as tested or untested, not used to reject a match. Commands identify the selected
profile; unavailable hardware metadata or no match uses generic RGB approximation.

`~/Library/Application Support/nanoleaf/calibration.json` can contain one profile
or an array. An exact local match takes precedence over embedded profiles.
Malformed files and multiple exact matches within a set are errors. Changing a
profile affects the next rendered command; `status` shows the current selection,
not necessarily the calibration used for the previous frame.

## Profile schema

| Field | Value |
| --- | --- |
| `schemaVersion` | `1` |
| `id` | Stable identifier, e.g. `nl82k2-hw-1.1.0` |
| `device.model` | `NL82K2` |
| `device.vendorId` / `device.productId` | `0x37FA` / `0x8202` |
| `device.hardwareVersion` | Exact revision, e.g. `1.1.0` |
| `testedFirmwareVersions` | Versions physically tested with the profile |
| `temperatureRange` | `min: 2700`, `max: 6500`, `step: 1` |
| `rgbByKelvin` | 3,801 RGB triples; integer channels 0–255 before brightness scaling |

After adding/editing a JSON profile under `calibrations/`:

```sh
python3 Scripts/generate-calibrations.py
swift run --build-system native NanoleafChecks
```

Commit the JSON and `Sources/NanoleafCore/BundledCalibrations.generated.swift`
together, then rebuild. Calibration data is embedded; no external resource file
is required at runtime. Preserve the complete app when distributing signed builds.

## USB rendering

Solid-color frames use command `0x02`, zone-count queries `0x03`, TLV framing,
and 64-byte HID reports. For calibrated channel `c` and brightness `b`:

```text
scaled  = round(c * b / 100)
encoded = round(15 + 240 * scaled / 255)
```

Channels are sent in GRB order to every zone. `[15,15,15]` is black. Generic RGB
uses single-stage rounding: `round(15 + 240 * c / 255 * b / 100)`.

[Nanoleaf protocol reference](https://nanoleaf.atlassian.net/wiki/spaces/nlapid/pages/2615574530/Nanoleaf+USB+Lightstrip+Communication+Protocol).
Streaming conventions were established through vendor implementation inspection
and device testing.
