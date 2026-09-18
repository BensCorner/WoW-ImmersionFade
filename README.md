# ImmersionFade

ImmersionFade is a lightweight World of Warcraft addon built around one idea:

**Let the UI get out of the way while exploring, and bring it back when it is needed.**

It is designed for WoW: Forever's modern UI architecture and keeps the default Blizzard UI intact rather than replacing it.

## What it does

During exploration, ImmersionFade can fade or hide UI elements that are not immediately useful, such as:

- Action bars and action bar artwork
- Player frame
- Micro menu and bag controls
- Cooldown Manager frames
- Swing timer
- Controller action overlay
- Performance / latency display

Some crucial elements remain visible, including the minimap, quest tracker, target frame and chat. The player frame is contextual: during exploration it remains visible while a naturally-restoring primary resource such as Mana, Energy, Focus, or Essence is below maximum, then fades away once that resource is full. Builder resources such as Rage or Fury do not keep it visible.

When combat begins, the managed combat UI fades back in automatically. The Forever controller action overlay is always visible in combat. During exploration it stays hidden until LB, LT, RB, or RT is held, then fades away again when the modifier is released.

Additional behavior includes:

- Smooth fade-in and fade-out transitions
- Resource-aware player frame: stays visible while Mana, Energy, Focus, or Essence is still recovering, including modern Secret Value power data
- Reduced chat opacity while exploring
- XP bar shown briefly when experience is gained
- Mouse blockers for invisible UI controls
- Temporary HUD reveal with `/imfade peek`
- Edit Mode and vehicle / override bar handling
- Contextual controller UI: always visible in combat; hidden during exploration unless LB/LT/RB/RT are held
- WoW: Forever client detection and diagnostics

## Useful commands

```text
/imfade status
/imfade pause
/imfade peek 5

/imfade groups
/imfade group <group> on
/imfade group <group> off

/imfade alpha <group> <value>
/imfade delay <seconds>
/imfade fadein <seconds>
/imfade fadeout <seconds>
/imfade xpseconds <seconds>

/imfade blockers on
/imfade blockers off

/imfade client
/imfade resource
/imfade frames
/imfade reset
```

For a convenient temporary HUD keybind, create a macro containing:

```text
/imfade peek 5
```

This reveals the UI for five seconds and then automatically returns to the appropriate exploration or combat state.

## Philosophy

ImmersionFade is intentionally not a complete UI replacement.

The goal is to preserve the familiar Blizzard interface while making Azeroth itself the focus during normal exploration. UI elements should appear when they provide useful information, then quietly disappear when they are no longer needed.

## Compatibility

ImmersionFade is currently developed for **World of Warcraft: Forever** and its modern/Retail-based UI architecture.

Forever is still evolving, so Blizzard frame names and behavior may change during beta. `/imfade frames` can be used to help diagnose UI elements that are not yet managed correctly.

On modern/Forever clients, primary resource values may be protected as **Secret Values**. ImmersionFade does not inspect or compare those values; it uses Blizzard's curve/display APIs to convert the secret resource percentage directly into player-frame opacity.

## Development status

ImmersionFade is an actively evolving personal addon. New Forever-specific frames and behaviors are added as they are encountered in-game.
