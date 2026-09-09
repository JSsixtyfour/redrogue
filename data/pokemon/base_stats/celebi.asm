	db DEX_CELEBI ; pokedex id

	db 100, 100, 100, 100, 100
	;   hp  atk  def  spd  spc

	db PSYCHIC_TYPE, GRASS ; type
	db 45 ; catch rate
	db 64 ; base exp

	INCBIN "gfx/pokemon/front/celebi.pic", 0, 1 ; sprite dimensions
	dw CelebiPicFront, CelebiPicBack

	db LEECH_SEED, CONFUSION, RECOVER, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - modeled on Exeggutor (Grass/Psychic)
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    PSYCHIC_M,    LIGHT_SCREEN, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         REST,         PSYWAVE,      \
	     SUBSTITUTE,   STRENGTH
	; end

	db BANK(CelebiPicFront) ; pic bank
