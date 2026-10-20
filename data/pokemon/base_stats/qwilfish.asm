	db DEX_QWILFISH ; pokedex id

	db  65,  95,  75,  85,  55
	;   hp  atk  def  spd  spc

	db WATER, POISON ; type
	db 45 ; catch rate
	db 100 ; base exp

	INCBIN "gfx/pokemon/front/qwilfish.dim" ; sprite dimensions
	dw QwilfishPicFront, QwilfishPicBack

	db TACKLE, POISON_STING, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     THUNDER_WAVE,   MIMIC,      DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         SUBSTITUTE,   SURF,         SELFDESTRUCT, \
         EXPLOSION
	; end

	db BANK(QwilfishPicFront) ; pic bank
