; custom_functions/battle_menu_extras.asm
;
; Battle menu additions: the END option's confirm-and-forfeit, the battle-only
; ITEM list (active key items + POKE FLUTE) with its description box, and the
; ghost-variant entrance fade.
;
; Declares its own SECTION, pinned to ROMX $3A in layout.link. "Battle Core"
; (bank $0F) has almost no free space, so core.asm keeps only thin farcall stubs
; and the logic lives here. Every entry point is reached by farcall, which
; clobbers a/b/c/h/l on the way in: inputs travel in d/e or WRAM, never hl.
;
; Text lives inline in this bank rather than behind text_far: "Rogue" text
; (bank $04, data/text/text_rogue.asm) has 5 bytes free. PrintText reads from
; the active ROM bank, which is this one while these routines run.

; ============================================================
; RogueConfirmEndBattle - the battle menu's END option (BattleMenu_RunWasSelected,
; engine/battle/core.asm). Debug builds never reach this: they keep the old RUN
; path, which auto-wins against trainers and procedural wilds.
;
; OUTPUT: carry set = the player confirmed. The whole party (and wBattleMon) is
;         at 0 HP and wBattleResult = 1, so the caller's jp HandlePlayerBlackOut
;         ends the battle exactly like an all-faint loss, and the overworld's
;         post-battle AnyPartyAlive check (home/overworld.asm) runs the blackout.
;         carry clear = declined or refused; the caller redisplays the menu.
;
; The yes/no box is drawn the way DoUseNextMonDialogue draws its own, NOT through
; YesNoChoice: YesNoChoice snapshots screen buffer 1 on entry, and buffer 1 is
; what DisplayBattleMenu restores - it would bring the prompt back forever.
; ============================================================
RogueConfirmEndBattle::
	; Refused where a forced blackout would go wrong. Link battles have a second
	; Game Boy to keep in step. Oak's Lab is the starter battle, where
	; HandlePlayerBlackOut deliberately skips the blackout, so the player would
	; walk out with a 0-HP party.
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .refuse
	ldh a, [hCurMap]
	cp OAKS_LAB
	jr z, .refuse

	ld hl, .ConfirmText
	call PrintText
	xor a ; YES_NO_MENU
	ld [wTwoOptionMenuID], a
	hlcoord 13, 9
	lb bc, 10, 14
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM ; NO, or B
	jr z, .declined

	; Forfeit: zero every party mon's HP, then the active battle copy.
	ld a, [wPartyCount]
	ld b, a
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH - 1
.zeroLoop
	xor a
	ld [hli], a
	ld [hl], a
	add hl, de
	dec b
	jr nz, .zeroLoop
	xor a
	ld hl, wBattleMonHP
	ld [hli], a
	ld [hl], a
	ld a, 1
	ld [wBattleResult], a
	scf
	ret

.refuse
	ld hl, .RefuseText
	call PrintText
.declined
	and a
	ret

.ConfirmText:
	text "Give up and end"
	line "this run?"
	done

.RefuseText:
	text "You can't end"
	line "this battle!"
	prompt

; ============================================================
; BuildBattleItemList - the battle menu's ITEM list (DisplayPlayerBag,
; engine/battle/core.asm, which is only reached in a normal battle). The list is
; the ACTIVE key items plus POKE FLUTE when owned, in wKeyItemPocketBuf's usual
; format: count, {item, qty} pairs, $FF.
;
; Also sets BIT_BATTLE_ITEM_LIST, which routes PrintBagInfoText's cursor-move
; hook to PrintBattleItemInfo below and makes PocketSwitchROMX refuse LEFT/RIGHT.
; DisplayBagMenu clears it again on the way out.
;
; The scroll offset and saved cursor are reset because both are shared with the
; field bag, whose pockets can be far longer than this list.
; ============================================================
; POKE FLUTE's slot in wRecoveryItemCounts: it is the last entry of
; RecoveryItemTable (custom_functions/pocket_items.asm). Read directly rather than
; through GetPocketItemCount, whose result comes back in a, and a does not survive
; farcall's return trip through Bankswitch.
DEF POKE_FLUTE_RECOVERY_SLOT EQU NUM_RECOVERY_ITEMS - 1

BuildBattleItemList::
	farcall BuildKeyItemPocketList
	ld a, [wRecoveryItemCounts + POKE_FLUTE_RECOVERY_SLOT]
	and a
	jr z, .noFlute
	ld hl, wKeyItemPocketBuf
	ld a, [hl]
	inc [hl]                   ; one more entry
	add a                      ; 2 bytes per entry
	inc a                      ; skip the count byte
	ld e, a
	ld d, 0
	add hl, de                 ; hl = the $FF that ended the key item list
	ld a, POKE_FLUTE
	ld [hli], a
	ld a, 1
	ld [hli], a
	ld [hl], $FF
.noFlute
	xor a
	ld [wListScrollOffset], a
	ld [wBagSavedMenuItem], a
	ld hl, wBagPocketsFlags
	set BIT_BATTLE_ITEM_LIST, [hl]
	ret

; ============================================================
; PrintBattleItemInfo - the battle ITEM list's description box, redrawn on
; every cursor move (PrintBagInfoText, custom_functions/tm_bag.asm, hands off
; here while BIT_BATTLE_ITEM_LIST is set). Two lines of description, then a
; third with the item's remaining uses, dice charges or upgrade tier.
; The box is taller and wider than the field bag's one-line BAG_INFO_BOX, which it
; covers: rows 13-17 are the battle text box, idle while the list is open, and a
; full-width line is needed because '#' alone expands to four tiles (POKe).
; ============================================================
PrintBattleItemInfo::
	hlcoord 0, 13
	lb bc, 3, SCREEN_WIDTH - 2
	call TextBoxBorder
	; highlighted entry (GetCurrentMenuItem's logic; that copy lives in the
	; rogue bank and returns in a, which farcall would lose)
	ld a, [wListScrollOffset]
	ld c, a
	ldh a, [hCurrentMenuItem]
	add c
	add a                      ; item entries are 2 bytes
	ld c, a
	ld b, 0
	ld hl, wListPointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	inc hl                     ; skip the count byte
	add hl, bc
	ld a, [hl]
	cp $FF
	ret z                      ; CANCEL: leave the box empty
	ld [wCurItem], a
	ld d, a
	ld hl, BattleItemInfoTable
.find
	ld a, [hli]
	cp $FF
	ret z                      ; not described: leave the box empty
	cp d
	jr z, .found
	inc hl
	inc hl
	inc hl
	jr .find
.found
	ld e, [hl]                 ; e = INFO_* kind of the third line
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	push de
	ld d, h
	ld e, l
	hlcoord 1, 14
	call PlaceString           ; leaves de on the first line's '@'
	inc de
	hlcoord 1, 15
	call PlaceString
	pop de
	ld a, e
	and a                      ; INFO_NONE
	ret z
	dec a                      ; INFO_TIER
	jr z, .tier
	dec a                      ; INFO_KO_USES
	jr z, .koUses
	; INFO_DOOR_DICE / _MON_DICE / _ITEM_DICE leave a = 1 / 2 / 3: each die owns
	; 2 bits of wDiceCharges, DOOR lowest (custom_functions/dice_items.asm)
	ld b, a
	ld a, [wDiceCharges]
.diceShift
	dec b
	jr z, .gotDice
	rrca
	rrca
	jr .diceShift
.gotDice
	and %11
	ld de, .ChargesLabel
	jr .printCount
.koUses
	ld a, [wKODefianceUsages]
	ld de, .UsesLabel
	jr .printCount
.tier
	farcall GetKeyItemTierInE  ; reads wCurItem, set above
	ld a, e
	inc a                      ; displayed TIER 1-3, as the field bag shows it
	ld de, .TierLabel
.printCount
	push af
	hlcoord 1, 16
	call PlaceString           ; bc = the tile after the label
	pop af
	add '0'
	ld [bc], a
	ret

.TierLabel:
	db "TIER @"
.UsesLabel:
	db "USES LEFT: @"
.ChargesLabel:
	db "CHARGES: @"

	const_def
	const INFO_NONE
	const INFO_TIER
	const INFO_KO_USES
	const INFO_DOOR_DICE       ; the three dice must stay in this order and last
	const INFO_MON_DICE
	const INFO_ITEM_DICE

; item, INFO_* kind, two description lines (18 tiles each at most)
MACRO battle_item_info
	db \1, \2
	dw \3
ENDM

BattleItemInfoTable:
	battle_item_info LEFTOVERS,     INFO_TIER,      .Leftovers
	battle_item_info PP_TONIC,      INFO_TIER,      .PPTonic
	battle_item_info KO_DEFIANCE,   INFO_KO_USES,   .KODefiance
	battle_item_info EXP_ALL,       INFO_TIER,      .ExpAll
	battle_item_info SHINY_CHARM,   INFO_TIER,      .ShinyCharm
	battle_item_info AMULET_COIN,   INFO_TIER,      .AmuletCoin
	battle_item_info TURN_REWIND,   INFO_NONE,      .TurnRewind
	battle_item_info RARE_SCOPE,    INFO_TIER,      .RareScope
	battle_item_info RARE_LENS,     INFO_TIER,      .RareLens
	battle_item_info DV_BOOSTER,    INFO_TIER,      .DVBooster
	battle_item_info STAT_BOOSTER,  INFO_TIER,      .StatBooster
	battle_item_info DOOR_DICE,     INFO_DOOR_DICE, .DoorDice
	battle_item_info MON_DICE,      INFO_MON_DICE,  .MonDice
	battle_item_info ITEM_DICE,     INFO_ITEM_DICE, .ItemDice
	battle_item_info ELEMENT_PRISM, INFO_TIER,      .ElementPrism
	battle_item_info POKE_FLUTE,    INFO_NONE,      .PokeFlute
	db $FF

.Leftovers:    db "Heals party@",    "after battles@"
.PPTonic:      db "Restores PP@",    "after battles@"
.KODefiance:   db "Revives last@",   "mon on a KO@"
.ExpAll:       db "Whole party@",    "shares EXP@"
.ShinyCharm:   db "Ups the odds@",   "of shinies@"
.AmuletCoin:   db "More money@",     "from battles@"
.TurnRewind:   db "Undo last turn@", "No turn used@"
.RareScope:    db "Rarer wild@",     "#MON appear@"
.RareLens:     db "Rarer items@",    "are found@"
.DVBooster:    db "Caught #MON@",    "get better DVs@"
.StatBooster:  db "More stat EXP@",  "from battles@"
.DoorDice:     db "Rerolls lobby@",  "doors@"
.MonDice:      db "Rerolls the@",    "reward #MON@"
.ItemDice:     db "Rerolls stage@",  "items@"
.ElementPrism: db "Powers moves@",   "of its type@"
.PokeFlute:    db "Wakes all #MON@", "Takes a turn@"

; ============================================================
; BattleKeyItemGate - top of UseItem_ (engine/items/item_effects.asm), before
; the item dispatch. In a normal battle, a key item never takes the turn:
; wActionResultOrTookBattleTurn is zeroed, so UseBagItem (core.asm) goes back
; to the ITEM list rather than on to the enemy's move.
;   TURN REWIND  restores last turn's snapshot here (the battle menu's old UNDO slot).
;   Dice         refused: rerolling a stage's item mid-battle would really fire.
;   Others       "<ITEM> is always active!". Their own handlers print the field
;                description, but it ends in `done`, not `prompt`, so in battle
;                it would vanish at once; the list's box already describes them.
; POKE FLUTE is not a key pocket item, so it keeps the vanilla path and its turn cost.
;
; OUTPUT: carry set = handled here, UseItem_ returns at once.
;         carry clear = continue into UseItem_'s normal dispatch.
; ============================================================
BattleKeyItemGate::
	ldh a, [hIsInBattle]
	and a                      ; clears carry
	ret z
	ld a, [wBattleType]
	and a
	ret nz                     ; old man / Safari items are their own paths
	farcall IsKeyPocketItem    ; carry = key pocket item; reads wCurItem
	ret nc
	xor a
	ld [wActionResultOrTookBattleTurn], a
	ld a, [wCurItem]
	cp TURN_REWIND
	jr z, .rewind
	sub DOOR_DICE
	cp ITEM_DICE - DOOR_DICE + 1
	ld hl, .NotNowText
	jr c, .print
	ld hl, .AlwaysActiveText
	jr .print
.rewind
	farcall TurnRewindRestore  ; NZ = restored; flags survive the farcall
	ld hl, .RewoundText
	jr nz, .print
	ld hl, .CantRewindText
.print
	call PrintText
	scf
	ret

.NotNowText:
	text_far _ItemUseNotTimeText
	text_end

; wStringBuffer holds the item's name: UseBagItem copies it there first.
.AlwaysActiveText:
	text_ram wStringBuffer
	text " is"
	line "always active!"
	prompt

.RewoundText:
	text "Rewound to the"
	line "last turn!"
	prompt

.CantRewindText:
	text "Can't rewind"
	line "right now!"
	prompt
