; AI_T4_REGRET_PLAN E1 (2026-11-18): which move of a type the AI presumes an
; unrevealed player slot holds. AIGetPlayerMoveN (ai_accessors.asm, bank $0E)
; still decides WHETHER a slot holds a guess (a STAB attack is presumed for each
; visible type until this mon reveals one); this decides WHICH: the strongest
; move of that type the species/form can actually carry, from
; tools/gen_ai_guess_learnset.py's tables. Replaces the old per-type table
; (AIStabGuessByType), which ignored the learnset: a mon with no damaging move of
; its type was still feared, and the strong/weak rows were a level proxy.
;
; TM moves are gated by a CEILING that rises with run progress (user, 2026-11-18:
; Master Ball TMs can arrive at any time by luck but get likelier as the run goes
; on; gym leaders give a TM per badge, routes roll ~20% Master). Ceiling = the
; highest mart rarity class presumed: 1 = Poke/Great, 2 = +Ultra, 3 = +Master,
; from the badge count (AI_GUESS_*_BADGES). Fair play: never sTMBitfield, which
; is the player's real TM case. Level-up and tutor moves need no gate.
;
; Two floating sections split by species id (no bank had room for one); each has
; a per-species index, so a lookup is O(1), not a table scan: AIGetPlayerMoveN
; runs for every slot of every threat scan.
;
; Contract (both entries): INPUT e = the type to guess for. Reads
; wBattleMonSpecies / CatchRate (form) / Level / Type1 and wObtainedBadges.
; OUTPUT e = the move, 0 = none (e survives the farcall return).
; Clobbers af, bc, d, hl. The caller picks the entry by AI_GUESS_SPLIT_SPECIES
; (data/battle/ai_guess_learnset_split.asm, included by ai_accessors.asm, which is
; assembled first), so each guess is ONE farcall.

; \1 = the section's label prefix (AIGuessLo / AIGuessHi), \2 = its first species id.
MACRO ai_guess_lookup
	ld a, [wBattleMonSpecies]
	sub \2
	ld l, a
	ld h, 0
	add hl, hl
	ld bc, \1Index
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = this species' block
	ld a, [wBattleMonCatchRate]
	and FORM_MASK ; bits 5-6
	add a ; -> bits 6-7, the record header's form field
	ld d, a
	push hl ; the base form's record (sorted first): the fallback
.record\@
	ld a, [hl]
	cp $ff
	jr z, .fallback\@
	and %11000000
	cp d
	jr z, .found\@
	ld a, [hl] ; skip it: 1 + 2 x (n1 + n2) bytes
	ld b, a
	and %111
	ld c, a
	ld a, b
	rra
	rra
	rra
	and %111
	add c
	add a
	inc a
	add l
	ld l, a
	jr nc, .record\@
	inc h
	jr .record\@
.fallback\@
	pop hl
	ld a, [hl]
	cp $ff
	jr z, .none\@ ; no row for this species at all (stack already balanced)
	push hl ; for .found's pop
.found\@
	pop bc ; drop the fallback
	ld a, [hli]
	ld d, a ; d = the header; hl = the first type's entries
	rra
	rra
	rra
	and %111
	ld b, a ; b = n1
; Rows follow the species' own type order, which is the battle mon's unless
; Transform/Conversion changed it: the first type's row, else the second's.
	ld a, [wBattleMonType1]
	cp e
	jr z, .rowFirst\@
	ld a, b
	add a ; skip the first type's entries
	add l
	ld l, a
	jr nc, .second\@
	inc h
.second\@
	ld a, d
	and %111 ; n2
	jr .scan\@
.rowFirst\@
	ld a, b
.scan\@
	and a
	jr z, .none\@
	ld d, a ; d = entries left
; The ceiling, counted inline (CountSetBits writes wNumSetBits, which aliases
; wTypeEffectiveness / wMoveType, live in the middle of an AI decision).
	ld a, [wObtainedBadges]
	ld b, 0
.badge\@
	and a
	jr z, .gotBadges\@
	srl a
	jr nc, .badge\@
	inc b
	jr .badge\@
.gotBadges\@
	ld c, 1
	ld a, b
	cp AI_GUESS_ULTRA_BADGES
	jr c, .entry\@
	inc c
	cp AI_GUESS_MASTER_BADGES
	jr c, .entry\@
	inc c ; c = the ceiling
.entry\@
	ld a, [hli]
	ld b, a ; b = the move
	ld a, [hli] ; its gate: < $80 a level, $80 | ceiling a TM
	bit 7, a
	jr nz, .tm\@
	push hl
	ld hl, wBattleMonLevel
	cp [hl] ; carry or Z: the gate level <= the mon's level
	pop hl
	jr c, .fits\@
	jr z, .fits\@
	jr .next\@
.tm\@
	and %11
	cp c ; carry or Z: the TM's class <= the ceiling
	jr c, .fits\@
	jr z, .fits\@
.next\@
	dec d
	jr nz, .entry\@
.none\@
	ld e, 0
	ret
.fits\@
	ld e, b
	ret
ENDM

SECTION "AI Guess Learnset Lo", ROMX

AIGuessLearnset:: ; species below AI_GUESS_SPLIT_SPECIES only (the caller checks)
	ld a, [wBattleMonSpecies]
	cp AI_GUESS_LO_FIRST
	jr nc, .lookup
	ld e, 0
	ret
.lookup
	ai_guess_lookup AIGuessLo, AI_GUESS_LO_FIRST

INCLUDE "data/battle/ai_guess_learnset_lo.asm"

SECTION "AI Guess Learnset Hi", ROMX

AIGuessLearnsetHi::
	ld a, [wBattleMonSpecies]
	cp AI_GUESS_HI_LAST + 1
	jr c, .lookup
	ld e, 0
	ret
.lookup
	ai_guess_lookup AIGuessHi, AI_GUESS_SPLIT_SPECIES

INCLUDE "data/battle/ai_guess_learnset_hi.asm"
