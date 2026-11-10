; Overqwil - QWILFISH form 2, evolved from Hisuian Qwilfish (QWILFISH form 1)
; at level 30. A form that acts as a species (numbered dex row), the
; Honchkrow/Ursaluna pattern: species ids are full.
;
; Dark/Poison. PRIMARY Dark becomes NORMAL per the type rules; secondary
; Poison is unaffected.
; Stats: project values (HP 85 / Atk 115 / Def 95 / Spd 85 / Spc 65).
; Catch rate, base exp, level-1 moves, growth and tmhm copied from Qwilfish.
; Growth must match Hisuian Qwilfish's or evolving changes the level.
	form_record QWILFISH, 2

	db DEX_QWILFISH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  85, 115,  95,  85,  65
	;   hp  atk  def  spd  spc

	db NORMAL, POISON ; type
	db 45 ; catch rate
	db 100 ; base exp

	INCBIN "gfx/pokemon/front/overqwil.dim" ; sprite dimensions
	dw OverqwilPicFront, OverqwilPicBack

	db TACKLE, POISON_STING, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     THUNDER_WAVE, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         SUBSTITUTE,   SURF,         SELFDESTRUCT, \
	     EXPLOSION,    BODY_SLAM
	; end

	db BANK(OverqwilPicFront) ; pic bank

	dname "OVERQWIL"

	form_end PAL_PURPLEMON
