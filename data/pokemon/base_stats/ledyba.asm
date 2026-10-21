	db DEX_LEDYBA ; pokedex id

	db  40,  20,  30,  55,  65
	;   hp  atk  def  spd  spc

	db BUG, FLYING ; type
	db 255 ; catch rate
	db 54 ; base exp

	INCBIN "gfx/pokemon/front/ledyba.dim" ; sprite dimensions
	dw LedybaPicFront, LedybaPicBack

	db TACKLE, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   RAZOR_WIND,   SUBSTITUTE,   TOXIC,        TAKE_DOWN,    \
	     DOUBLE_EDGE,  SWORDS_DANCE, RAGE,         MEGA_DRAIN,   SOLARBEAM,    \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        \
	     REST,         COUNTER,      DIG,          SUBMISSION,   LIGHT_SCREEN, \
	     FLASH
	; end

	db BANK(LedybaPicFront) ; pic bank
