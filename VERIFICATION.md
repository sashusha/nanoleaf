# Verification

Physical observations cover one **NL82K2, hardware 1.1.0, firmware 1.5.0**.
Human verification consisted of everyday CLI use; automated checks and technical
inspections were performed by Codex, not independently reviewed.

## Automated checks

All 27 test groups pass and the release builds. Coverage includes parsing and
aliases, saved-state/configuration compatibility, rejected writes, frame encoding,
calibration selection, relative adjustments, button handling, reconnect policy,
overlapping idle events, sunset interpolation, manual overrides, time zones,
invalid locations, and polar conditions.

The calibrated output matched the Desktop pipeline for all 7,602 tested frames
(2700–6500 K at 10% and 30%). Embedded calibration generation is deterministic.
Binary inspection found only system-library dependencies.

## Observed behavior

- White near 4000 K visually matched Desktop; brightness changes dimmed the strip,
  off was fully dark, and on restored the remembered setting.
- Physical power toggled off/restored; mode alternated saved day/evening profiles.
- USB reconnect restored the remembered setting, including after an offline
  physical power-off.
- Screensaver and display sleep blanked/restored the strip without changing the
  saved-state file.
- Brightness shortcuts changed the strip without changing monitor brightness;
  F18/F19 temperature shortcuts and centered indicators worked.

Service startup/shutdown, local command routing, malformed requests, stalled
clients, socket permissions, and system location delivery were checked locally.

## Signed updates

Two self-signed app versions had different code hashes and the same certificate
identity. After the first was authorized, installing the second preserved both
permissions: its event tap activated and a fresh location fix arrived without
reauthorization. The strip was disconnected during this test. The final release
archive passed signature verification and executable startup checks; it contains
no private-key files or local user build paths.

## Not verified

Other devices, hardware revisions, Macs, older macOS versions, fullscreen and
multi-display placement, full system sleep/wake, battery impact, a complete real
sunset transition, and Developer ID/notarized releases. Visual matching is not
an instrument measurement of color temperature.
