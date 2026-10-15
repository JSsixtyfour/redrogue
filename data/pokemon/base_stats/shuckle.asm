	db DEX_SHUCKLE ; pokedex id

	db  20,  10, 230,   5, 230
	;   hp  atk  def  spd  spc

	db BUG, ROCK ; type
	db 190 ; catch rate
	db 80 ; base exp

	INCBIN "gfx/pokemon/front/shuckle.dim" ; sprite dimensions
	dw ShucklePicFront, ShucklePicBack

	db CONSTRICT, WITHDRAW, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_SLOW ; growth rate

	; tm/hm learnset - modeled on Onix (defensive Rock-type tank)
	tmhm TOXIC,        RAGE,         EARTHQUAKE,   SUBSTITUTE,   STRENGTH, \
	     DIG,          MIMIC,        DOUBLE_TEAM,  FLASH,      BIDE,         \
	     REST,         ROCK_SLIDE
	; end

	db BANK(ShucklePicFront) ; pic bank
