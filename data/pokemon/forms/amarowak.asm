; Alolan Marowak - MAROWAK form 1.
;
; Fire/Ghost, both valid Gen 1 types, so no type-drop rule applies.
; Special split: modern SpA 50 / SpD 80, take the HIGHER -> spc 80.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Marowak.
	form_record MAROWAK, 1

	db DEX_MAROWAK ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  60,  80, 110,  45,  80
	;   hp  atk  def  spd  spc

	db FIRE, GHOST ; type
	db 75 ; catch rate
	db 124 ; base exp

	INCBIN "gfx/pokemon/front/amarowak.pic", 0, 1 ; sprite dimensions
	dw AMarowakPicFront, AMarowakPicBack

	db BONE_CLUB, GROWL, LEER, FOCUS_ENERGY ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  BUBBLEBEAM,   WATER_GUN,    ICE_BEAM,     BLIZZARD,     \
	     HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         FIRE_BLAST,   SKULL_BASH,   REST,         SUBSTITUTE,   \
	     STRENGTH,     FLAMETHROWER
	; end

	db BANK(AMarowakPicFront) ; pic bank

	dname "A-MAROWAK"

	form_end
