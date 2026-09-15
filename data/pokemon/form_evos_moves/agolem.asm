AgolemFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of GOLEM's (GolemEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 6, DEFENSE_CURL
	db 12, ROCK_THROW
	db 21, DIG
	db 26, HARDEN
	db 31, SELFDESTRUCT
	db 40, ROCK_SLIDE
	db 45, EARTHQUAKE
	db 48, EXPLOSION
	db 0
