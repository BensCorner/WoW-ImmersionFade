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
- Melee and ranged swing timers
- Pet action bar / pet controls
- Controller action overlay and central reticle
- Performance / latency display

Some crucial elements remain visible, including the minimap, quest tracker, target frame and chat. The player frame is contextual: during exploration it remains visible while health is recovering or while a naturally-restoring primary resource such as Mana, Energy, Focus, or Essence is below maximum. Builder resources such as Rage or Fury do not keep it visible.

When combat begins, the managed combat UI fades back in automatically, including the pet action bar when a pet is available. The Forever controller action overlay and central reticle are always visible in combat. During exploration they stay hidden until LB, LT, RB, or RT is held, then fade away again when the modifier is released.

Additional behavior includes:

- Smooth fade-in and fade-out transitions
- Health- and resource-aware player frame: stays visible through post-combat health recovery and while Mana/Energy/Focus/Essence is still recovering
- Reduced chat opacity while exploring
- XP bar shown briefly when experience is gained
- Mouse blockers for invisible UI controls
- Temporary HUD reveal with `/imfade peek`
- Edit Mode and vehicle / override bar handling
- Contextual controller UI and reticle: always visible in combat; hidden during exploration unless LB/LT/RB/RT are held
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
/imfade health
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

On the current Forever beta, player health is deliberately exposed to addons as a **Secret Value**. Addons may pass secret values into Blizzard widgets for display, but they cannot safely compare them to determine whether health is exactly full. ImmersionFade therefore does not inspect health values on Forever: after combat, and whenever `UNIT_HEALTH` fires out of combat, it keeps the player frame visible; after health updates have been quiet for 3.25 seconds it hands visibility back to the existing secret-safe resource curve. This combines health recovery with Mana/Energy/Focus/Essence readiness without attempting to bypass Blizzard's restrictions. `/imfade health` and `/imfade resource` report the active paths.

## Development status

ImmersionFade is an actively evolving personal addon. New Forever-specific frames and behaviors are added as they are encountered in-game.
