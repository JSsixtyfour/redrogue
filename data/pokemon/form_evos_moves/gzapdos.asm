GzapdosFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of ZAPDOS's (ZapdosEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 10, DOUBLE_KICK
    db 18, LOW_KICK
    db 22, TAKEDOWN
    db 30, COUNTER
    db 32, ROLLING_KICK
	db 35, AGILITY
	db 40, DRILL_PECK
	db 45, JUMP_KICK
    db 51, HI_JUMP_KICK
    db 55, MEGA_KICK
	db 0
