; Hisuian Arcanine - ARCANINE form 1.
;
; Fire/Rock, both valid Gen 1 types.
; Special split: modern SpA 95 / SpD 80, take the HIGHER -> spc 95.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Arcanine.
	form_record ARCANINE, 1

	db DEX_ARCANINE ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  90, 115,  80,  90,  95
	;   hp  atk  def  spd  spc

	db FIRE, ROCK ; type
	db 75 ; catch rate
	db 213 ; base exp

	INCBIN "gfx/pokemon/front/harcanine.pic", 0, 1 ; sprite dimensions
	dw HArcaninePicFront, HArcaninePicBack

	db TAKE_DOWN, EMBER, LEER, BITE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         DRAGON_RAGE,  DIG,          FLAMETHROWER, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         FIRE_BLAST,   SWIFT,        \
	     SKULL_BASH,   REST,         SUBSTITUTE
	; end

	db BANK(HArcaninePicFront) ; pic bank

	dname "H-ARCANINE"

	form_end
