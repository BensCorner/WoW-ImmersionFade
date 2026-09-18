# ImmersionFade Changelog

## 0.6.1
- Controller action UI now always remains visible while in combat/full-HUD mode.
- Improved RT detection on WoW Forever by checking direct gamepad key state in addition to mapped button state.
- Added active-device and combined-device mapped-state fallbacks for controller modifier detection.
- Preserved hold-to-reveal behavior for LB, LT, RB, and RT while exploring.

## 0.6.0
- Added support for WoW Forever's `GamepadMainActionBarFrame` controller action overlay.
- Controller UI is hidden by default and reveals while LB, LT, RB, or RT is held.
- Controller UI hides again immediately after the last shoulder/trigger modifier is released.
- Uses mapped gamepad-state polling instead of capturing controller input, avoiding interference with Blizzard's controller bindings.
- Added automatic remapping refresh when gamepad devices or configurations change.

## 0.5.1
- Added support for the WoW Forever swing timer.
- Swing timer now fades out during exploration and returns in combat.
- Added defensive support for possible off-hand swing timer frames.

## 0.5.0
- Added native support for the WoW Forever beta.
- Updated addon compatibility for Forever's modern/Retail-based UI architecture.
- Added support for modern action bar frames and artwork.
- Updated vehicle, override bar, Micro Menu, and bag handling.
- Added compatibility with modern Edit Mode.
- Improved safety around protected/restricted Blizzard UI elements.
- Added support for modern Cooldown Manager frames.