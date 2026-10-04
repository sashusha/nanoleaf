# Verification

Physical observations cover one **NL82K2, hardware 1.1.0, firmware 1.5.0**.
Human verification consisted of everyday CLI use; automated checks and technical
inspections were performed by Codex, not independently reviewed.

## Automated checks

The v0.2.5 build passed all 27 test groups. Coverage includes parsing and
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
- Requesting native brightness zero preserved online RGB output but left a faint
  glow with some offline scenes (red or green matching the selected scene).
  Readback was 16. Native power-off did not guarantee offline darkness either.
- A manually selected offline scene stayed completely dark after disconnecting
  from both RGB-only control and the installed service; reconnect restored normal
  lighting. This scene has not been identified or tested through full power loss.
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
reauthorization. The strip was disconnected during that initial signing test.
Release archives passed signature verification; the v0.2.1 archive was also
inspected for private-key files and local user build paths.

For v0.2.4–v0.2.5, live installation checks confirmed that CLI-symlink enable
preserved the certificate, standalone/ad-hoc replacements were rejected, updates
retained the registration file, and repeated enable retained the running process.
Disable/enable and stop/start retained the registration and restored service
operation with Accessibility and Location still active. Login/reboot persistence
of the disabled state and notification frequency were not physically tested.

## Not verified

Other devices, hardware revisions, Macs, older macOS versions, fullscreen and
multi-display placement, full system sleep/wake, battery impact, a complete real
sunset transition, and Developer ID/notarized releases. Visual matching is not
an instrument measurement of color temperature.
