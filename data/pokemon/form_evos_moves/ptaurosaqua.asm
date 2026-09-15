PtaurosaquaFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of TAUROS's (TaurosEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 13, HORN_ATTACK
	db 15, LEER
	db 19, STOMP
	db 23, TAIL_WHIP
	db 27, HEADBUTT
	db 35, RAGE
	db 40, TAKE_DOWN
	db 45, THRASH
	db 50, DOUBLE_EDGE
	db 0
