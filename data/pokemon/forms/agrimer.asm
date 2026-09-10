; Alolan Grimer - GRIMER form 1.
;
; Poison/Dark. SECONDARY Dark is DROPPED per the type rules, leaving
; POISON/POISON, same as vanilla Grimer.
; Special split: modern SpA 40 / SpD 50, take the HIGHER -> spc 50.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Grimer.
	form_record GRIMER, 1

	db DEX_GRIMER ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  80,  80,  50,  25,  50
	;   hp  atk  def  spd  spc

	db POISON, POISON ; type
	db 190 ; catch rate
	db 90 ; base exp

	INCBIN "gfx/pokemon/front/agrimer.pic", 0, 1 ; sprite dimensions
	dw AGrimerPicFront, AGrimerPicBack

	db POUND, DISABLE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    RAGE,         MEGA_DRAIN,   THUNDERBOLT,  \
	     THUNDER,      MIMIC,        DOUBLE_TEAM,  BIDE,         SELFDESTRUCT, \
	     FIRE_BLAST,   REST,         EXPLOSION,    SUBSTITUTE,   FLAMETHROWER
	; end

	db BANK(AGrimerPicFront) ; pic bank

	dname "A-GRIMER"

	form_end
