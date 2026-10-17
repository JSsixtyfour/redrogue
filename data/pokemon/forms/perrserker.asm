; Perrserker - PERSIAN form 2 (form 1 is Alolan, see apersian.asm).
;
; Steel (single type). PRIMARY Steel becomes ROCK per the type rules.
; 
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Persian.
	form_record PERSIAN, 2

	db DEX_PERSIAN ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65, 110, 100,  50,  50
	;   hp  atk  def  spd  spc

	db ROCK, ROCK ; type
	db 90 ; catch rate
	db 148 ; base exp

	INCBIN "gfx/pokemon/front/perrserker.dim" ; sprite dimensions
	dw PerrserkerPicFront, PerrserkerPicBack

	db SCRATCH, GROWL, BITE, SCREECH ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    HYPER_BEAM,   PAY_DAY,      RAGE,         THUNDERBOLT,  \
	     THUNDER,      MIMIC,        DOUBLE_TEAM,  BIDE,         SWORDS_DANCE, \
	     SKULL_BASH,   REST,         SUBSTITUTE,   ROCK_SLIDE,   DIG
	; end

	db BANK(PerrserkerPicFront) ; pic bank

	dname "PERRSERKER"

	form_end PAL_GRAYMON
