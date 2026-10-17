GponytaFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of PONYTA's (PonytaEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, TAIL_WHIP
    db 12, CONFUSION
	db 19, STOMP
	db 25, QUICK_ATTACK
	db 26, PSYBEAM
	db 35, AGILITY
	db 36, PSYCHIC_M
	db 40, TAKE_DOWN
	db 45, RECOVER
	db 0
