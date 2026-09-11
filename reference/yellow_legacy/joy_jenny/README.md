# Yellow Legacy Joy and Jenny battle reference

This directory preserves the deferred YL-6B material without activating it.
Nothing here is included by `main.asm`, and the portrait PNGs at
`gfx/trainers/joy.png` and `gfx/trainers/jenny.png` are not converted or
assembled. The package therefore has no ROM, RAM, save, event, or runtime
effect.

Source: `cRz-Shadows/Pokemon_Yellow_Legacy` at commit
`15169d137e2ef778e8765f7f3381acc4093dc169`.

- `options.asm` records the donor parties, move overrides, and lifecycle seams
  as comments so they can be adapted after a Red Rogue role is chosen.
- `gfx/trainers/joy.png` is credited by the donor to ZuperZACH.
- `gfx/trainers/jenny.png` is credited by the donor to Karlos.

Before activation, choose the destination system, progression gate, level or
scaling policy, rewards, rematch policy, loss/blackout behavior, and trainer
class allocation. Do not reuse the donor's `wGameStage`, Squirtle gift event,
or map script state without a fresh Red Rogue lifecycle audit.

Possible future integration points, all deliberately inactive:

1. Add trainer constants and pointer/money records.
2. Convert and include the portraits in an approved trainer-picture section.
3. Add parties and special-move records using the current trainer data format.
4. Adapt one battle lifecycle to the selected Red Rogue system.
5. Allocate and initialize any new persistent event state.
6. Build all ROM variants, remeasure placement, and complete focused runtime
   acceptance before enabling the second battle.

