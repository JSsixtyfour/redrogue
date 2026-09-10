; Sandy Shocks - MAGNETON form 1.
;
; Paired with Magneton (paradox 'ancient Magneton'): Electric/Ground, both
; valid Gen 1 types.
; Special split: modern SpA 85 / SpD 65, take the HIGHER -> spc 85.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Magneton, same
; as the Espeon precedent (data/pokemon/forms/espeon.asm).
	form_record MAGNETON, 1

	db DEX_MAGNETON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  85,  63,  85,  87,  85
	;   hp  atk  def  spd  spc

	db ELECTRIC, GROUND ; type
	db 60 ; catch rate
	db 161 ; base exp

	INCBIN "gfx/pokemon/front/sandyshocks.pic", 0, 1 ; sprite dimensions
	dw SandyShocksPicFront, SandyShocksPicBack

	db TACKLE, SONICBOOM, THUNDERSHOCK, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     THUNDERBOLT,  THUNDER,      LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SWIFT,        REST,         THUNDER_WAVE, \
	     SUBSTITUTE,   FLASH
	; end

	db BANK(SandyShocksPicFront) ; pic bank

	dname "SANDSHOCKS"

	form_end
