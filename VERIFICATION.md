# Verification

This project was entirely vibe-coded with OpenAI Codex, including the code,
automated tests, and documentation. The only human verification was testing the
actual CLI during regular, everyday use. The automated checks and technical
inspections below were performed by Codex, not independently reviewed by a human.

## Automated checks

All 17 test groups pass, and the release executable builds successfully.
The dependency-free suite covers:

- Argument parsing, ranges, and configuration preservation.
- TLV responses, HID packet boundaries, and reference frame fixtures.
- Zero/low brightness, temperature changes, and off/on restoration.
- Saved-state validation and preservation after rejected writes.
- Calibration validation, exact hardware matching, local overrides, and compatibility loading.
- Bundled profile selection and calibrated frame scaling.

Embedded profile generation is deterministic. The calibrated Swift output was
compared with the Desktop calibration and brightness pipeline for all 7,602
frames spanning 2700–6500 K at 10% and 30% brightness, with matching results.

## Device checks and everyday usage

Tested hardware: **NL82K2, revision 1.1.0, firmware 1.5.0**.

The installed CLI selects `nl82k2-hw-1.1.0` from the executable without a local
calibration override. The profile contains the same 3,801 RGB samples used in
the physical tests.

Human observations during everyday CLI use indicated a match to Desktop's white near 4000 K at 30%.
The installed CLI sequence **4000 K/30% → 10% → off → on at 10% → 30%**
produced visible dimming, complete darkness, and restoration of white and
brightness as observed by the user. Codex checked that profile defaults remained unchanged.

Binary dependency inspection showed only system libraries. Nanoleaf Desktop
and its libraries are not required at runtime.

## Scope and limitations

Physical results cover one device; other units and hardware revisions have not
been independently tested. Visual agreement with Desktop is not an
instrument measurement of color temperature.

`status` reports saved CLI settings, not measured LED state. Another controller,
a button, or power loss can make those settings stale. A frame acknowledgement
confirms delivery, not physical appearance. These verification results are test
evidence, not a live reading of the connected strip.
