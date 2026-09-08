	db DEX_LEDIAN ; pokedex id

	db  55,  35,  50,  85, 110
	;   hp  atk  def  spd  spc

	db BUG, FLYING ; type
	db 90 ; catch rate
	db 134 ; base exp

	INCBIN "gfx/pokemon/front/ledian.pic", 0, 1 ; sprite dimensions
	dw LedianPicFront, LedianPicBack

	db TACKLE, SUPERSONIC, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    PSYCHIC_M,    \
	     PSYWAVE,      MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         FLY
	; end

	db BANK(LedianPicFront) ; pic bank
