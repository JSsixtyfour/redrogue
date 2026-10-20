; Body Armor's move checks. They live in their own floating section because
; "rogue" (bridge_selected_effects.asm's bank) and "Battle Core" (which calls
; them) are both full.

; Called after GetCurrentMove has loaded wPlayerMovePower, with the menu's
; choice in wPlayerSelectedMove. Carry is set after printing the rejection only
; when Body Armor blocks a zero-power move. When it would block every move the
; mon could select (PP left, not Disabled), the menu would accept nothing and
; the battle could not go on: then the mon Struggles instead, as with no PP
; left, and carry is clear.
BridgeBodyArmorBlocksSelectedMove::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld e, BRIDGE_SELECTED_EFFECT_BODY_ARMOR
	farcall BridgeActiveMonHasSelectedEffect
	ret nc
	call BridgeBodyArmorRefusesLoadedMove
	ret nc
	call BridgeBodyArmorRefusesEveryMove
	jr c, .struggle
	ld hl, .blockedText
	call PrintText
	call LoadScreenTilesFromBuffer1
	scf
	ret
.struggle
	ld hl, .noMovesLeftText
	call PrintText
	ld c, 60
	call DelayFrames
	ld a, STRUGGLE
	ld [wPlayerSelectedMove], a
	ld [wTestBattlePlayerSelectedMove], a
	and a                          ; accepted
	ret
.blockedText
	text "BODY ARMOR"
	line "BLOCKS STATUS!"
	prompt
.noMovesLeftText
	text_far _NoMovesLeftText
	text_end

; Out: carry set when Body Armor refuses every move the active mon could select
; (PP left, not Disabled). Loads each one into wPlayerMoveNum..., which move
; execution reloads for the move actually used.
BridgeBodyArmorRefusesEveryMove:
	ld a, [wPlayerDisabledMove]
	swap a
	and $f
	ld d, a                        ; d = the Disabled slot + 1, 0 = none
	ld e, 0                        ; e = move slot
.loop
	ld b, 0
	ld c, e
	ld hl, wBattleMonPP
	add hl, bc
	ld a, [hl]
	and PP_MASK
	jr z, .next
	ld a, e
	inc a
	cp d
	jr z, .next
	ld hl, wBattleMonMoves
	add hl, bc
	ld a, [hl]
	and a
	jr z, .next
	push de
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wPlayerMoveNum
	ld bc, MOVE_LENGTH
	ld a, BANK(Moves)
	call FarCopyData
	call BridgeBodyArmorRefusesLoadedMove
	pop de
	jr nc, .someMoveUsable
.next
	inc e
	ld a, e
	cp NUM_MOVES
	jr c, .loop
	scf
	ret
.someMoveUsable
	and a
	ret

; Out: carry set when Body Armor refuses the move loaded in wPlayerMovePower /
; wPlayerMoveEffect: no base power, and not a fixed-damage move.
BridgeBodyArmorRefusesLoadedMove:
	ld a, [wPlayerMovePower]
	and a
	ret nz
	ld a, [wPlayerMoveEffect]
	cp SPECIAL_DAMAGE_EFFECT
	ret z
	cp SUPER_FANG_EFFECT
	ret z
	cp BIDE_EFFECT
	ret z
	scf
	ret

