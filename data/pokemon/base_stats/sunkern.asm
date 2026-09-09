	db DEX_SUNKERN ; pokedex id

	db  30,  30,  30,  30,  30
	;   hp  atk  def  spd  spc

	db GRASS, GRASS ; type
	db 235 ; catch rate
	db 52 ; base exp

	INCBIN "gfx/pokemon/front/sunkern.pic", 0, 1 ; sprite dimensions
	dw SunkernPicFront, SunkernPicBack

	db ABSORB, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         REST,         SUBSTITUTE,   CUT
	; end

	db BANK(SunkernPicFront) ; pic bank
