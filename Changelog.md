# ImmersionFade Changelog

## 0.6.5
- Pet controls are now managed by default through Forever's top-level `PetActionBar` frame.
- The pet action bar is hidden during exploration and shown in combat/full-HUD states, matching the normal action bars.
- The separate pet unit frame remains unchanged and optional.

## 0.6.4
- Added support for Forever's separate `GamepadReticle` frame.
- The central controller reticle now follows the same contextual visibility rules as the controller action overlay: hidden during exploration, shown while LB/LT/RB/RT are held, and always shown in combat/full-HUD states.

## 0.6.3
- Fixed resource-aware player-frame visibility on WoW Forever's modern client, where primary resource values such as Mana can be Secret Values.
- Uses `UnitPowerPercent()` with a step curve and passes the resulting secret-safe alpha directly to the player frame instead of inspecting the resource value.
- Preserves the readable-resource fallback for clients where power values are not secret.
- Added `/imfade resource` diagnostics for primary-resource type and secrecy handling.

## 0.6.2
- Player frame is now resource-aware during exploration.
- Keeps the player frame visible while a naturally-restoring primary resource is below maximum.
- Mana, Energy, Focus, and Essence are treated as readiness resources.
- Builder resources such as Rage, Fury, Runic Power, Insanity, Holy Power, and Soul Shards do not force the player frame visible.
- Resource changes and primary-resource swaps update the frame automatically.

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