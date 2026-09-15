HelectrodeFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of ELECTRODE's (ElectrodeEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 17, SONICBOOM
	db 19, THUNDERSHOCK
	db 22, SELFDESTRUCT
	db 26, SWIFT
	db 30, LIGHT_SCREEN
	db 35, THUNDERBOLT
	db 44, EXPLOSION
	db 50, THUNDER
	db 0
