; Intimidating Presence (Trashed House gift: the special Growlithe family).
; Floating section, reached only by farcall from SendOutMon (battle core); it
; reaches "rogue" (GetSpecialFormCaps) and battle core (BridgeRecalculateEnemyStat,
; PlaySelectedAnimation) only by farcall, so it can land in any bank.

SECTION "Bridge Intimidate", ROMX

; On each player send-out, lower the opposing active mon's Attack one stage
; when the player form is the special Growlithe family, with the LEER
; animation and a message so it is visible. Stage changes saturate at -6
; through the standard 1..13 modifier representation; at the floor, or when
; the target is behind a Substitute or Mist, the message says the Attack
; won't drop instead. hWhoseTurn is preserved.
BridgeTryIntimidate::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld hl, wEnemyMonHP
	ld a, [hli]
	or [hl]
	ret z                       ; no live target
	ld de, wBattleMon
	farcall GetSpecialFormCaps  ; de in, caps out in e
	bit SF_INTIMIDATE, e
	ret z
	ldh a, [hWhoseTurn]
	push af
	xor a
	ldh [hWhoseTurn], a         ; player is <USER>, enemy is <TARGET>
	lb de, 0, LEER              ; d = player side, e = animation id
	farcall PlaySelectedAnimation
	; Substitute and Mist block it, as in later games. Fly/Dig do not: it is
	; not a move, so there is no accuracy check to dodge.
	ld hl, BridgeIntimidateFloorText
	ld a, [wEnemyBattleStatus2]
	and (1 << HAS_SUBSTITUTE_UP) | (1 << PROTECTED_BY_MIST)
	jr nz, .print
	ld a, [wEnemyMonAttackMod]
	cp 1
	jr z, .print
	ld hl, wEnemyMonAttackMod
	dec [hl]
	ld e, 0                     ; Attack stat index
	farcall BridgeRecalculateEnemyStat
	ld hl, BridgeIntimidateText
.print
	call PrintText
	ld hl, .emptyString         ; clear the box, as SendOutMon's own text does
	call PrintText
	pop af
	ldh [hWhoseTurn], a
	ret
.emptyString
	db "@"

BridgeIntimidateText:
	text "<USER>'s"
	line "INTIMIDATE!"
	para "<TARGET>'s"
	line "ATTACK fell!"
	prompt

BridgeIntimidateFloorText:
	text "<USER>'s"
	line "INTIMIDATE!"
	para "<TARGET>'s"
	line "ATTACK won't drop!"
	prompt
