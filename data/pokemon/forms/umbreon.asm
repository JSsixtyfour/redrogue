; Umbreon - JOLTEON form 2 (form 1 is Espeon, see espeon.asm).
;
; Dark (single type). PRIMARY Dark becomes NORMAL. Paired with Jolteon per the
; plan's stat-shape pairing.
; Stats follow the Gen 1 eeveelution rule, not the modern split: every Gen 1
; eeveelution rearranges one shared pool of 130 / 110 / 65 / 65 / 60
; (Vaporeon puts 130 in HP, Jolteon in Speed, Flareon in Attack, with 110 as
; Special). Umbreon's stats and role don't translate well to Gen 1. It could
; put 130 in Special and 110 in Defense, but that is the same shape as Glaceon.
; To give it a unique spread, which it probably would have had, while keeping
; its tank role, the 130 goes in HP instead: a physical tank with meh special
; walling. Total 430 like the others. Modern HP 95 is not in the pool.

	form_record JOLTEON, 2

	db DEX_JOLTEON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  130, 60, 110,  65,  65
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
	     RAGE,         LIGHT_SCREEN, CUT,          DIG,          MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         SWIFT,        SKULL_BASH,   \
	     REST,         THUNDER_WAVE, SUBSTITUTE,   FLASH,        PSYCHIC_M,    \
	     DREAM_EATER
	; end

	db BANK(UmbreonPicFront) ; pic bank

	dname "UMBREON"

	form_end PAL_MEWMON
