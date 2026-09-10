; Toedscool - TENTACOOL form 1.
;
; Paired with Tentacool ('land Tentacool'): Ground/Grass, both valid Gen 1
; types.
; Special split: modern SpA 50 / SpD 100, take the HIGHER -> spc 100.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tentacool, same
; as the Espeon precedent.
	form_record TENTACOOL, 1

	db DEX_TENTACOOL ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  40,  40,  35,  70, 100
	;   hp  atk  def  spd  spc

	db GROUND, GRASS ; type
	db 190 ; catch rate
	db 105 ; base exp

	INCBIN "gfx/pokemon/front/toedscool.pic", 0, 1 ; sprite dimensions
	dw ToedscoolPicFront, ToedscoolPicBack

	db ACID, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     RAGE,         MEGA_DRAIN,   \
	     MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         SKULL_BASH,   \
	     REST,         SUBSTITUTE,   CUT,          SURF
	; end

	db BANK(ToedscoolPicFront) ; pic bank

	dname "TOEDSCOOL"

	form_end
