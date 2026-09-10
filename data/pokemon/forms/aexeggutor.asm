; Alolan Exeggutor - EXEGGUTOR form 1.
;
; Grass/Dragon; Dragon is a valid Gen 1 type so no type-drop rule applies here.
; Special split: modern SpA 125 / SpD 65, take the HIGHER -> spc 125.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Exeggutor.
	form_record EXEGGUTOR, 1

	db DEX_EXEGGUTOR ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  95, 107,  95,  45, 125
	;   hp  atk  def  spd  spc

	db GRASS, DRAGON ; type
	db 45 ; catch rate
	db 212 ; base exp

	INCBIN "gfx/pokemon/front/aexeggutor.pic", 0, 1 ; sprite dimensions
	dw AExeggutorPicFront, AExeggutorPicBack

	db BARRAGE, HYPNOSIS, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_SLOW ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   RAGE,         \
	     MEGA_DRAIN,   SOLARBEAM,    PSYCHIC_M,    LIGHT_SCREEN, MIMIC,        \
	     DOUBLE_TEAM,  REFLECT,      BIDE,         SELFDESTRUCT, EGG_BOMB,     \
	     REST,         PSYWAVE,      EXPLOSION,    SUBSTITUTE,   STRENGTH
	; end

	db BANK(AExeggutorPicFront) ; pic bank

	dname "AEXEGGUTOR"

	form_end
