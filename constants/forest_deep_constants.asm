; The Forest's optional deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Forest SPEC,
; custom_functions/forest_deep_floor.asm). Floor 2 is PROCEDURAL_FOREST again
; with the Forest's SRAM state exchanged for a shadow copy kept in the cave's
; idle bank-0 buffer: nothing writes sProcCaveStagingBuffer during a Forest
; stage (measured, plan Forest Phase 0.2), and it shares bank 0 with the
; Forest's own state, so the exchange never switches banks.
;
; A deep Forest has floor 2 INSTEAD of the grotto: floor 1's grotto-style
; opening leads down to floor 2's entrance, floor 2's exit leads back up to
; that opening. An encounter rolled for the grotto stands on floor 2.

; The shadow, all bank 0, inside the cave's 600 B buffer:
DEF FOREST_DEEP_MAP_SIZE     EQU 400 ; sProcForestStagingBuffer, compact 20x20
DEF FOREST_DEEP_STATE_SIZE   EQU 102 ; sProcForestExitI..sProcForestGenScratch + 80
DEF FOREST_DEEP_BLOCK_SIZE   EQU 21  ; sProcForestExitI..sProcForestAlgoForce (no scratch)
; Floor 2's optional encounter stands in object slot 8 (F6 adds the object).
DEF FOREST_OPTIONAL_MON      EQU 8
DEF FOREST_DEEP_SHADOW_MAP   EQUS "sProcCaveStagingBuffer"
DEF FOREST_DEEP_SHADOW_STATE EQUS "(sProcCaveStagingBuffer + FOREST_DEEP_MAP_SIZE)"
; The control word: a byte and its complement. Only the Forest's lobby preload
; writes it (ForestDeepLobbyDecide), so a cave's map bytes left here can only
; matter if they happen to pass the check, and a Forest stage always rewrites it
; before any Forest load reads it.
DEF FOREST_DEEP_CTRL         EQUS "(sProcCaveStagingBuffer + FOREST_DEEP_MAP_SIZE + FOREST_DEEP_STATE_SIZE)"
DEF FOREST_DEEP_MAGIC        EQU $C0 ; bits 5-7 when valid (deep)
DEF FOREST_DEEP_MAGIC_MASK   EQU $E0
DEF BIT_FOREST_DEEP_LIVE_2   EQU 0   ; the live buffer holds floor 2
DEF BIT_FOREST_DEEP_MADE     EQU 1   ; floor 2 has been generated
DEF BIT_FOREST_DEEP_HOUSE_2  EQU 2   ; the coin put the rest house on floor 2
DEF BIT_FOREST_DEEP_BALLS_2  EQU 3   ; floor 2 keeps ball 2 too (slot 3), from the coin's bit 3
DEF BIT_FOREST_DEEP_OPENING_2 EQU 4  ; floor 2 has its own opening (its exit is closed)
	ASSERT (1 << BIT_FOREST_DEEP_OPENING_2) & FOREST_DEEP_MAGIC_MASK == 0
; The deep-floor roll, made once per Forest in the lobby, is the shared ramp
; (DeepRampRoll, DEEP_ODDS_* in round_constants.asm; 50% flat until 2026-11-20).
; 0 = every Forest is decided ordinary: the kill switch. The PyBoy harness
; decides Forests ordinary on its own unless a test sets allow_deep_forest_floor.
DEF FOREST_DEEP_ENABLED      EQU 1

; While floor 2 generates, what its finalize would rewrite for the Forest as a
; whole is saved here: the ForestDeepSavedWram list, then the 10 SRAM bytes from
; sProcCavePalette (the palettes and the stage-event hideout). The list's
; "house" tail (the rest house's lobby offers and residents) is put back only
; when the house is on floor 1; wProcForestWildBudget is last of the always part.
; Mirrors of the generator's own constants (procedural_forest_gen.asm ASSERTs
; that they still agree): a plain tree block, and sProcForestItemGot's house
; site field (site index + 1, 0 = no house).
DEF FOREST_DEEP_TREE         EQU 2         ; PF_TREE
DEF FOREST_DEEP_HOUSE_MASK   EQU %00011111 ; PF_HOUSE_SITE_MASK
DEF FOREST_DEEP_SAVE         EQUS "(sProcCaveStagingBuffer + FOREST_DEEP_MAP_SIZE + FOREST_DEEP_STATE_SIZE + 2)"
DEF FOREST_DEEP_SRAM_TAIL    EQU 10
; 4 always (boss species and form, wStageEvent, wild budget), then the house
; part: 17 offer bytes, the trade form, the trade flag byte, the bought-Pokemon
; event byte, the two residents' toggle bytes.
DEF FOREST_DEEP_NUM_SAVED_WRAM EQU 4 + 17 + 1 + 1 + 1 + 2
DEF FOREST_DEEP_NUM_ALWAYS     EQU 4 ; restored on every first descent
; Like the grotto, the floors meet opening to opening: floor 1 leaves by its
; opening on wall N/W/E and floor 2's faces it (S/E/W). The wall floor 2's must
; use (0N/1W/2E/3S), stored by the first descent for FGCarveOpening.
DEF FOREST_DEEP_UP_WALL      EQUS "(FOREST_DEEP_SAVE + FOREST_DEEP_NUM_SAVED_WRAM + FOREST_DEEP_SRAM_TAIL)"

; The generic trainer (custom_functions/forest_generic_trainer.asm): object 9 of
; ProceduralForest. Picture 0 and parked when absent, as the optional slot 8.
DEF FOREST_GENERIC          EQU 9
DEF GENERIC_TRAINER_ODDS    EQU 256 ; of 256; 256 = every Forest (the trial)
