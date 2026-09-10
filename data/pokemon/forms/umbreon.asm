; Umbreon - JOLTEON form 2 (form 1 is Espeon, see espeon.asm).
;
; Dark (single type). PRIMARY Dark becomes NORMAL. Paired with Jolteon per the
; plan's stat-shape pairing.
; Special split: modern SpA 60 / SpD 130, take the HIGHER -> spc 130.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Jolteon, same
; as the Espeon precedent.
	form_record JOLTEON, 2

	db DEX_JOLTEON ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  95,  65, 110,  65, 130
	;   hp  atk  def  spd  spc

	db NORMAL, NORMAL ; type
	db 45 ; catch rate
	db 197 ; base exp

	INCBIN "gfx/pokemon/front/umbreon.pic", 0, 1 ; sprite dimensions
	dw UmbreonPicFront, UmbreonPicBack

	db TACKLE, SAND_ATTACK, QUICK_ATTACK, THUNDERSHOCK ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         THUNDERBOLT,  THUNDER,      MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         SWIFT,        SKULL_BASH,   REST,         \
	     THUNDER_WAVE, SUBSTITUTE,   FLASH
	; end

	db BANK(UmbreonPicFront) ; pic bank

	dname "UMBREON"

	form_end
