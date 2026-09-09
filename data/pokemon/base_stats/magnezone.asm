	db DEX_MAGNEZONE ; pokedex id

	db  70,  70, 115,  60, 130
	;   hp  atk  def  spd  spc

	db ELECTRIC, ELECTRIC ; type - Steel (secondary) dropped per project type rules
	db 30 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/magnezone.pic", 0, 1 ; sprite dimensions
	dw MagnezonePicFront, MagnezonePicBack

	db TACKLE, THUNDERSHOCK, SONICBOOM, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - from tmp/kep/data/pokemon/base_stats/magnezone.asm;
	; TELEPORT is not a valid TM/HM in this project (same class of error as
	; Slowking's TELEPORT in batch 4), dropped rather than substituted
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     THUNDERBOLT,  THUNDER,      MIMIC,        DOUBLE_TEAM,  REFLECT,      \
	     BIDE,         SWIFT,        REST,         THUNDER_WAVE, SUBSTITUTE,   \
	     FLASH
	; end

	db BANK(MagnezonePicFront) ; pic bank
