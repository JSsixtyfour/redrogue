	db DEX_GLIGAR ; pokedex id

	db  65,  75, 105,  85,  65
	;   hp  atk  def  spd  spc

	db GROUND, FLYING ; type
	db 60 ; catch rate
	db 108 ; base exp

	INCBIN "gfx/pokemon/front/gligar.pic", 0, 1 ; sprite dimensions
	dw GligarPicFront, GligarPicBack

	db POISON_STING, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         SWIFT,        REST,         EARTHQUAKE,   FISSURE,      \
	     DIG,          FLY
	; end

	db BANK(GligarPicFront) ; pic bank
