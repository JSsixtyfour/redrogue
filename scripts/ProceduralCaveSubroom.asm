; The cave's subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4), on the map id of the
; unreachable SAFARI_ZONE_NORTH_REST_HOUSE. Reached by either of the cave's two
; ladders down; each of its two ladders up leads back to its own. The room is a
; placeholder cut from Mt. Moon B1F's two-ladder chamber
; (maps/ProceduralCaveSubroom.blk), to be redrawn. Its resident is a coin flip
; per cave: the Gambler (Money Match) or the Super Nerd, the Facility's.

ProceduralCaveSubroom_Script:
	call EnableAutoTextBoxDrawing
	; A resident's battle, if one just ended: record a win; the Super Nerd then
	; hands over his prize (the Gambler paid in the battle).
	farcall FacSuperNerdSettle
	ret nc
	farcall CaveSubroomResidentIsNerd
	ret nc
	ld a, TEXT_CAVESUB_PRIZE
	ldh [hTextID], a
	jp DisplayTextID

ProceduralCaveSubroom_TextPointers:
	def_text_pointers
	; Objects first, in slot order; script-only texts after them.
	dw_const CaveSubGamblerText,   TEXT_CAVESUB_GAMBLER
	dw_const CaveSubSuperNerdText, TEXT_CAVESUB_SUPER_NERD
	dw_const CaveSubBallText,      TEXT_CAVESUB_BALL
	dw_const CaveSubPrizeText,     TEXT_CAVESUB_PRIZE

; Money Match (custom_functions/money_match.asm), started here as the forest
; rest house starts it; the win is settled by FacSuperNerdSettle, which records
; it in CAVESUB_STATE.
CaveSubGamblerText:
	text_asm
	push bc
	farcall MoneyMatchHouseTalk     ; carry = the player accepted
	pop bc
	jr nc, .done
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, CaveSubGamblerBeatenText
	ld de, CaveSubGamblerWonText
	call SaveEndBattleTextPointers  ; this bank, read back after the battle
	ld a, OPP_GAMBLER
	ld [wCurOpponent], a
	ld a, 1                         ; his party is the roster's (MONEY_MATCH_STEP)
	ld [wTrainerNo], a
	ld [wIsTrainerBattle], a
	ld a, SCRIPT_SUPER_NERD_AFTER_BATTLE
	ld [wSafariZoneGateCurScript], a
.done
	jp TextScriptEnd

CaveSubSuperNerdText:
	text_asm
	push bc
	farcall FacSuperNerdTalk
	pop bc
	jp TextScriptEnd

CaveSubBallText:
	text_asm
	push bc
	farcall FacSubroomPickUpBall    ; shared with the Facility subroom's ball
	pop bc
	jp TextScriptEnd

CaveSubPrizeText:
	text_asm
	push bc
	farcall FacSuperNerdPrize
	pop bc
	jp TextScriptEnd

; In battle: he lost. Line 1 already holds "GAMBLER: " (9 of 18).
CaveSubGamblerBeatenText:
	text "Ah ha!"
	para "You earned this!"
	prompt

; In battle: he won.
CaveSubGamblerWonText:
	text "House wins!"
	prompt
