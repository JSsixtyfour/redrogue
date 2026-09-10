; Alolan Diglett - DIGLETT form 1.
;
; Added so Diglett's Cave becomes a one-species test bed for the enemy-side form
; seam: with wSpawnForm set, essentially every wild encounter there is a form.
; Diglett is one of the 18 Alolan variants on the roster regardless, so this is
; roster work, not scaffolding.
;
; Transcription rules applied:
;  - Alolan Diglett is Ground/Steel. SECONDARY Steel is DROPPED, leaving
;    GROUND/GROUND, which vanilla Diglett already is.
;  - Special split: modern SpA 45 / SpD 45, tie, so spc 45 either way.
;  - DEF 25 -> 30 and SPD 95 -> 90 are the only stat differences, both small.
;    The SPRITE is the tell here (Alolan Diglett's golden hair), not the numbers.
;  - Catch rate and base exp kept at Diglett's.
	form_record DIGLETT, 1

	db DEX_DIGLETT ; pokedex id (documentation only - GetMonHeader overwrites
	               ; byte 0 with the species index right after the patch)

	db  10,  55,  30,  90,  45
	;   hp  atk  def  spd  spc

	db GROUND, GROUND ; type (secondary Steel dropped per the type rules)
	db 255 ; catch rate
	db 81 ; base exp

	INCBIN "gfx/pokemon/front/adiglett.pic", 0, 1 ; sprite dimensions
	dw ADiglettPicFront, ADiglettPicBack

	db SCRATCH, NO_MOVE, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  RAGE,         \
	     EARTHQUAKE,   FISSURE,      DIG,          MIMIC,        DOUBLE_TEAM,  \
	     BIDE,         REST,         ROCK_SLIDE,   SUBSTITUTE
	; end

	db BANK(ADiglettPicFront) ; pic bank

	dname "A-DIGLETT"

	form_end
