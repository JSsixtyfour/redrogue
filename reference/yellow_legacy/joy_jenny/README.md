# Yellow Legacy Joy and Jenny battle reference

> **ACTIVATED 2026-09-17, Phase 7f of PROCEDURAL_WILD_AREA_PLAN.md.** Joy and
> Jenny are now the two good-NPC procedural stage events (`STAGE_EVENT_JOY`,
> `STAGE_EVENT_JENNY`, and the pair `STAGE_EVENT_BOTH_GOOD`), rollable on any
> wild area. `options.asm` and this README are kept as a historical record of
> what was adapted and what was deliberately NOT carried over; nothing in this
> directory is INCLUDEd by `main.asm` - the real trainer classes, pools, and
> text live in `constants/trainer_constants.asm` (NURSE_JOY, OFFICER_JENNY),
> `data/trainers/pools.asm` (POOL_JOY, POOL_JENNY), `data/trainers/
> party_specs.asm`, `data/trainers/special_moves.asm`, and `gfx/pics.asm`.
>
> The six-step checklist below: steps 1-3 done as described (constants/
> pointers, portraits converted and included in `gfx/pics.asm`'s "Joy Jenny
> Portraits" section, donor move records pasted into `SpecialTrainerMoves`
> keyed to the round-9 tier). Step 4 (lifecycle) used the STAGE EVENT
> lifecycle (7c/7e), not the donor's `wGameStage`/`YesNoChoice` offer, per
> this README's own warning below - the donor lifecycle has no Red Rogue
> equivalent. Step 5 (persistent state) needed nothing new: `wStageEvent`
> already carries the whole lifecycle. Step 6 (build + remeasure) is recorded
> in `ROM_BIBLE.md`'s dated 7f entry.
>
> Levels and team size were NOT pasted from the donor's flat level-65 six-mon
> teams - see "Two adaptations are mandatory" below, which this activation
> followed: the donor lists became POOL_JOY/POOL_JENNY (species only), and
> level/team size come from `stage_event_team_spec`'s own round ladder
> (`data/trainers/party_specs.asm`), the same mini-boss-style scaling the
> other three stage-event characters (Jessie & James, the Psychic, the
> Burglar) use.

This directory preserves the deferred YL-6B material as a historical record.
The portrait PNGs at `gfx/trainers/joy.png` and `gfx/trainers/jenny.png` are
now converted and assembled (see the note above); nothing else in this
directory is included by `main.asm`.

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

