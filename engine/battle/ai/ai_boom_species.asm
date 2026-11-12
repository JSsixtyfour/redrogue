; Setup gate, item 3 (2026-11-12): can the player's active mon blow up?
;
; Its own floating section: nothing here reads another bank, and the only caller
; (AISetupExtraHitHurts, ai_setup_gate.asm, bank $0E) farcalls it, so it can sit
; in any bank with room. Keep the table and the routine together: the routine
; indexes the table with a plain in-bank read.

; Carry SET if the player's active species, or a form of it, can ever learn
; Explosion or Self-Destruct. This is species knowledge, like the type guess in
; AIGetPlayerMoveN: a player who sees a Golem knows it may carry Explosion, so
; the AI may assume as much without having seen the move. Clobbers af, bc, de, hl.
AIPlayerSpeciesCanExplode::
	ld a, [wBattleMonSpecies]
	ld c, a
	srl a
	srl a
	srl a
	ld e, a
	ld d, 0
	ld hl, AIBoomSpeciesBits
	add hl, de
	ld a, c
	and 7
	inc a
	ld b, a
	ld a, [hl]
.shift ; rrca leaves the bit just shifted out in carry; dec does not touch it
	rrca
	dec b
	jr nz, .shift
	ret

INCLUDE "data/battle/ai_boom_species.asm"
