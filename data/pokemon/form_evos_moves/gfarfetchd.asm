GfarfetchdFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of FARFETCHD's (FarfetchdEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, LEER
	db 9, SHARPEN
	db 13, FURY_ATTACK
	db 18, WING_ATTACK
	db 23, SLASH
	db 28, SWORDS_DANCE
	db 31, DRILL_PECK
	db 39, AGILITY
	db 0
