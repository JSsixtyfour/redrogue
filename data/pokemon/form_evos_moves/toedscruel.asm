ToedscruelFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of TENTACRUEL's (TentacruelEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, SUPERSONIC
	db 13, GROWTH
    db 15, VINE_WHIP
	db 17, POISONPOWDER
	db 22, STUN_SPORE
    db 25, MEGA_DRAIN
	db 27, CONSTRICT
	db 33, SOLARBEAM
	db 40, SCREECH
	db 47, WRAP
	db 48, SPORE
	db 0
