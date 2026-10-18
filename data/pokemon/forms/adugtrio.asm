; Alolan Dugtrio - DUGTRIO form 1.
;
; Added during increment 2 specifically because the DEBUG party's slot 4 is
; already a Dugtrio (Exeggutor / Mew / Jolteon / DUGTRIO / Articuno / Pikachu,
; see engine/debug/debug_party.asm). That makes the whole form path testable by
; poking ONE byte - the mon's MON_CATCH_RATE - with no species surgery.
;
; Transcription rules applied:
;  - Alolan Dugtrio is Ground/Steel. SECONDARY Steel is DROPPED, leaving
;    GROUND/GROUND, which is what vanilla Dugtrio already is.
;  - Special split: modern SpA 50 / SpD 70, take the HIGHER -> spc 70.
;  - DEF 50 -> 60 and SPD 120 -> 110 are the only stat differences from vanilla
;    Dugtrio. Modern ATK 100 is kept at Dugtrio's 80 so the total matches 355.
;  - Base exp and catch rate kept at Dugtrio's.
	form_record DUGTRIO, 1

	db DEX_DUGTRIO ; pokedex id (documentation only - GetMonHeader overwrites
	               ; byte 0 with the species index right after the patch)

	db  35, 80,  60, 110,  70
	;   hp  atk  def  spd  spc

	db GROUND, GROUND ; type (secondary Steel dropped per the type rules)
	db 50 ; catch rate
	db 153 ; base exp

	INCBIN "gfx/pokemon/front/adugtrio.dim" ; sprite dimensions
	dw ADugtrioPicFront, ADugtrioPicBack

	db SCRATCH, GROWL, DIG, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  HYPER_BEAM,   \
	     RAGE,         EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        \
	     DOUBLE_TEAM,  BIDE,         REST,         ROCK_SLIDE,   SUBSTITUTE
	; end

	db BANK(ADugtrioPicFront) ; pic bank

	dname "A-DUGTRIO"

	form_end PAL_BROWNMON
