; AI review CP3 (2026-11-12; AI_REVIEW_PLAN_2026-11-12.md): the high-crit move a
; player's species is known to learn by level-up. Its own floating section, like
; "AI Boom Species": the only caller (AIGetPlayerMoveN, ai_accessors.asm, bank
; $0E) farcalls it, and it answers in e, which survives a farcall. Keep the table
; and the routine together: the routine reads the table with plain in-bank reads.
;
; Species knowledge, the same fair-play footing as the visible-type guess: a
; player who sees a Persian above level 34 expects Slash. Karate Chop, Razor
; Leaf, Crabhammer and Slash are not TMs here, so the level-up list is their one
; normal source. A form uses its base species' row.

; OUTPUT: e = the high-crit move the player's active mon (wBattleMonSpecies) has
; reached by level (wBattleMonLevel), 0 if none. Clobbers af, bc, d, hl.
AIGuessCritMove::
	ld a, [wBattleMonSpecies]
	ld b, a
	ld a, [wBattleMonLevel]
	ld c, a
	ld hl, AICritSpeciesTable
.next
	ld a, [hli]
	and a
	jr z, .none ; end of table
	cp b
	jr nz, .skip
	ld a, [hli]
	ld d, a ; the move
	ld a, c
	cp [hl] ; carry: the mon is below the learn level
	inc hl
	jr c, .next
	ld e, d
	ret
.skip
	inc hl
	inc hl
	jr .next
.none
	ld e, 0
	ret

INCLUDE "data/battle/ai_crit_species.asm"
