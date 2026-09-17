; custom_functions/wild_area_selection.asm
; Wild-area door layer for the unified special-encounter roll (see miniboss.asm's
; SpecialEncounterRollAndAssign). No-repeat rotation over the four rollable types
; (Cave/Forest/Cemetery/Facility), tracked in wWildAreaState.

; type id (0-3) -> lobby door ENTRY map id. Cemetery enters at floor 1.
WildAreaTypeMaps:
	db PROCEDURAL_CAVE_1      ; WILD_AREA_CAVE
	db PROCEDURAL_FOREST      ; WILD_AREA_FOREST
	db PROCEDURAL_CEMETERY_1  ; WILD_AREA_CEMETERY
	db PROCEDURAL_FACILITY    ; WILD_AREA_FACILITY

; type id (0-3) -> its offered-this-cycle bit mask.
WildAreaTypeBit:
	db %001                   ; WILD_AREA_CAVE
	db %010                   ; WILD_AREA_FOREST
	db %100                   ; WILD_AREA_CEMETERY
	db %10000000              ; WILD_AREA_FACILITY

; ============================================================
; StageEventRoll  (Phase 7a)
; Rolls this lobby selection's stage event into wStageEvent: STAGE_EVENT_CHANCE
; out of 256 that anything happens at all, then a uniform pick over the wired
; types (1..STAGE_EVENT_MAX_ROLLABLE). The phase field is left at
; STAGE_EVENT_PHASE_WAITING and bit 5 clear, which is the correct starting
; state for every type.
;
; Called from SpecialEncounterRollAndAssign's .doWildArea, AFTER
; WildAreaPickAndAssign has settled the type and the doors, rather than from
; inside WildAreaPickAndAssign itself - that routine carries the forced/
; choosable flag in carry across its whole body, and there is no point in it
; where a clobbering call is free. Both routines live in the "rogue" section,
; so this is a plain call.
;
; wStageEvent is already zeroed by the clear at the top of
; SpecialEncounterRollAndAssign, so the two early returns here leave
; STAGE_EVENT_NONE behind without writing anything.
; Clobbers a/bc/hl. Preserves de.
; ============================================================
StageEventRoll:
	call Random                   ; a = 0..255
	cp STAGE_EVENT_CHANCE
	ret nc                        ; no event on this wild area
	ld c, STAGE_EVENT_MAX_ROLLABLE
	call Rangerandom              ; a = [0, MAX_ROLLABLE-1]
	inc a                         ; -> [1, MAX_ROLLABLE]; 0 is STAGE_EVENT_NONE
	ld [wStageEvent], a
	ret

; ============================================================
; StageEventStageSprites  (Phase 7b)
; Publishes the overworld sprite each stage-event NPC slot should wear into
; sStageEventSprite6/7, for ProcBossPatchStageSprite to install into PICTUREID
; in the window between LoadMapHeader and InitMapSprites.
;
; Called from a wild area's PRELOAD rather than its finalize, because the
; sprite has to be staged before the map is ever loaded, and the preload is the
; only hook guaranteed to run before the first load and to re-run per lobby
; assignment.
;
; A slot's table entry of 0 means "no NPC in this slot", and that is load
; bearing rather than conventional: LoadMapSpriteTilePatterns skips a slot
; whose PICTUREID is 0 (`and a / jp z, .nextSpriteSlot`), so an unused slot
; costs no VRAM tile-pattern slot at all. Hence the no-event path writes 0/0
; explicitly instead of leaving the previous assignment's sprites staged.
;
; SRAM: re-asserted to bank 0 here rather than trusted from the caller, per the
; standing rule about farcalls and rRAMG/rRAMB. Deliberately left OPEN on
; return - the caller (PCPreloadCave) owns this window and closes it itself.
; Clobbers a/bc/hl.
; ============================================================
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
StageEventClearStagedSprites:
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

; ============================================================
; StageEventDoTheft  (Phase 7d)
; The robbery. Farcalled from the map script between the villain's arrival
; text and the dark flash, so the player reads the threat, then loses the
; thing, then watches them vanish with it.
;
; Only the mon-stealing villains are wired (7d.1). The Burglar's item theft is
; 7d.2, and until it exists STAGE_EVENT_MAX_ROLLABLE keeps him out of the roll
; rather than letting him appear and take nothing.
;
; THREE GUARDS, in order, each of which can leave STOLEN_NOTHING behind:
;   1. party size < 2 - never leave the player with an empty party
;   2. every eligible mon is FUSED - see below
;   3. (implicit) the event type does not steal at all
; A failed theft is not an error state: the villain still speaks, vanishes and
; can be fought; there is simply nothing to hand back. 7e reads sStolenKind and
; gives back only what was actually taken.
;
; WHY FUSED MONS ARE EXCLUDED, and why it is exclusion rather than fidelity. A
; fusion's identity is NOT in its struct. The struct carries only bit 1 of
; MON_CATCH_RATE; the secondary species and form live in global, one-per-run
; saved WRAM (wFusionSecondarySpecies / wFusionSecondaryForm). Copying the
; struct would therefore capture a fusion BIT whose partner data is global
; state - and for the Psychic, whose team is rebuilt from this record in 7e,
; that means an ENEMY mon pulling the player's global secondary through
; CacheFusionSecondaryBaseStats. Re-rolling past them removes the whole
; state-aliasing class for a few bytes.
;
; Clobbers a/bc/de/hl.
; ============================================================
StageEventDoTheft::
	call StageEventClearStolenRecord
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	cp STAGE_EVENT_BURGLAR
	jr z, .stealItem              ; the Burglar goes straight for the bag
	cp STAGE_EVENT_JESSIE_JAMES
	jr z, .stealMon
	cp STAGE_EVENT_PSYCHIC
	ret nz                        ; the good NPCs take nothing, by design
.stealMon
	call StageEventStealMon       ; carry set = a mon was taken
	ret c
	; FALL THROUGH, and this is the point of the chain: a mon thief who cannot
	; find an eligible victim settles for an item rather than leaving
	; empty-handed. Only when the bag is ALSO empty does nothing get stolen,
	; which needs a one-mon (or all-fused) party AND not a single Recovery,
	; Stat or Valuable item - rare enough to be a curiosity, but it is a
	; defined outcome rather than an unhandled one.
.stealItem
	jp StageEventStealItem

; OUTPUT: carry SET = a mon was stolen and recorded.
; Clobbers a/bc/de/hl.
StageEventStealMon:
	ld a, [wPartyCount]
	cp 2
	jr nc, .partyBigEnough
	; One mon left: never empty the party. Carry must be CLEARED before
	; returning - `cp 2` on a party of 1 SETS it, and a bare `ret c` here
	; returned "success" to the caller, which then skipped the item fallback
	; entirely. Caught by audit_cave_stage_theft.py --force-party 1
	; --expect-item; the earlier no-fallback build hid it, because "party of
	; 1 steals nothing" was then the intended outcome.
	and a
	ret
.partyBigEnough
	; --- pass 1: how many slots are eligible? ---
	ld b, 0                       ; b = eligible count
	ld c, 0                       ; c = slot iterator
.countLoop
	ld a, [wPartyCount]
	cp c
	jr z, .countDone
	call StageEventSlotEligible   ; carry = eligible; preserves bc
	jr nc, .countSkip
	inc b
.countSkip
	inc c
	jr .countLoop
.countDone
	ld a, b
	and a
	ret z                         ; every mon is fused - carry clear, so the
	                              ; caller falls back to an item
	; --- pick the k-th eligible slot ---
	ld c, b                       ; c = population for Rangerandom
	call Rangerandom              ; a = [0, eligible-1]; preserves bc
	ld b, a                       ; b = target index among the eligible
	                              ; NOT d: StageEventSlotEligible needs de for
	                              ; IsFusionMon's struct pointer and clobbers it
	ld c, 0
.pickLoop
	call StageEventSlotEligible
	jr nc, .pickSkip
	ld a, b
	and a
	jr z, .found
	dec b
.pickSkip
	inc c
	jr .pickLoop
.found
	; c = victim slot (0-based)
	call StageEventCopyMonToRecord
	ld a, c
	ldh [hWhichPokemon], a
	xor a
	ld [wRemoveMonFromBox], a     ; 0 = party, not the current box
	; RemovePokemon ALREADY does the bridge bookkeeping: _RemovePokemon
	; farcalls BridgeTrackRemovePokemon on BOTH of its exit paths
	; (engine/pokemon/remove_mon.asm:46 and :112). The plan's instruction to
	; call it again here would have double-applied the sparse-owner shift.
	call RemovePokemon
	scf                           ; a mon was taken; no item fallback needed
	ret

; ============================================================
; StageEventStealItem  (Phase 7d)
; Takes one unit of a random owned item and records it. Reached either
; directly (the Burglar) or as the fallback when a mon theft is refused.
;
; POCKETS: Recovery, Stat and Valuable. Key Items are excluded because the
; plan says so and because losing one would be unrecoverable in a way an
; ordinary item is not. The TM pocket is excluded for a mechanical reason
; rather than a design one: TMs live in sTMBitfield, not in a count array, so
; RemovePocketItem cannot remove one. Adding them needs a second removal path,
; which is not worth it while three pockets already make an empty bag
; vanishingly unlikely.
;
; POKE_FLUTE is skipped in both passes. RemovePocketItem refuses to decrement
; it (`cp POKE_FLUTE / ret z`, it is an infinite-use item), so "stealing" it
; would record a loss that never happened and hand the player a duplicate on
; recovery.
;
; Two passes rather than a reservoir sample: count the owned stacks, roll an
; index, then walk again to resolve it. That keeps the pick uniform over
; STACKS (not over quantity) with no scratch memory at all - everything lives
; in registers, which matters because this runs from a map script with no
; buffer it can safely claim.
;
; OUTPUT: carry SET = an item was taken. Clobbers a/bc/de/hl.
; ============================================================
StageEventStealItem:
	ld b, 0                       ; b = owned stack count
	ld hl, RecoveryItemTable
	ld de, wRecoveryItemCounts
	call StageEventCountPocket
	ld hl, StatItemTable
	ld de, wStatItemCounts
	call StageEventCountPocket
	ld hl, ValuableItemTable
	ld de, wValuableItemCounts
	call StageEventCountPocket
	ld a, b
	and a
	ret z                         ; empty bag AND no stealable mon: the
	                              ; near-impossible nothing-stolen case
	ld c, b
	call Rangerandom              ; a = [0, stacks-1]; preserves bc
	ld b, a                       ; b = target stack index
	ld hl, RecoveryItemTable
	ld de, wRecoveryItemCounts
	call StageEventPickPocket
	jr c, .got
	ld hl, StatItemTable
	ld de, wStatItemCounts
	call StageEventPickPocket
	jr c, .got
	ld hl, ValuableItemTable
	ld de, wValuableItemCounts
	call StageEventPickPocket
	ret nc                        ; defensive: pass 1 promised one exists
.got
	; ⚠ wCurItem IS wCurPartySpecies - one byte, several labels. Writing it
	; here destroys any live species value. Safe at this call site: this runs
	; from the overworld map script after the arrival text, where no species
	; is in flight, and every encounter path sets wCurPartySpecies fresh. Do
	; not move this into a battle or creation path without re-checking that.
	ld a, c
	ld [wCurItem], a
	ld a, 1
	ld [wItemQuantity], a
	push bc
	call StageEventRecordItem     ; record BEFORE removing, so a half-done
	pop bc                        ; removal can never leave an untagged record
	call RemovePocketItem
	scf
	ret

; Walk one pocket, adding its owned, stealable stacks to b.
; INPUT: hl = $ff-terminated item table, de = parallel count array.
; Preserves b. Clobbers a/c/de/hl.
StageEventCountPocket:
.loop
	ld a, [hli]
	cp $ff
	ret z
	ld c, a                       ; c = this entry's item id
	ld a, [de]
	inc de
	and a
	jr z, .loop                   ; none owned
	ld a, c
	cp POKE_FLUTE
	jr z, .loop                   ; infinite-use, cannot be removed
	inc b
	jr .loop

; Resolve the b-th owned stack within one pocket, decrementing b past the
; stacks this pocket holds if it is not here.
; INPUT: hl = item table, de = count array, b = remaining target index.
; OUTPUT: carry SET = found, c = item id. Carry clear = not in this pocket.
; Clobbers a/de/hl.
StageEventPickPocket:
.loop
	ld a, [hli]
	cp $ff
	jr z, .notHere
	ld c, a
	ld a, [de]
	inc de
	and a
	jr z, .loop
	ld a, c
	cp POKE_FLUTE
	jr z, .loop
	ld a, b
	and a
	jr z, .found
	dec b
	jr .loop
.found
	scf
	ret
.notHere
	and a
	ret

; INPUT: c = item id. Tags the record as an item theft.
; Clobbers a.
StageEventRecordItem:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld a, c
	ld [sStolenItem], a
	ld a, STOLEN_ITEM
	ld [sStolenKind], a           ; tag last, as with the mon record
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; INPUT:  c = party slot index (0-based).
; OUTPUT: carry SET = this mon may be stolen (it is not a fusion).
; Preserves bc. Clobbers a/de/hl.
;
; bc is pushed around the farcall because Bankswitch destroys a/b/c/h/l on BOTH
; sides - only d/e and the flags survive. Both callers keep their loop counter
; and iterator in b and c, so without this the very first eligibility test
; would corrupt the loop it is driving.
StageEventSlotEligible:
	push bc
	ld a, c
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes                ; hl = this slot's struct base (a=0 safe:
	                              ; AddNTimes early-returns on zero)
	ld d, h
	ld e, l                       ; de = struct base, IsFusionMon's input
	farcall IsFusionMon           ; Z set = NOT a fusion
	pop bc                        ; does not disturb the flags
	jr z, .eligible
	and a                         ; carry clear = fused, skip this slot
	ret
.eligible
	scf
	ret

; INPUT: c = party slot index. Copies that mon into the SRAM theft record at
; full fidelity and tags it STOLEN_MON.
;
; Three flat copies are all "full fidelity" needs here. The plan pointed at
; SendNewMonToBox as the canonical copy, but that routine INSERTS a new mon
; into a box, shifting the whole box and rebuilding from wCurPartySpecies - it
; is not a copy helper, and its wFormContext publishes matter when REBUILDING
; a mon (7e), not when reading one out. The box portion of the party struct
; already contains the species, DVs, stat exp, moves, PP, OT ID and the
; catch-rate byte that carries form/fusion/shiny, so a memcpy loses nothing.
; The party-only tail (level and the five computed stats) is deliberately not
; copied: 7e recalculates those from the struct, which is what every other
; creation path does.
; Clobbers a/de/hl. Preserves bc.
StageEventCopyMonToRecord:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)     ; bank 1 - NOT bank 0, where the rest of the
	ld [rRAMB], a                 ; stage-event SRAM lives
	push bc
	ld a, c
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld de, sStolenBoxMon
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	pop bc
	push bc
	ld a, c
	ld hl, wPartyMonNicks
	ld bc, NAME_LENGTH
	call AddNTimes
	ld de, sStolenNickname
	ld bc, NAME_LENGTH
	call CopyData
	pop bc
	push bc
	ld a, c
	ld hl, wPartyMonOT
	ld bc, NAME_LENGTH
	call AddNTimes
	ld de, sStolenOTName
	ld bc, NAME_LENGTH
	call CopyData
	pop bc
	ld a, STOLEN_MON
	ld [sStolenKind], a           ; written LAST: the tag is the validity flag,
	                              ; so it must not claim a record that is only
	                              ; half copied
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; Zeroes the theft record's tag. Called at the top of every theft and from the
; lobby-time reset, so a record can never outlive the visit that created it.
; Clobbers a.
StageEventClearStolenRecord:
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
; WildAreaPickAndAssign
; INPUT: carry = forced (mandatory single door) / clear = choosable one-of-two.
; Picks a not-yet-offered-this-cycle wild type (resets after all four are offered),
; marks it in wWildAreaState + bumps the saturating count, resolves it to its entry
; map, and writes wLobbyDoor1/2StageMap. wRogueMap (the route _PickNextStage picked)
; stays on the non-wild door in the choosable case.
; Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickAndAssign:
	; preserve the forced flag across the Rangerandom-heavy pick
	push af                       ; bit: carry = forced
	call WildAreaPickType         ; a = chosen type (0-3); updates wWildAreaState
	call WildAreaTypeToMap        ; a = entry map id for that type
	ld b, a                       ; b = wild entry map
	pop af                        ; restore carry = forced
	jr nc, .choosable
	; --- forced: single mandatory door (collapse both doors to the wild map) ---
	ld a, b
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a   ; door1==door2==wild => Lobby_IsDoor2Blocked blocks door 2
	ret
.choosable:
	; --- choosable: wild on a random door, wRogueMap (route) on the other ---
	push bc                       ; save wild map (b)
	ld c, 2
	call Rangerandom              ; a = 0 (door1 = wild) or 1 (door2 = wild)
	pop bc
	and a
	jr nz, .wildDoor2
	ld a, b
	ld [wLobbyDoor1StageMap], a
	ld a, [wRogueMap]
	ld [wLobbyDoor2StageMap], a
	ret
.wildDoor2:
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld a, b
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; WildAreaPickType
; Picks a random wild type whose "offered this cycle" bit is clear; if all four are
; already set, resets the cycle mask first (keeping the count bits). Sets the chosen
; type's bit and increments the saturating count (bits 3-4, cap 3).
; OUTPUT: a = chosen type (0-3). Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickType:
	ld a, [wWildAreaState]
	ld d, a                       ; d = working state (mask + count); accumulator
	and WILD_AREA_MASK
	cp WILD_AREA_MASK
	jr nz, .haveRoom
	; all four offered this cycle -> clear their noncontiguous mask, keep count bits
	ld a, d
	and WILD_AREA_COUNT_MASK
	ld d, a
.haveRoom:
	; --- pass 1: count unoffered types ---
	ld b, 0                       ; b = unoffered count
	ld c, 0                       ; c = type iterator
.cntLoop:
	ld a, c
	cp NUM_WILD_AREA_TYPES
	jr z, .cntDone
	ld a, c
	call WildAreaMaskForType      ; a = mask for type c (preserves b/c/d/e)
	and d                         ; offered?
	jr nz, .cntSkip
	inc b
.cntSkip:
	inc c
	jr .cntLoop
.cntDone:
	; --- pick the k-th unoffered (b = unoffered count, guaranteed >=1) ---
	ld c, b
	push de                       ; protect working state (Multiply may clobber d/e)
	call Rangerandom              ; a = [0, unoffered-1]; preserves bc
	pop de
	ld c, a                       ; c = target index among unoffered
	ld b, 0                       ; b = type iterator
.pickLoop:
	ld a, b
	call WildAreaMaskForType      ; a = mask for type b (preserves b/c/d/e)
	ld e, a                       ; e = this type's mask
	and d
	jr nz, .pickSkip              ; already offered -> skip
	ld a, c
	and a
	jr z, .chosen                 ; target reached
	dec c
.pickSkip:
	inc b
	jr .pickLoop
.chosen:
	; b = chosen type, e = its mask. Set bit in d, bump count (cap 3), store.
	ld a, d
	or e
	ld d, a
	and WILD_AREA_COUNT_MASK
	cp WILD_AREA_COUNT_MASK
	jr z, .store                  ; count already 3 -> leave
	ld a, d
	add a, 1 << WILD_AREA_COUNT_SHIFT
	ld d, a
.store:
	ld a, d
	ld [wWildAreaState], a
	ld a, b                       ; return chosen type (0-3)
	ret

; a = wild type (0-3) -> a = its offered-cycle bit mask. Preserves bc/de; clobbers hl.
WildAreaMaskForType:
	push bc
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeBit
	add hl, bc
	ld a, [hl]
	pop bc
	ret

; a = wild type (0-3) -> a = its entry map id (from WildAreaTypeMaps). Preserves de; clobbers bc/hl.
WildAreaTypeToMap:
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeMaps
	add hl, bc
	ld a, [hl]
	ret
