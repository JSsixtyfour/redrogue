; Toedscruel - TENTACRUEL form 1.
;
; Paired with Tentacruel ('land Tentacruel'): Ground/Grass, both valid Gen 1
; types.
; Special split: modern SpA 80 / SpD 120, take the HIGHER -> spc 120.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Tentacruel, same
; as the Espeon precedent.
	form_record TENTACRUEL, 1

	db DEX_TENTACRUEL ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  80,  70,  65, 100, 120
	;   hp  atk  def  spd  spc

	db GROUND, GRASS ; type
	db 60 ; catch rate
	db 205 ; base exp

	INCBIN "gfx/pokemon/front/toedscruel.pic", 0, 1 ; sprite dimensions
	dw ToedscruelPicFront, ToedscruelPicBack

	db ACID, SUPERSONIC, WRAP, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     MEGA_DRAIN,   MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SKULL_BASH,   REST,         SUBSTITUTE,   CUT,          SURF
	; end

	db BANK(ToedscruelPicFront) ; pic bank

	dname "TOEDSCRUEL"

	form_end
