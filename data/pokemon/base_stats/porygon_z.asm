	db DEX_PORYGON_Z ; pokedex id

	db  85,  80,  70,  90, 135
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 30 ; catch rate
	db 185 ; base exp

	INCBIN "gfx/pokemon/front/porygonz.pic", 0, 1 ; sprite dimensions
	dw PorygonZPicFront, PorygonZPicBack

	db TACKLE, SHARPEN, CONVERSION, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - from tmp/kep/data/pokemon/base_stats/porygonz.asm;
	; TELEPORT is not a valid TM/HM in this project (same class of error as
	; Slowking's TELEPORT in batch 4), dropped rather than substituted
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   RAGE,         THUNDERBOLT,  THUNDER,      PSYCHIC_M,    \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        \
	     SKULL_BASH,   REST,         THUNDER_WAVE, PSYWAVE,      TRI_ATTACK,   \
	     SUBSTITUTE,   FLASH
	; end

	db BANK(PorygonZPicFront) ; pic bank
