# Verification

Tested hardware: **NL82K2, revision 1.1.0, firmware 1.5.0**, on one Mac.
Human verification covered everyday CLI use; Codex generated the code and tests
and performed technical checks. There has been no independent code review.

## Checks performed

- v0.2.5 passed 27 test groups covering parsing, saved state, USB framing,
  calibration, button/keyboard adjustments, reconnect and idle policies, and
  sunset scheduling with manual overrides and location edge cases.
- All 7,602 calibrated frames at 2700–6500 K and 10%/30% brightness matched
  Desktop’s conversion pipeline. Visual white matching is not a colorimeter test.
- Physical checks covered power, brightness, temperature, controller buttons,
  keyboard shortcuts, reconnect restoration, and screensaver/display-sleep blanking.
- Offline darkness worked with a manually selected dark scene; other scenes
  retained a faint glow. Native power-off alone did not solve this.
- Service checks covered command routing, malformed/stalled clients, socket
  permissions, and location delivery.
- Signed updates retained Accessibility and Location permissions. v0.2.4–v0.2.5
  installation checks covered symlink invocation, rejected signing downgrades,
  retained registration through stop/start, and repeated enable without restart.

## Not verified

Other devices/revisions or Macs, Intel builds, older macOS versions, fullscreen
and multi-display indicator placement, full system sleep/wake, battery impact,
a complete real sunset transition, offline-scene persistence after power loss,
disabled-service persistence through reboot, background notification frequency,
and Developer ID/notarized releases.
