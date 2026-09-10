; Galarian Moltres - MOLTRES form 1.
;
; Dark/Flying. PRIMARY Dark becomes NORMAL; secondary Flying is unaffected.
; Special split: modern SpA 100 / SpD 125, take the HIGHER -> spc 125.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Moltres.
	form_record MOLTRES, 1

	db DEX_MOLTRES ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  90,  85,  90,  90, 125
	;   hp  atk  def  spd  spc

	db NORMAL, FLYING ; type
	db 3 ; catch rate
	db 217 ; base exp

	INCBIN "gfx/pokemon/front/gmoltres.pic", 0, 1 ; sprite dimensions
	dw GMoltresPicFront, GMoltresPicBack

	db PECK, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   FLAMETHROWER, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         FIRE_BLAST,   SWIFT,        SKY_ATTACK,   REST,         \
	     SUBSTITUTE,   FLY
	; end

	db BANK(GMoltresPicFront) ; pic bank

	dname "G-MOLTRES"

	form_end
