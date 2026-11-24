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
	call DoorDiceBargainWarning ; any accepted bargain: YES breaks it
	ret nc                      ; NO: no charge spent
	ld a, [wDiceCharges]
	and %00000011
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
; RESOLVED 2026-09-16: like the normal lobby-entry path (IndigoPlateauLobby_Script,
; which farcalls ProcPreloadAssignedWildArea right after its own SelectAndPatchLobbyExit),
; a reroll now re-preloads too. Decision: the ~0.5s hitch mid-reroll is accepted rather
; than staging the preload behind the text box - a rerolled door landing on a wild area
; must show the door's OWN fresh layout/boss, not whatever cave/forest was staged for
; the PREVIOUS assignment (or nothing, on a fresh save).
;
; farcall, not call: procedural_stage_hooks.asm opens its own SECTION "ProcStageHooks",
; so despite being INCLUDEd under "rogue" in main.asm it floats to another bank. This
; used to be a plain call on the belief the two shared a SECTION, and it jumped into
; whatever was mapped at that address in this bank (fixed 2026-09-24).
	; On a gym cycle the reroll forgets a reveal and rolls new gyms: a two-door
	; lobby gets a fresh pair; a single-door one (a back-to-back pair's lobby, or
	; the last gym) stays single, so a reroll never adds a door (2026-10-10).
	ld a, [wGymChoice]
	bit BIT_GYM_CHOICE_LATCHED, a
	jr z, .rollDoors            ; a route visit: nothing latched
	ld c, a
	and GYM_CHOICE_DOOR1_MASK
	ld b, a
	ld a, c
	and GYM_CHOICE_DOOR2_MASK
	rrca
	rrca
	rrca
	ASSERT GYM_CHOICE_DOOR2_SHIFT == 3
	cp b
	ld a, 0                     ; (keeps the flags) forget the old choice
	ld [wGymChoice], a
	jr nz, .rollDoors           ; two doors: SelectAndPatchLobbyExit latches a pair
	call RogueLatchGymChoice    ; one door: roll, then keep only door 1's gym
	ld a, [wGymChoice]
	and ~GYM_CHOICE_DOOR2_MASK
	ld c, a
	and GYM_CHOICE_DOOR1_MASK
	add a
	add a
	add a
	or c
	ld [wGymChoice], a
.rollDoors
	call SelectAndPatchLobbyExit
	farcall ProcPreloadAssignedWildArea
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
	cp FIGHTING_DOJO
	jr z, .dojo
	cp REWARD_ROOM
	jr z, .standard
	cp GAME_CORNER
	jr z, .standard
	call IsRogueStageMap
	jr nz, .standard
	ldh a, [hCurMap]
	cp OAKS_LAB
	jr nz, .refuseLocation
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	jr z, .refuseLocation
	CheckEvent EVENT_GOT_STARTER
	jr .normalBatch
.dojo
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr nz, .refuseLocation
	CheckEvent EVENT_DEFEATED_FIGHTING_DOJO
	ld e, 1
	jr .checkClaim
.standard
	CheckEvent EVENT_GOT_ROGUE_POKEMON
.normalBatch
	ld e, 0
.checkClaim
	jr nz, .refuseLocation
	ld a, [wDiceCharges]
	and %00001100
	jr z, .refuseCharges
	ld a, [wDiceCharges]
	sub %00000100                  ; nonzero field: no borrow into adjacent charges
	ld [wDiceCharges], a
	dec e
	jr z, .rollDojo
	call rogue_pokemon_randomized_batch
	ldh a, [hCurMap]
	cp OAKS_LAB
	jr z, .rolled
	; Swap the first ball and trader only if that reward is already visible.
	; SS Anne keeps both hidden until its trainers have been defeated.
	ASSERT TOGGLE_ROGUE_REWARD_POKEBALL_1 / 8 == TOGGLE_ROGUE_TRADE_NPC / 8
	ld hl, wToggleableObjectFlags + TOGGLE_ROGUE_TRADE_NPC / 8
	bit TOGGLE_ROGUE_REWARD_POKEBALL_1 % 8, [hl]
	jr z, .syncFirst
	bit TOGGLE_ROGUE_TRADE_NPC % 8, [hl]
	jr nz, .rolled
.syncFirst
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	set TOGGLE_ROGUE_TRADE_NPC % 8, [hl]
	res TOGGLE_ROGUE_REWARD_POKEBALL_1 % 8, [hl]
	jr z, .rolled
	res TOGGLE_ROGUE_TRADE_NPC % 8, [hl]
	set TOGGLE_ROGUE_REWARD_POKEBALL_1 % 8, [hl]
	jr .rolled
.rollDojo
	farcall FightingDojoRerollRewards
.rolled
	ld hl, MonDiceRerolledText
	jp PrintText
.refuseLocation
	ld hl, MonDiceRefuseText
	jp PrintText
.refuseCharges
	ld hl, DiceOutOfChargesText
	jp PrintText

MonDiceRerolledText:
	text_far _MonDiceRerolledText
	text_end

MonDiceRefuseText:
	text_far _MonDiceRefuseText
	text_end

RogueItemUseItemDice::
	call IsRogueStageMap           ; Z clear = a standard route/gym stage
	jr z, .tryBridge
; Scope limit (v1): procedural stages (cave/forest/cemetery/wild areas) stage
; their ball contents in SRAM, not wRogueItem alone - IsRogueStageMap already
; excludes those maps (they're not in RogueStageMapTable), so this handler
; never reaches them.
	ld a, [wToggleableObjectFlags + (TOGGLE_STAGE_RANDOM_ITEM / 8)]
	bit TOGGLE_STAGE_RANDOM_ITEM % 8, a
	jr nz, .refuseLocation         ; already collected - nothing to reroll
	ld e, 0
	jr .charge
.tryBridge
	ldh a, [hCurMap]
	cp OAKS_LAB
	jr z, .checkEntrance
	cp REDS_HOUSE_1F
	jr nz, .findGiver
.checkEntrance
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .refuseLocation
.findGiver
	ld hl, BridgeRoomMaps
	ld b, NUM_BRIDGE_ROOMS
	ldh a, [hCurMap]
.findBridge
	cp [hl]
	jr z, .bridge
	inc hl
	dec b
	jr nz, .findBridge
	jr .refuseLocation
.bridge
	CheckEvent EVENT_BRIDGE_RECEIVE_GIFT
	jr nz, .refuseLocation
	ld e, 1
.charge
	ld a, [wDiceCharges]
	and %00110000
	jr z, .refuseCharges
	ld a, [wDiceCharges]
	sub %00010000
	ld [wDiceCharges], a
	dec e
	jr nz, .stageItem
	farcall rogue_gift_randomized_batch
	ld hl, MonDiceRerolledText ; "Choices rerolled!"
	jp PrintText
.stageItem
	farcall Random_Item_Selection     ; re-rolls wRogueItem using wRogueDoorSelection
	farcall RefreshBallRarityCache    ; recolour the item ball for the new contents
	ld hl, ItemDiceRerolledText
	jp PrintText
.refuseLocation
	ld hl, ItemDiceRefuseText
	jp PrintText
.refuseCharges
	ld hl, DiceOutOfChargesText
	jp PrintText

ItemDiceRerolledText:
	text_far _ItemDiceRerolledText
	text_end

ItemDiceRefuseText:
	text_far _ItemDiceRefuseText
	text_end
