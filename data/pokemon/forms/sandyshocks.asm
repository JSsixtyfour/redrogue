; Sandy Shocks - MAGNETON form 1.
;
; Paired with Magneton (paradox 'ancient Magneton'): Electric/Ground, both
; valid Gen 1 types.

	form_record MAGNETON, 1

	db DEX_MAGNETON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  85,  81,  97,  101,  121
	;   hp  atk  def  spd  spc

	db ELECTRIC, GROUND ; type
	db 60 ; catch rate
	db 211 ; base exp

	INCBIN "gfx/pokemon/front/sandyshocks.dim" ; sprite dimensions
	dw SandyShocksPicFront, SandyShocksPicBack

	db TACKLE, SUPERSONIC, SAND_ATTACK, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     THUNDERBOLT,  THUNDER,      LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SWIFT,        REST,         THUNDER_WAVE, \
	     SUBSTITUTE,   FLASH,        BODY_SLAM,    EARTHQUAKE,   DIG,		   \
		 FISSURE
	; end

	db BANK(SandyShocksPicFront) ; pic bank

	dname "SANDSHOCKS"

	form_end PAL_BROWNMON
