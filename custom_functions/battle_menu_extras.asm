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
; third with "Charges: now/max" for the items that have charges (KO DEFIANCE,
; TURN REWIND and the dice). Tiers are left to the field bag.
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
	and a                      ; INFO_NONE: no charges to show
	ret z
	; "Charges: now/max". Every charged key item refills to 1 + its tier
	; (ApplyKeyItemTierEffects, engine/events/credit_mart.asm, for KO DEFIANCE;
	; RogueOnBlackout, custom_functions/credit_popup.asm, for the dice).
	; TURN REWIND alone starts at 2 (wram.asm, wTurnRewindUsages).
	ld d, e                    ; d = kind; farcall keeps d/e, loses a/b/c/h/l
	farcall GetKeyItemTierInE  ; reads wCurItem, set above
	inc e                      ; e = max charges
	ld a, d
	dec a                      ; INFO_KO_USES
	jr nz, .notKO
	ld a, [wKODefianceUsages]
	jr .printCharges
.notKO
	dec a                      ; INFO_REWIND_USES
	jr nz, .dice
	inc e
	ld a, [wTurnRewindUsages]
	jr .printCharges
.dice
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
.printCharges
	push de
	push af
	ld de, .ChargesLabel
	hlcoord 1, 16
	call PlaceString           ; bc = the tile after the label
	pop af
	add '0'
	ld [bc], a
	inc bc
	ld a, '/'
	ld [bc], a
	inc bc
	pop de
	ld a, e
	add '0'
	ld [bc], a
	ret

.ChargesLabel:
	db "Charges: @"

	const_def
	const INFO_NONE
	const INFO_KO_USES
	const INFO_REWIND_USES     ; must stay directly before the dice
	const INFO_DOOR_DICE       ; the three dice must stay in this order and last
	const INFO_MON_DICE
	const INFO_ITEM_DICE

; item, INFO_* kind, two description lines (18 tiles each at most)
MACRO battle_item_info
	db \1, \2
	dw \3
ENDM

BattleItemInfoTable:
	battle_item_info LEFTOVERS,     INFO_NONE,      .Leftovers
	battle_item_info PP_TONIC,      INFO_NONE,      .PPTonic
	battle_item_info KO_DEFIANCE,   INFO_KO_USES,   .KODefiance
	battle_item_info EXP_ALL,       INFO_NONE,      .ExpAll
	battle_item_info SHINY_CHARM,   INFO_NONE,      .ShinyCharm
	battle_item_info AMULET_COIN,   INFO_NONE,      .AmuletCoin
	battle_item_info TURN_REWIND,   INFO_REWIND_USES, .TurnRewind
	battle_item_info RARE_SCOPE,    INFO_NONE,      .RareScope
	battle_item_info RARE_LENS,     INFO_NONE,      .RareLens
	battle_item_info DV_BOOSTER,    INFO_NONE,      .DVBooster
	battle_item_info STAT_BOOSTER,  INFO_NONE,      .StatBooster
	battle_item_info DOOR_DICE,     INFO_DOOR_DICE, .DoorDice
	battle_item_info MON_DICE,      INFO_MON_DICE,  .MonDice
	battle_item_info ITEM_DICE,     INFO_ITEM_DICE, .ItemDice
	battle_item_info ELEMENT_PRISM, INFO_NONE,      .ElementPrism
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
	ld a, [wTurnRewindUsages]
	and a
	ld hl, .NoRewindsText
	jr z, .print
	farcall TurnRewindRestore  ; NZ = restored; flags survive the farcall
	ld hl, .CantRewindText
	jr z, .print               ; a refusal costs no charge
	ld hl, wTurnRewindUsages
	dec [hl]
	ld hl, .RewoundText
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

.NoRewindsText:
	text "No rewinds left"
	line "this run!"
	prompt

; ============================================================
; Ghost-variant entrance: the mon fades in from nothing, the way the vanilla
; ghost MAROWAK was revealed. Four Battle Core draw sites hand off here, each by a
; farcall the same size as the `hlcoord` + `predef` pair it replaced, and each
; keeps the vanilla draw for any mon that is not a ghost variant.
;   RogueDrawWildEnemyPic        InitWildBattle: a ghost stays blank for the slide.
;   RogueWildEnemyGhostEntrance  PrintBeginningBattleText (common_text.asm): the
;                                fade, before the cry and "Wild X appeared!".
;   RogueAnimateEnemySendOut     EnemySendOut: a trainer's ghost (none exist yet).
;   RogueAnimatePlayerSendOut    SendOutMon: the player's own ghost variant.
; The ghost flag is bit 0 of the struct's catch-rate byte (func_ghost_variant.asm).
; ============================================================
RogueDrawWildEnemyPic::
	ld de, wEnemyMon
	farcall IsGhostVariant
	ret nz                     ; ghost: RogueWildEnemyGhostEntrance fades it in
	hlcoord 12, 0              ; hStartTileID is already 0 here
	predef_jump CopyUncompressedPicToTilemap

RogueWildEnemyGhostEntrance::
	ld de, wEnemyMon
	farcall IsGhostVariant
	ret z
	ld e, 1
	jr RogueGhostFadeIn

RogueAnimateEnemySendOut::
	ld de, wEnemyMon
	farcall IsGhostVariant     ; flags survive the farcall; ld keeps them
	ld e, 1
	jr nz, RogueGhostFadeIn
	hlcoord 15, 6              ; the caller set hStartTileID = -$31
	predef_jump AnimateSendingOutMon

RogueAnimatePlayerSendOut::
	ld de, wBattleMon
	farcall IsGhostVariant
	ld e, 0
	jr nz, RogueGhostFadeIn
	hlcoord 4, 11
	predef_jump AnimateSendingOutMon

; ============================================================
; RogueGhostFadeIn - ported from the MarowakAnim this tree used to carry
; (git show c1a0d2f1^:engine/battle/ghost_marowak_anim.asm): its fade-in half
; and CopyMonPicFromBGToSpriteVRAM, parametrized by side. The pic is shown as a
; 6x6 grid of OBP1 sprites while rOBP1 ramps from $00 to $e4, then drawn into
; the tilemap and the sprites cleared. As in the original, the pic's top row and
; left column get no sprite (6x6 = 36 of the 40 OAM slots); pics rarely use them,
; and they appear when the tilemap copy lands.
; INPUT: e = 0 player back pic at (1,5), 1 enemy front pic at (12,0)
;
; CGB: UpdateGBCPal_OBP1 fills OBJ palettes 4-7 from base palettes 0-3, and
; SetPal_Battle puts the player mon's palette in base 2 and the enemy's in base 3,
; so the sprites use OBJ palette 6 / 7 (attr $16 / $17: OBP1 + that palette) and
; fade in the same purple the BG pic is drawn in. The original used $14 (OBJ
; palette 4 = the player's HP bar color).
; ============================================================
RogueGhostFadeIn:
	xor a
	ldh [rOBP1], a             ; every shade white: the sprites start invisible
	call UpdateGBCPal_OBP1     ; preserves every register
	ld a, e
	and a
	jr z, .player
	ld de, vFrontPic
	ld a, $10
	ld [wBaseCoordY], a
	ld a, $70
	ld [wBaseCoordX], a
	ld c, $17
	xor a                      ; vFrontPic's first tile
	hlcoord 12, 0
	jr .gotSide
.player
	ld de, vBackPic
	ld a, $38
	ld [wBaseCoordY], a
	ld a, $18
	ld [wBaseCoordX], a
	ld c, $16
	ld a, $31                  ; vBackPic's first tile
	hlcoord 1, 5
.gotSide
	; for the tilemap redraw at the end; nothing in between reads it
	ldh [hStartTileID], a
	push hl                    ; the pic's tilemap corner, for the clear and redraw
	push bc                    ; c = OAM attribute
	ld hl, vSprites
	lb bc, BANK(@), PIC_SIZE   ; VRAM source: the bank byte only has to be harmless
	call CopyVideoData
	pop bc
	; OAM grid (CopyMonPicFromBGToSpriteVRAM): pic tiles are column-major, 7 per
	; column; start at column 1 row 1 (tile 8) and skip each column's row 0
	ld hl, wShadowOAM
	ld b, 6
	ld d, $8
.oamLoop
	push bc
	ld a, [wBaseCoordY]
	ld e, a
	ld b, 6
.oamInnerLoop
	ld a, e
	add $8
	ld e, a
	ld [hli], a
	ld a, [wBaseCoordX]
	ld [hli], a
	ld a, d
	ld [hli], a
	ld a, c
	ld [hli], a
	inc d
	dec b
	jr nz, .oamInnerLoop
	inc d
	ld a, [wBaseCoordX]
	add $8
	ld [wBaseCoordX], a
	pop bc
	dec b
	jr nz, .oamLoop
	; clear the BG pic so only the fading sprites show it
	pop hl
	push hl
	lb bc, 7, 7
	call ClearScreenArea
	call Delay3
	ld b, $e4
.fadeInLoop
	ld c, 10
	call DelayFrames
	ldh a, [rOBP1]
	srl b
	rra
	srl b
	rra
	ldh [rOBP1], a
	call UpdateGBCPal_OBP1
	ld a, b
	and a
	jr nz, .fadeInLoop
	; the pic back into the tilemap, then drop the sprites
	pop hl
	predef CopyUncompressedPicToTilemap
	xor a
	ldh [hStartTileID], a
	call Delay3
	jp ClearSprites
