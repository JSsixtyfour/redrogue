	db DEX_LEDYBA ; pokedex id

	db  40,  20,  30,  55,  80
	;   hp  atk  def  spd  spc

	db BUG, FLYING ; type
	db 255 ; catch rate
	db 54 ; base exp

	INCBIN "gfx/pokemon/front/ledyba.pic", 0, 1 ; sprite dimensions
	dw LedybaPicFront, LedybaPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  \
	     HYPER_BEAM,   RAGE,         MEGA_DRAIN,   SOLARBEAM,    PSYCHIC_M,    \
	     PSYWAVE,      MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         FLY
	; end

	db BANK(LedybaPicFront) ; pic bank
