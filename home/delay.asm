DelayFrames::
; wait c frames. In battle, the BATTLE SPEED option (wOptions3) halves c once
; for 2X and twice for 4X, never below 1 frame. Clobbers a (as DelayFrame
; always has) and c.
	ldh a, [hIsInBattle]
	and a
	jr z, .loop
	ld a, [wOptions3]
	and BATTLE_SPEED_MASK
	jr z, .loop
	rrca                    ; a = halvings (1 or 2)
.halve
	srl c
	dec a
	jr nz, .halve
	ld a, c
	and a
	jr nz, .loop
	inc c                   ; c = max(1, c >> n)
.loop
	call DelayFrame
	dec c
	jr nz, .loop
	ret

PlaySoundWaitForCurrent::
	push af
	call WaitForSoundToFinish
	pop af
	jp PlaySound

; Wait for sound to finish playing
WaitForSoundToFinish::
	ld a, [wLowHealthAlarm]
	and $80
	ret nz
	; BATTLE SPEED 4X: in battle, don't hold the game for a cry or hit sound
	; to finish (the next sound may cut its tail). 1X and 2X still wait.
	ldh a, [hIsInBattle]
	and a
	jr z, .wait
	ld a, [wOptions3]
	and BATTLE_SPEED_MASK
	cp BATTLE_SPEED_X4
	ret z
.wait
	push hl
.waitLoop
	ld hl, wChannelSoundIDs + CHAN5
	xor a
	or [hl]
	inc hl
	or [hl]
	inc hl
	inc hl
	or [hl]
	jr nz, .waitLoop
	pop hl
	ret
