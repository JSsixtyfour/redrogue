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
