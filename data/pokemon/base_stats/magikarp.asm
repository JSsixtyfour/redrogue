	db DEX_MAGIKARP ; pokedex id

	db  20,  10,  55,  80,  20
	;   hp  atk  def  spd  spc

	db WATER, WATER ; type
	db 255 ; catch rate
	db 20 ; base exp

	INCBIN "gfx/pokemon/front/magikarp.dim" ; sprite dimensions
	dw MagikarpPicFront, MagikarpPicBack

	db TACKLE, SPLASH, NO_MOVE, NO_MOVE ; level 1 learnset - SPLASH restored (Red/Blue)
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm
	; end

	db BANK(MagikarpPicFront) ; pic bank
