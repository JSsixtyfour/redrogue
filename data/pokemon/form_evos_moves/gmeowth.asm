GmeowthFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of MEOWTH's (MeowthEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 10, FURY_SWIPES
	db 12, ROCK_THROW
	db 15, BITE
	db 18, PAY_DAY
	db 22, SCREECH
	db 29, THRASH
	db 34, SLASH
	db 44, ROCK_SLIDE
	db 0
