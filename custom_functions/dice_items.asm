; custom_functions/dice_items.asm
;
; DOOR_DICE / MON_DICE / ITEM_DICE (see KEY_ITEM_EFFECTS_PLAN_PC.md §3f-3h).
; wDiceCharges packs 2 bits per die (bits 0-1 DOOR, 2-3 MON, 4-5 ITEM),
; refilled by RogueOnBlackout (custom_functions/credit_popup.asm) and by
; InitDiceChargeOnFirstPurchase (engine/events/credit_mart.asm) on first buy.
;
; Lives in the "rogue" bank (not engine/items/item_effects.asm, "bank3")
; because every reroll action these items trigger - SelectAndPatchLobbyExit,
; rogue_pokemon_randomized_batch, Random_Item_Selection, IsRogueStageMap -
; already lives here; keeping the logic in bank3 would need a farcall out to
; reach any of them anyway, and bank3 had no room left for it (moving this
; here is what fixed a "bank3 grew too big" link error - see
; project_rom0_home_pressure). item_effects.asm keeps only a 2-instruction
; farcall stub per item.
;
; The ITEM_DICE ball-collected check reads wToggleableObjectFlags directly
; rather than calling ToggleableObjectFlagAction (bank3): that routine takes
; its flag-array pointer in hl, and farcall's own macro expansion (ld hl,
; \1 / call Bankswitch) overwrites hl with the CALLEE's address before the
; routine ever runs, destroying any hl the caller tried to preload - the
; same landmine IsGhostVariant's header documents for farcall generally.
; wToggleableObjectFlags is a plain flag_array (same bit-per-index scheme as
; the generic FlagAction it's "identical to" per its own comment), so the
; byte/bit split is just compile-time constant arithmetic - no call needed.

DiceOutOfChargesText:
	text_far _DiceOutOfChargesText
	text_end

RogueItemUseDoorDice::
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .refuseLocation
	ld a, [wDiceCharges]
	and %00000011
	jr z, .refuseCharges
	dec a
	ld b, a
	ld a, [wDiceCharges]
	and %11111100
	or b
	ld [wDiceCharges], a
; SelectAndPatchLobbyExit patches THIS map's warp entries at fixed
; coordinates (11,7)/(11,8) - calling it from any other map would corrupt
; that map's warp table, which is exactly why the map gate above runs first.
;
; KNOWN GAP: unlike the normal lobby-entry path (IndigoPlateauLobby_Script,
; which farcalls ProcPreloadAssignedWildArea right after this same call), a
; reroll here does NOT re-preload. If the reroll lands a door on a wild area,
; PCFinalizeCave/PFinalizeForest/etc. run against whatever cave/forest was
; already staged from the PREVIOUS assignment (or nothing, on a fresh save) -
; not a crash (regenerates the last-rolled layout instead of the new door's
; intended fresh one), but not a true fresh generation either. Not fixed:
; a farcall ProcPreloadAssignedWildArea here would add a ~0.5s hitch right
; after this reroll's text box. See Red Rogue Files/PROC_GEN_NOTES.md.
	call SelectAndPatchLobbyExit
	ld hl, DoorDiceRerolledText
	call PrintText
	ret
.refuseLocation
	ld hl, DoorDiceRefuseText
	call PrintText
	ret
.refuseCharges
	ld hl, DiceOutOfChargesText
	call PrintText
	ret

DoorDiceRerolledText:
	text_far _DoorDiceRerolledText
	text_end

DoorDiceRefuseText:
	text_far _DoorDiceRefuseText
	text_end

RogueItemUseMonDice::
	ldh a, [hCurMap]
	cp REWARD_ROOM
	jr nz, .refuseLocation
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr nz, .refuseLocation         ; already claimed - nothing to reroll
	ld a, [wDiceCharges]
	and %00001100
	jr z, .refuseCharges
	srl a
	srl a                          ; a = charge value (1-3)
	dec a
	sla a
	sla a                          ; shift back into bits 2-3
	ld b, a
	ld a, [wDiceCharges]
	and %11110011
	or b
	ld [wDiceCharges], a
	call rogue_pokemon_randomized_batch
	ld hl, MonDiceRerolledText
	call PrintText
	ret
.refuseLocation
	ld hl, MonDiceRefuseText
	call PrintText
	ret
.refuseCharges
	ld hl, DiceOutOfChargesText
	call PrintText
	ret

MonDiceRerolledText:
	text_far _MonDiceRerolledText
	text_end

MonDiceRefuseText:
	text_far _MonDiceRefuseText
	text_end

RogueItemUseItemDice::
	call IsRogueStageMap           ; Z clear = a standard route/gym stage
	jr z, .refuseLocation
; Scope limit (v1): procedural stages (cave/forest/cemetery/wild areas) stage
; their ball contents in SRAM, not wRogueItem alone - IsRogueStageMap already
; excludes those maps (they're not in RogueStageMapTable), so this handler
; never reaches them.
	ld a, [wToggleableObjectFlags + (TOGGLE_STAGE_RANDOM_ITEM / 8)]
	bit TOGGLE_STAGE_RANDOM_ITEM % 8, a
	jr nz, .refuseLocation         ; already collected - nothing to reroll
	ld a, [wDiceCharges]
	and %00110000
	jr z, .refuseCharges
	swap a                         ; bits 4-5, nibble-aligned -> a = charge value (1-3)
	dec a
	swap a                         ; shift back into bits 4-5
	ld b, a
	ld a, [wDiceCharges]
	and %11001111
	or b
	ld [wDiceCharges], a
	farcall Random_Item_Selection     ; re-rolls wRogueItem using wRogueDoorSelection
	ld hl, ItemDiceRerolledText
	call PrintText
	ret
.refuseLocation
	ld hl, ItemDiceRefuseText
	call PrintText
	ret
.refuseCharges
	ld hl, DiceOutOfChargesText
	call PrintText
	ret

ItemDiceRerolledText:
	text_far _ItemDiceRerolledText
	text_end

ItemDiceRefuseText:
	text_far _ItemDiceRefuseText
	text_end
