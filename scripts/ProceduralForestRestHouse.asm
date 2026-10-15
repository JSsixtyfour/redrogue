; The forest's rest house (PROCEDURAL_SUBROOMS_PLAN Phase 4), on the map id of
; the unreachable SAFARI_ZONE_CENTER_REST_HOUSE. Entered through the house
; PFinalizeForest stands on one of the forest's door spots. Who is home, and
; what they offer, is rolled once per forest (PFRestHouseRollResidents).
;
; The residents are the lobby's own services. Their code lives elsewhere, so
; each text here is a text_asm stub; bc is the live text cursor and every
; farcall destroys it, hence the push/pop around each one.
; Script state, in wSafariZoneGateCurScript: the Safari Zone is unreachable
; and this house has no other state. AFTER_MONEY_MATCH is armed by the
; gambler's text the moment the player accepts.
DEF SCRIPT_PFRESTHOUSE_DEFAULT           EQU 0
DEF SCRIPT_PFRESTHOUSE_AFTER_MONEY_MATCH EQU 1

ProceduralForestRestHouse_Script:
	call EnableAutoTextBoxDrawing
	ld a, [wSafariZoneGateCurScript]
	cp SCRIPT_PFRESTHOUSE_AFTER_MONEY_MATCH
	ret nz
	; The overworld starts the battle on the frame wCurOpponent is set; until
	; it has run (the battle zeroes wCurOpponent) there is nothing to settle.
	ld a, [wCurOpponent]
	and a
	ret nz
	xor a
	ASSERT SCRIPT_PFRESTHOUSE_DEFAULT == 0
	ld [wSafariZoneGateCurScript], a
	ld [wIsTrainerBattle], a
	ld hl, wStatusFlags3
	res BIT_PRINT_END_BATTLE_TEXT, [hl]
	; The overworld runs this once with $ff after an all-faint loss: the
	; blackout takes it from there.
	ldh a, [hIsInBattle]
	inc a
	ret z
	farjp MoneyMatchHouseRecordWin

ProceduralForestRestHouse_TextPointers:
	def_text_pointers
	dw_const PFRestHouseRentalText,      TEXT_PFRESTHOUSE_RENTAL_OFFICIAL
	dw_const PFRestHouseHealingMartText, TEXT_PFRESTHOUSE_CLERK_HEALING
	dw_const PFRestHouseStockMartText,   TEXT_PFRESTHOUSE_CLERK_STOCK
	dw_const PFRestHouseTutorText,       TEXT_PFRESTHOUSE_MOVE_TUTOR
	dw_const PFRestHouseTraderText,      TEXT_PFRESTHOUSE_TRADER
	dw_const PFRestHouseSalesmanText,    TEXT_PFRESTHOUSE_SALESMAN
	dw_const PFRestHouseGamblerText,     TEXT_PFRESTHOUSE_GAMBLER

PFRestHouseRentalText:
	text_asm
	push bc
	rfarcall RentalInteraction
	pop bc
	jp TextScriptEnd

PFRestHouseHealingMartText:
	text_asm
	ld e, 0                         ; the healing clerk's list
	jr PFRestHouseMart

PFRestHouseStockMartText:
	text_asm
	ld e, 1                         ; the stock clerk's list
PFRestHouseMart:
	push bc
	farcall PFRestHouseRunMart      ; e, not a: a farcall destroys a/b/c/h/l going in
	pop bc
	jp TextScriptEnd

PFRestHouseTutorText:
	text_asm
	push bc
	farcall PCMoveTutorTalk
	pop bc
	jp TextScriptEnd

PFRestHouseTraderText:
	text_asm
	push bc
	farcall PCTraderSuperNerdTalk   ; the lobby trader's own talk, result text included
	pop bc
	jp TextScriptEnd

PFRestHouseSalesmanText:
	text_asm
	push bc
	farcall PCPokemonSalesmanTalk
	pop bc
	jp TextScriptEnd

; Money Match (custom_functions/money_match.asm). A plain object, so the
; battle is started here, the way AILair starts its fight: a map trainer would
; need an event flag to remember the win, and the event array is full. The
; win is remembered per forest in sProcForestItemGot instead.
PFRestHouseGamblerText:
	text_asm
	push bc
	farcall MoneyMatchHouseTalk     ; carry = the player accepted
	pop bc
	jr nc, .done
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, PFRestHouseGamblerBeatenText
	ld de, PFRestHouseGamblerWonText
	call SaveEndBattleTextPointers  ; this bank, read back after the battle
	ld a, OPP_GAMBLER
	ld [wCurOpponent], a
	ld a, 1                         ; his party is the roster's (MONEY_MATCH_STEP)
	ld [wTrainerNo], a
	ld [wIsTrainerBattle], a
	ld a, SCRIPT_PFRESTHOUSE_AFTER_MONEY_MATCH
	ld [wSafariZoneGateCurScript], a
.done
	jp TextScriptEnd

; In battle: he lost.
; Line 1 already holds "GAMBLER: " (9 of 18).
PFRestHouseGamblerBeatenText:
	text "Ah ha!"
	para "You earned this!"
	prompt

; In battle: he won.
PFRestHouseGamblerWonText:
	text "House wins!"
	prompt
