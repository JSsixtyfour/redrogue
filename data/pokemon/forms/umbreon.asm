; Umbreon - JOLTEON form 2 (form 1 is Espeon, see espeon.asm).
;
; Dark (single type). PRIMARY Dark becomes NORMAL. Paired with Jolteon per the
; plan's stat-shape pairing.
; Special split: modern SpA 60 / SpD 130, take the HIGHER -> spc 130.

	form_record JOLTEON, 2

	db DEX_JOLTEON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65, 60, 110,  65,  130
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 197 ; base exp

	INCBIN "gfx/pokemon/front/umbreon.dim" ; sprite dimensions
	dw UmbreonPicFront, UmbreonPicBack

	db BITE, SAND_ATTACK, QUICK_ATTACK, GROWL ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         LIGHT_SCREEN,  CUT,      MIMIC,        DOUBLE_TEAM,     \
	     REFLECT,      BIDE,         SWIFT,        SKULL_BASH,   REST,         \
	     THUNDER_WAVE, SUBSTITUTE,   FLASH,        DIG,          PSYCHIC_M,	   \
		 DREAM_EATER												    \
	; end

	db BANK(UmbreonPicFront) ; pic bank

	dname "UMBREON"

	form_end PAL_MEWMON
