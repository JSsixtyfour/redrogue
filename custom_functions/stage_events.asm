; custom_functions/stage_events.asm
;
; Procedural stage-event support that is reached ONLY by farcall, split out of
; custom_functions/wild_area_selection.asm into its own section.
;
; WHY THE SPLIT (2026-09-17). Adding TM theft overflowed the "rogue" section by
; 122 bytes in the debug build: `Section "rogue" grew too big (max size =
; 0x4000 bytes, reached 0x407A)`. The theft itself CANNOT leave that section -
; it reads RecoveryItemTable / StatItemTable / ValuableItemTable and calls
; RemovePocketItem and RemoveTMHM, all of which live there, and a raw `ld hl,
; <table>` across banks reads whatever happens to be mapped. So the routines
; that have NO same-bank dependency moved out instead.
;
; Everything here is entered by farcall from another bank already, so nothing
; about the call convention changed. `predef ShowObject` is bank-safe: Predef
; saves hLoadedROMBank and restores it before returning (home/predef.asm).
;
; CONTRACT for adding to this file: only routines with no same-bank reference.
; Anything that reads a table or plain-calls a helper in "rogue" belongs beside
; it, not here.

; PINNED REACTIVELY to $3A. Left floating, rgblink's first fit dropped this
; 188-byte section into bank $03 - one of the tightest banks in the ROM - and
; took it from 73 free bytes down to 59. That is the documented first-fit
; pressure hazard (project_romx_firstfit_bank_pressure): the linker backfills
; the smallest hole it can, so an unpinned section gravitates to exactly the
; bank that can least afford it. $3A had ~9 KB free and holds nothing this
; touches, and everything here is farcall-only, so the bank choice is free.
SECTION "Stage Events", ROMX, BANK[$3A]

; Zeroes the theft record's tag. Called at the top of every theft and from the
; lobby-time reset, so a record can never outlive the visit that created it.
; Clobbers a.
StageEventClearStolenRecord::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	xor a
	ld [sStolenKind], a
	ld [sStolenItem], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

StageEventStageSprites::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld [sStageEventSprite6], a      ; a is still 0: default both slots to unused
	ld [sStageEventSprite7], a
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	ret z                           ; STAGE_EVENT_NONE - leave both at 0
	; No hideout means the generator found nowhere for the villain to go after
	; the theft, so the event must not manifest AT ALL - appearing and then
	; having nowhere to vanish to would be worse than not appearing. Gating it
	; here, on the sprite bytes, makes that one decision rather than one per
	; consumer: every later stage of the lifecycle already treats a zero sprite
	; as "this slot does not exist".
	ld a, [sStageEventHideoutX]
	cp STAGE_EVENT_NO_HIDEOUT
	ret z
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	dec a                           ; type is 1-based; table row is 0-based
	add a                           ; 2 bytes per row
	ld c, a
	ld b, 0
	ld hl, StageEventSpriteTable
	add hl, bc
	ld a, [hli]
	ld [sStageEventSprite6], a
	ld a, [hl]
	ld [sStageEventSprite7], a
	ret

; One row per STAGE_EVENT_* type, starting at type 1: the sprite for NPC object
; slot 6, then for slot 7. 0 = this event does not use that slot.
;
; Jessie and James are the only pair among the villains, so every other villain
; row leaves slot 7 empty; STAGE_EVENT_BOTH_GOOD is the good-NPC pair. All five
; sprites are 12-tile walking sprites that already exist with .png/.2bpp in the
; tree, and procedural maps are indoor, so the outdoor sprite-set bound that
; restricts which SPRITE_* a route may use does not apply to any of them.
;
; SUPER_NERD and ROCKET are placeholders for the Psychic and the Burglar chosen
; for flavour from sprites already on other maps; 7f may repoint them when it
; wires the trainer classes. Nothing else keys off these values.
StageEventSpriteTable:
	db SPRITE_JESSIE,        SPRITE_JAMES         ; STAGE_EVENT_JESSIE_JAMES
	db SPRITE_SUPER_NERD,    0                    ; STAGE_EVENT_PSYCHIC
	db SPRITE_ROCKET,        0                    ; STAGE_EVENT_BURGLAR
	db SPRITE_NURSE,         0                    ; STAGE_EVENT_JOY
	db SPRITE_OFFICER_JENNY, 0                    ; STAGE_EVENT_JENNY
	db SPRITE_NURSE,         SPRITE_OFFICER_JENNY ; STAGE_EVENT_BOTH_GOOD
	ASSERT NUM_STAGE_EVENT_TYPES == 6, "StageEventSpriteTable needs a row per type"

; ============================================================
; StageEventShowCaveNpcs  (Phase 7b)
; Reveals whichever of the cave's two stage-event NPC objects this event
; actually uses. Both default to OFF in ToggleableObjectStates, because the
; common case - a cave with no event - should show neither.
;
; The staged SPRITE byte is the single source of truth for "is this slot in
; use". Re-deriving it from wStageEvent's type here would be a second copy of
; the same decision, free to drift out of step with StageEventStageSprites;
; reading the byte that routine published cannot drift.
;
; Farcalled from ProceduralCave1_Script's EVENT_ENTER_ROOM setup. Reaching
; ShowObject from ROMX is safe: Predef (home/predef.asm) saves hLoadedROMBank
; on entry and restores it before returning.
; Clobbers a/bc/de/hl.
; ============================================================
StageEventShowCaveNpcs::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld a, [sStageEventSprite6]
	ld d, a
	ld a, [sStageEventSprite7]
	ld e, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, d
	and a
	ret z                           ; no event armed - leave both hidden
	push de                         ; ShowObject clobbers freely
	ld a, TOGGLE_WILD_AREA_NPC_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	pop de
	ld a, e
	and a
	ret z                           ; single-NPC event
	ld a, TOGGLE_WILD_AREA_NPC_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ret

; ============================================================
; StageEventClearStagedSprites  (Phase 7c)
; Zeroes sStageEventSprite6/7, from the top of SpecialEncounterRollAndAssign
; beside the wStageEvent clear.
;
; This is the STRUCTURAL half of the phantom-NPC fix; the other half is the
; per-map gate in ProcBossPatchStageSprite. Either alone stops today's bug, but
; only this one stops it coming back: without it, the staged sprites outlive
; the assignment that set them, because only a stage's own preload ever writes
; them and only the Cave has one that does. Anything that later reads them on
; another stage - a new stage growing NPC slots, a debug path, a reordering -
; would see a previous cave's villains. Clearing at the single choke point
; every lobby selection passes through means there is no stale value to read,
; rather than a rule that each new stage has to remember.
;
; ORDERING, checked not assumed: the lobby does `call SelectAndPatchLobbyExit`
; then `call ProcPreloadAssignedWildArea` (custom_functions/dice_items.asm:60),
; so the roll and this clear both run BEFORE the preload that re-stages them.
; Clearing here cannot wipe the sprites the current assignment just published.
;
; Opens and closes its own SRAM window: this runs from the lobby, where no
; caller guarantees SRAM state either way.
; Clobbers a.
; ============================================================
StageEventClearStagedSprites::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld [sStageEventSprite6], a
	ld [sStageEventSprite7], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	; Phase 7d: the theft record is the other half of this lobby-time reset,
	; so a robbery can never outlive the visit that produced it. It gets its
	; own SRAM window rather than sharing this one, because it lives in a
	; DIFFERENT bank (1, "Save Data") from the sprites above (0).
	jp StageEventClearStolenRecord
