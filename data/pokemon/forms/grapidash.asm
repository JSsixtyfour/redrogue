; Galarian Rapidash - RAPIDASH form 1.
;
; Psychic (single type in modern games).
; Special split: modern SpA 80 / SpD 80, tie either way -> spc 80.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Rapidash.
	form_record RAPIDASH, 1

	db DEX_RAPIDASH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65, 100,  70, 105,  80
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, PSYCHIC_TYPE ; type
	db 60 ; catch rate
	db 192 ; base exp

	INCBIN "gfx/pokemon/front/grapidash.pic", 0, 1 ; sprite dimensions
	dw GRapidashPicFront, GRapidashPicBack

	db EMBER, TAIL_WHIP, STOMP, GROWL ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        HORN_DRILL,   BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         FIRE_BLAST,   SWIFT,        SKULL_BASH,   REST,         \
	     SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(GRapidashPicFront) ; pic bank

	dname "G-RAPIDASH"

	form_end
