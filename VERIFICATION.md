# Verification after the streaming-frame fix

## Correction to the original verification

The original implementation received successful USB replies but the user observed green light from `off`/`on`, and bluish, excessively bright light from `day`. The original claim that all commands were physically verified was wrong. Native property readback did not establish the emitted RGB frame.

## Evidence for the fix

Read-only inspection of the installed vendor application identified GRB channel order, a channel floor of 15, software brightness scaling, and black-frame power-off. The app was not launched or used as a runtime dependency. The original packet fragmentation was retained because the diagnostic frames worked with it.

Standalone physical tests, confirmed by the user:

- `[15,15,15]` per zone: completely dark and remained dark after process exit.
- Day 4800 K/30%, GRB `[78,87,71]`: white and reasonably dim.
- Day 4800 K/10%, GRB `[36,39,34]`: clearly dimmer and still white.

All 11 regression test groups passed. Tests include hard-coded probe fixtures, prohibition of native power/brightness commands in the streaming controller, off/on restoration across separate instances and saved state, low/zero brightness, malformed replies, packet fragmentation, configuration round trips, and rejected-write state preservation.

The corrected release was installed at `~/.local/bin/nanoleaf`. The installed executable completed `day`, `off`, and `on` as separate processes; the user confirmed complete darkness during `off` and restoration of the same white and brightness with `on`. At the end of that verification, its saved setting was 4800 K/30%, on, with profile defaults day 4800 K/30% and evening 3500 K/30%. These are historical test results, not a live status reading.

The user subsequently confirmed that all behavior works as expected.

## Limits

Kelvin is approximate RGB white, not instrument-measured CCT. `status` explicitly reports saved CLI state rather than a measured LED state. Another controller, a button, or USB power loss may invalidate it. Frame acknowledgements establish delivery only. No proprietary library or Nanoleaf Desktop component is loaded at runtime.

## Subsequent color-temperature calibration diagnosis

The user later observed that the generic CLI white looked bluer than Desktop at
4000 K. This narrowed the earlier visual confirmation: it established working
white/dimming and off/on, not a match to Desktop's color-temperature calibration.

Computer control established Desktop's reference at 3993 K and 30%, and its
settings identified hardware 1.1.0 and firmware 1.5.0. Desktop's calibration
library returns the same RGB triple at 3993 K and 4000 K for that hardware. A
standalone frame using that triple was sent after Desktop quit; the user
confirmed no noticeable change from the Desktop reference.

A local snapshot was generated for every integer Kelvin from 2700 through 6500.
The compiled Swift calibrated output matched the Desktop calibration and
brightness pipeline for all 7,602 frames across that range at 10% and 30%.
The calibration snapshot remains outside this repository. Matching the vendor
pipeline numerically does not establish instrument-measured Kelvin accuracy.

The expanded suite passed all 15 test groups, including calibrated scaling,
file validation, device matching, and off/on restoration. The calibrated release
was installed locally and completed the 4000 K sequence 30% → 10% → off → on
at 10% → 30%. The sequence was repeated with five seconds at each step; the user confirmed
the Desktop-matched white, visible dimming, complete darkness, and correct
off/on restoration. Profile defaults were verified unchanged. Binary dependency inspection
showed only system libraries; no Nanoleaf library is loaded by the CLI.
