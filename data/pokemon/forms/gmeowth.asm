; Galarian Meowth - MEOWTH form 2 (form 1 is Alolan, see ameowth.asm).
;
; Steel (single type in modern games). PRIMARY Steel becomes ROCK per the type
; rules.
; Special split: modern SpA 40 / SpD 40, tie either way -> spc 40.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Meowth.
	form_record MEOWTH, 2

	db DEX_MEOWTH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  50,  65,  55,  40,  40
	;   hp  atk  def  spd  spc

	db ROCK, ROCK ; type
	db 255 ; catch rate
	db 69 ; base exp

	INCBIN "gfx/pokemon/front/gmeowth.pic", 0, 1 ; sprite dimensions
	dw GMeowthPicFront, GMeowthPicBack

	db SCRATCH, GROWL, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm TOXIC,        BODY_SLAM,    TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    PAY_DAY,      RAGE,         THUNDERBOLT,  THUNDER,      \
	     MIMIC,        DOUBLE_TEAM,  BIDE,         SWIFT,        SKULL_BASH,   \
	     REST,         SUBSTITUTE
	; end

	db BANK(GMeowthPicFront) ; pic bank

	dname "G-MEOWTH"

	form_end
