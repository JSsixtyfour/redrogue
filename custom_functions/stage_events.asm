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
	jr nz, .haveSomewhereToHide
	; The CEMETERY resolves its hideout later than the other three. Its floors
	; generate lazily, so at preload - which is when this routine runs - only
	; the FLOOR has been rolled and the cell on it does not exist yet. A
	; pending floor answers this question just as well as a resolved cell, and
	; checking it here keeps "an event with nowhere to hide must not manifest"
	; ONE rule rather than giving the cemetery its own copy of this routine.
	;
	; The floor byte is cemetery-only, so it is cleared back to the sentinel by
	; StageEventClearStagedSprites at every lobby selection. Without that
	; clear a cave with no hideout could pass this gate on a floor left behind
	; by an earlier cemetery run.
	ld a, [sStageEventHideoutFloor]
	cp STAGE_EVENT_NO_HIDEOUT
	ret z
.haveSomewhereToHide
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

StageEventSpriteTable:
	db SPRITE_JESSIE,        SPRITE_JAMES         ; STAGE_EVENT_JESSIE_JAMES
	db SPRITE_YOUNGSTER,     0                    ; STAGE_EVENT_PSYCHIC
	db SPRITE_SUPER_NERD,    0                    ; STAGE_EVENT_BURGLAR
	db SPRITE_NURSE,         0                    ; STAGE_EVENT_JOY
	db SPRITE_OFFICER_JENNY, 0                    ; STAGE_EVENT_JENNY
	;db SPRITE_NURSE,         SPRITE_OFFICER_JENNY ; STAGE_EVENT_BOTH_GOOD
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "StageEventSpriteTable needs a row per type"

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
; ============================================================
; StageEventApplyTrainers  (Phase 7e, team number dynamic since 7f)
; Patches the OPP class and team number of the two NPC object slots from the
; rolled event type, the same mechanism MiniBossApplyStageTrainer uses for a
; mini-boss: wMapSpriteExtraData + (slot-1)*2, two bytes, class then set.
;
; EngageMapTrainer reads that pair fresh at engage time and copies the class
; into wCurOpponent and the set into wTrainerNo, so patching once per map load
; is sufficient and nothing needs to re-run per battle.
;
; The object list's declared class is a placeholder; what it has to get right
; at build time is the TRAINER flag, which comes from declaring the object
; with eight arguments rather than seven.
;
; Called from the cave's finalize, beside the sprite placement. No-ops when no
; event is armed - the objects are invisible and PICTUREID-zeroed then, so the
; stale class in wMapSpriteExtraData is unreachable.
;
; The team number (wTrainerNo) is the SAME round-tier for both slots, computed
; once by StageEventRoundTier rather than read from the table - this is what
; makes the rolled team scale with the round instead of pinning to team 1
; forever. Class differs per slot only for STAGE_EVENT_BOTH_GOOD (Joy in the
; base slot, Jenny in the next one); every other row uses the same class for
; both, which for Jessie & James is exactly the point - talking to either
; starts the identical battle, so the pair reads as one encounter.
;
; INPUT: d = this map's base NPC object slot (6 for Cave/Forest, 10 for
; Facility - Cemetery has no pair and does not call this). The base slot's
; pair gets the table's two class bytes; the base+1 slot is contiguous with
; it in wMapSpriteExtraData, so no second input is needed. Survives the
; StageEventRoundTier call (that routine only touches a/b) and the table
; walk (which uses bc for the row offset, not d/e).
; Clobbers a/bc/hl. Preserves e only incidentally (not a caller contract).
; ============================================================
StageEventApplyTrainers::
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	ret z
	push af
	call StageEventRoundTier      ; a = wTrainerNo (1-9); d (base slot) survives
	ld e, a                       ; e = team number, shared by both slots
	pop af
	dec a                         ; 1-based type -> 0-based row
	add a                         ; 2 bytes per row
	ld c, a
	ld b, 0
	ld hl, StageEventTrainerTable
	add hl, bc
	ld a, [hli]
	ld c, a                       ; c = base slot's class
	ld a, [hl]
	ld b, a                       ; b = base+1 slot's class (0 = unused, harmless)

	push bc
	ld a, d
	dec a
	add a
	ld l, a
	ld h, 0
	ld bc, wMapSpriteExtraData
	add hl, bc                    ; hl -> base slot's (class, team) pair
	pop bc
	ld a, c
	ld [hli], a
	ld a, e
	ld [hli], a                   ; hl now -> base+1 slot's pair
	ld a, b
	ld [hli], a
	ld a, e
	ld [hl], a
	ret

; a = wTrainerNo (1-9), the SAME round-tier stage_event_team_spec
; (data/trainers/party_specs.asm) is keyed on. Duplicates
; GetMiniBossTierPtr's clamp/divide (custom_functions/func_enc_gen.asm) rather
; than reaching it by farcall: that routine returns a pointer into its OWN
; bank's table, which cannot survive the bank restore on the way back out -
; the same reason PFRollMonClass/PCAbs are duplicated rather than shared.
; Clobbers a/b.
StageEventRoundTier:
	ld a, [wBattleCount]
	cp 90
	jr c, .noClamp
	ld a, 89
.noClamp
	ld b, 0
.loop
	cp 10
	jr c, .done
	sub 10
	inc b
	jr .loop
.done
	ld a, b
	inc a                         ; 0-based round -> 1-based wTrainerNo
	ret

; One row per STAGE_EVENT_* type from 1: OPP class for slot 6, then for slot
; 7 (0 = slot 7 unused). STAGE_EVENT_BOTH_GOOD is the only row where the two
; differ - Joy and Jenny are two independent ordinary trainers, not a pair
; sharing one battle the way Jessie & James do.
StageEventTrainerTable:
	db OPP_JESSIE_JAMES,  OPP_JESSIE_JAMES   ; STAGE_EVENT_JESSIE_JAMES
	db OPP_PSYCHIC_TR,    0                  ; STAGE_EVENT_PSYCHIC
	db OPP_BURGLAR,       0                  ; STAGE_EVENT_BURGLAR
	db OPP_NURSE_JOY,     0                  ; STAGE_EVENT_JOY
	db OPP_OFFICER_JENNY, 0                  ; STAGE_EVENT_JENNY
	;db OPP_NURSE_JOY,     OPP_OFFICER_JENNY  ; STAGE_EVENT_BOTH_GOOD
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "StageEventTrainerTable needs a row per type"

; ============================================================
; StageEventSyncPairScreenPos  (2026-09-17)
; Re-derives SPRITESTATEDATA1_YPIXELS/XPIXELS from MAPY/MAPX for the stage
; event's two NPC slots.
;
; WHY THIS HAS TO EXIST. A sprite carries its position twice: MAPY/MAPX in
; StateData2, and YPIXELS/XPIXELS in StateData1. CheckSpriteAvailability
; decides the on-screen window test from the MAP pair but the text-box test
; (GetTileSpriteStandsOn) and TrainerEngage both read the PIXEL pair. The only
; thing that resyncs them in normal play is InitializeSpriteScreenPosition,
; reached from UpdateNPCSprite - but UpdateNPCSprite does `ret c` on an
; invisible sprite BEFORE it gets there, so once the two disagree the sprite
; cannot repair itself.
;
; Every stage-event placement writes MAP coords and never pixels. That is
; harmless on an ordinary map load, where LoadMapHeader has just zeroed the
; sprite state - but NOT after a battle: LoadMapHeader skips the object-list
; load when BIT_BATTLE_OVER_OR_BLACKOUT is set ("battles don't destroy this
; data"), so the pixels still hold wherever the trainer walked to, while
; PCPlaceStageEventNpcs slams the map coords back to the hideout. The sprite
; then reads as offscreen (IMAGEINDEX $ff), which also makes
; DetectCollisionBetweenSprites skip it - the reported "they flicker on and
; off and no longer block you, and the location can change".
;
; INPUT: d = base sprite slot (the pair is d and d+1).
; Clobbers a/b/c/h/l. Preserves d/e - which is why the slot travels in d:
; farcall destroys a/b/c/h/l on BOTH legs.
; ============================================================
StageEventSyncPairScreenPos::
	ld a, d
	call .one
	ld a, d
	inc a
.one
	swap a                          ; slot -> sprite state offset
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ret

; ============================================================
; StageEventGiveBack  (Phase 7e)
; Returns whatever the villain took, once, after they are beaten. Farcalled
; from the cave's map script when a stage-event NPC's beat flag is set and the
; end-battle text has cleared - the same shape the boss join offer uses.
;
; Advances the phase to SETTLED and clears the record's tag whatever happens,
; so this can never fire twice and a half-returned mon cannot be re-returned.
;
; OUTPUT: wStageEventScratch = a STAGE_GIVEBACK_* result for the caller to
; pick text with. a holds the same value, but callers must NOT read it: every
; caller is a map script reaching this by `farcall`, and Bankswitch's return
; leg does `ld a, b` with the caller's ROM bank, so `a` arrives holding the
; BANK NUMBER. That is what the "12 ERROR." box was - $11 indexed 26 bytes
; past the end of a 4-entry text table. See [[project_farcall_home_clobbers_a]].
; Clobbers a/bc/de/hl.
; ============================================================
; ============================================================
; StageEventNameLoot  (2026-09-17)
; Fills wNameBuffer with the name of whatever the villain took, so both the
; arrival line and the recovery line can say it out loud instead of "your
; #MON".
;
; The mon case uses the stored NICKNAME, not the species: that is the name
; the player knows it by, and it is already sitting in SRAM, so it costs a
; copy rather than a GetMonName call.
;
; MUST run while the stolen record still exists. For the arrival that is
; automatic (the theft just happened); for the recovery it is why
; StageEventGiveBack calls this as its very first action, before either of
; its StageEventClearStolenRecord calls.
;
; OUTPUT: a = sStolenKind. Clobbers a/bc/de/hl.
; ============================================================
StageEventNameLoot::
	call StageEventReadStolenKind
	cp STOLEN_MON
	jr z, .mon
	cp STOLEN_ITEM
	jr z, .item
	ret                           ; nothing taken - leave the buffer alone
.item
	call StageEventReadStolenItem
	ld [wNamedObjectIndex], a
	call GetItemName              ; -> wNameBuffer
	ld a, STOLEN_ITEM
	ret
.mon
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld hl, sStolenNickname
	ld de, wNameBuffer
	ld bc, NAME_LENGTH
	call CopyData
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, STOLEN_MON
	ret

; ============================================================
; StageEventPrintLootLine  (2026-09-17)
; The second half of the arrival: the villain names what they just took.
; Farcalled from each map's arrival text handler, after it has printed that
; type's greeting, so the two print as one box sequence.
;
; Silent for the good NPCs and for the empty-handed fallback (one mon left
; and an empty bag) - in both cases nothing was taken and there is nothing to
; announce, and the greeting already stands on its own.
; ============================================================
StageEventPrintLootLine::
	call StageEventNameLoot       ; a = kind, wNameBuffer = its name
	cp STOLEN_MON
	jr z, .mon
	cp STOLEN_ITEM
	jr z, .item
	ret
.mon
	ld hl, StageEventTookMonTexts
	jr .pickByType
.item
	ld hl, StageEventTookItemTexts
.pickByType
	; One line per villain, because "They" only fits Jessie & James. Both
	; tables are indexed by STAGE_EVENT_* type starting at 1 and hold rows
	; for the three THIEVES only - the good NPCs take nothing, so they never
	; reach here, and the guard below keeps a future type from indexing past
	; the end if that ever stops being true.
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	cp STAGE_EVENT_JOY
	ret nc
	dec a                         ; type is 1-based; row is 0-based
	add a, a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp PrintText

StageEventTookMonTexts:
	dw StageEventTookMonJessieJames
	dw StageEventTookMonPsychic
	dw StageEventTookMonBurglar
StageEventTookItemTexts:
	dw StageEventTookItemJessieJames
	dw StageEventTookItemPsychic
	dw StageEventTookItemBurglar

StageEventTookMonJessieJames:
	text_far _StageEventTookMonJessieJamesText
	text_end
StageEventTookMonPsychic:
	text_far _StageEventTookMonPsychicText
	text_end
StageEventTookMonBurglar:
	text_far _StageEventTookMonBurglarText
	text_end
StageEventTookItemJessieJames:
	text_far _StageEventTookItemJessieJamesText
	text_end
StageEventTookItemPsychic:
	text_far _StageEventTookItemPsychicText
	text_end
StageEventTookItemBurglar:
	text_far _StageEventTookItemBurglarText
	text_end

StageEventGiveBack::
	; Name the loot BEFORE anything below can clear the record - both the
	; item and the mon paths call StageEventClearStolenRecord on success, and
	; the recovery text needs the name after that has happened.
	call StageEventNameLoot
	call StageEventReadStolenKind ; a = sStolenKind
	ld b, a
	; Advance the phase FIRST. Every path below ends the event, and doing it
	; up front means an early return cannot leave the event re-triggerable.
	ld a, [wStageEvent]
	and ~STAGE_EVENT_PHASE_MASK & $ff
	or STAGE_EVENT_PHASE_SETTLED << STAGE_EVENT_PHASE_SHIFT
	ld [wStageEvent], a
	ld a, b
	cp STOLEN_ITEM
	jr z, .giveItem
	cp STOLEN_MON
	jr z, .giveMon
	ld a, STAGE_GIVEBACK_NOTHING  ; they never managed to take anything
	jr .done
.giveItem
	call StageEventReadStolenItem ; a = sStolenItem
	ld b, a
	ld c, 1
	; GiveItem routes by id: a TM or HM goes to sTMBitfield via AcquireTMHM, a
	; count-pocket item to its array. One call covers every pocket the theft
	; can draw from, which is why the record needs no separate TM kind.
	call GiveItem
	jr nc, .noRoom
	call StageEventClearStolenRecord
	ld a, STAGE_GIVEBACK_ITEM
	jr .done
.noRoom
	ld a, STAGE_GIVEBACK_NO_ROOM
	jr .done
.giveMon
	; A full party is the one way this can legitimately fail. The theft
	; guaranteed at least 2 mons at the time, so at most 5 remained - but the
	; player can catch or be given one inside the wild area before recovering,
	; and then there is nowhere to put it back.
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	jr nc, .noRoom
	call StageEventRebuildStolenMon
	call StageEventClearStolenRecord
	ld a, STAGE_GIVEBACK_MON
; The store has to be the LAST thing on every path: StageEventRebuildStolenMon
; uses wStageEventScratch as its own scratch, so writing the result any earlier
; would be overwritten by the very path that produces it.
.done
	ld [wStageEventScratch], a
	ret

; OUTPUT: a = sStolenKind. Clobbers a.
StageEventReadStolenKind:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld a, [sStolenKind]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	ret

; OUTPUT: a = sStolenItem. Clobbers a/b.
StageEventReadStolenItem:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld a, [sStolenItem]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	ld a, b
	ret

; ============================================================
; StageEventRebuildStolenMon  (Phase 7e)
; Appends the recorded mon to the party at full fidelity.
;
; WHY NOT AddPartyMon OR GivePokemon: both CREATE a mon from a species and a
; level, rolling fresh DVs and fresh moves. The whole point of the record is
; that the player gets THEIR mon back - same DVs, same stat exp, same moves
; and PP, same OT and nickname, same form. So the box struct is copied in
; verbatim and only the two DERIVED fields are recomputed.
;
; Level and stats are recomputed rather than stored, which is what _MoveMon's
; box-to-party path does for exactly the same reason: experience is the source
; of truth, the party struct's level and five stats are a cache of it, and
; copying a cache is how it goes stale.
;
; The form needs no special handling on the way back either - it rode in on
; MON_CATCH_RATE bits 5-6 inside the struct and is still there.
; Clobbers a/bc/de/hl.
; ============================================================
StageEventRebuildStolenMon:
	; --- grow the party list ---
	ld a, [wPartyCount]
	inc a
	ld [wPartyCount], a
	ld c, a                       ; c = new party length (1-based)
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld [hl], $ff                  ; terminator one past the new entry
	dec hl
	; species comes from the record's first byte
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld a, [sStolenBoxMon]         ; box struct byte 0 = species
	ld [hl], a
	ld [wCurPartySpecies], a
	; --- copy the struct and both names into the new slot ---
	ld a, [wPartyCount]
	dec a                         ; 0-based slot index
	ld [wStageEventScratch], a
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, sStolenBoxMon
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	ld a, [wStageEventScratch]
	ld hl, wPartyMonNicks
	ld bc, NAME_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, sStolenNickname
	ld bc, NAME_LENGTH
	call CopyData
	ld a, [wStageEventScratch]
	ld hl, wPartyMonOT
	ld bc, NAME_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, sStolenOTName
	ld bc, NAME_LENGTH
	call CopyData
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	; --- recompute the two derived fields from experience ---
	ld a, [wStageEventScratch]
	ldh [hWhichPokemon], a
	xor a
	ld [wMonDataLocation], a      ; PLAYER_PARTY_DATA
	call LoadMonData
	farcall CalcLevelFromExperience ; d = level; farcall keeps d/e
	ld a, [wStageEventScratch]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	push de
	call AddNTimes                ; hl = the new mon's struct base
	pop de
	ld bc, BOXMON_STRUCT_LENGTH
	add hl, bc                    ; hl = its Level byte, just past the box part
	ld a, d
	ld [wCurEnemyLevel], a
	; The CalcStats call convention is copied verbatim from _MoveMon's
	; box-to-party tail (engine/pokemon/add_mon.asm), because getting it from
	; the doc comment alone is easy to get wrong: de is the MON_STATS
	; destination but hl is the STAT EXP base, wPartyMon*HPExp - 1, NOT the
	; same pointer. An earlier draft passed MON_STATS in both and would have
	; computed every stat from the wrong bytes.
	ld [hli], a                   ; write level; hl now = MON_STATS
	ld d, h
	ld e, l                       ; de = MON_STATS destination
	ld bc, (MON_HP_EXP - 1) - MON_STATS
	add hl, bc                    ; hl = wPartyMon*HPExp - 1
	ld b, $1                      ; consider stat exp
	; Same wrapper every other recalc site uses. The theft excludes fused mons
	; so the fusion half is moot here, but the bridge-ray half is not, and
	; keeping the sequence identical to the reference is cheaper than
	; reasoning about which half this path needs.
	push de
	push bc
	push hl
	farcall PrepareFusionAndBridgeRayCalcStats
	pop hl
	pop bc
	pop de
	call CalcStats                ; writes the five stats to [de]
	ret

; ============================================================
; StageEventInjectStolenMon  (Phase 7e)
; Puts the mon the Psychic stole onto the Psychic's own team, as its last
; slot, so the player fights their own Pokemon to get it back.
;
; ORDERING IS THE WHOLE TRAP HERE, and it is a known one in this codebase.
; This runs from .FinishUp in read_trainer_party.asm, which is AFTER
; RogueApplyMixToParty (the plan's explicit requirement) and also after the
; SpecialTrainerMoves loop. Both of those rewrite movesets across the enemy
; party, so injecting earlier would have the stolen mon's own four moves
; rolled away - which is the same shape as the GetRandRosterLoop override
; ordering already recorded for the GAMBLER path.
;
; THE LAST SLOT, not the first: it reads as the trainer's ace, and it means
; the injection cannot be masked by a lead that the AI switches out.
;
; Gated four ways, because this writes into a live enemy party and any of
; these being wrong would corrupt an unrelated trainer's team:
;   - the armed event is the Psychic
;   - the trainer being built IS a Psychic (not some other class on the map)
;   - something was actually stolen, and it was a mon
;   - the enemy party is non-empty
; Clobbers a/bc/de/hl.
; ============================================================
StageEventInjectStolenMon::
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	cp STAGE_EVENT_PSYCHIC
	ret nz
	ld a, [wTrainerClass]
	cp PSYCHIC_TR
	ret nz
	call StageEventReadStolenKind
	cp STOLEN_MON
	ret nz
	ld a, [wEnemyPartyCount]
	and a
	ret z
	dec a                         ; 0-based index of the last slot
	ld [wStageEventScratch], a

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	; species also has to go into the parallel list, or the battle engine and
	; the party menu disagree about what this slot holds
	ld a, [wStageEventScratch]
	ld c, a
	ld b, 0
	ld hl, wEnemyPartySpecies
	add hl, bc
	ld a, [sStolenBoxMon]
	ld [hl], a
	ld [wCurPartySpecies], a
	; the struct itself
	ld a, [wStageEventScratch]
	ld hl, wEnemyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, sStolenBoxMon
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	; the nickname, so the player recognises their own mon on the field
	ld a, [wStageEventScratch]
	ld hl, wEnemyMonNicks
	ld bc, NAME_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, sStolenNickname
	ld bc, NAME_LENGTH
	call CopyData
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; Recompute level and stats from experience, exactly as the give-back
	; does - same reason, and the same CalcStats convention (de = MON_STATS
	; destination, hl = the stat-exp base, NOT the same pointer).
	ld a, [wStageEventScratch]
	ldh [hWhichPokemon], a
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	call LoadMonData
	farcall CalcLevelFromExperience ; d = level
	ld a, [wStageEventScratch]
	ld hl, wEnemyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	push de
	call AddNTimes
	pop de
	ld bc, BOXMON_STRUCT_LENGTH
	add hl, bc                    ; hl = this slot's Level byte
	ld a, d
	ld [hli], a                   ; hl now = MON_STATS
	ld d, h
	ld e, l
	ld bc, (MON_HP_EXP - 1) - MON_STATS
	add hl, bc                    ; hl = HPExp - 1
	ld b, $1
	call CalcStats
	ret

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
	; The cemetery's hideout FLOOR belongs to this same reset. It is the only
	; stage-event field a non-cemetery run never writes, so without clearing
	; it here a stale floor from an earlier cemetery would survive into a cave
	; or forest run and wrongly satisfy StageEventStageSprites' hideout gate.
	ld a, STAGE_EVENT_NO_HIDEOUT
	ld [sStageEventHideoutFloor], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	; Phase 7d: the theft record is the other half of this lobby-time reset,
	; so a robbery can never outlive the visit that produced it. It gets its
	; own SRAM window rather than sharing this one, because it lives in a
	; DIFFERENT bank (1, "Save Data") from the sprites above (0).
	jp StageEventClearStolenRecord
