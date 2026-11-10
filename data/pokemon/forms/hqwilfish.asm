; Hisuian Qwilfish - QWILFISH form 1 (form 2 is Overqwil, see overqwil.asm).
;
; Dark/Poison. PRIMARY Dark becomes NORMAL per the type rules; secondary
; Poison is unaffected.
; Stats, catch rate, base exp, level-1 moves, growth and tmhm copied verbatim
; from Qwilfish (design choice: same numbers, new typing and learnset).
; Evolves into Overqwil at level 30 (form_evos_moves/hqwilfish.asm).
	form_record QWILFISH, 1

	db DEX_QWILFISH ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  65,  95,  75,  85,  55
	;   hp  atk  def  spd  spc

	db NORMAL, POISON ; type
	db 45 ; catch rate
	db 100 ; base exp

	INCBIN "gfx/pokemon/front/hqwilfish.dim" ; sprite dimensions
	dw HQwilfishPicFront, HQwilfishPicBack

	db TACKLE, POISON_STING, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm SWORDS_DANCE, TOXIC,        TAKE_DOWN,    DOUBLE_EDGE,  BUBBLEBEAM,   \
	     WATER_GUN,    ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   RAGE,         \
	     THUNDER_WAVE, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     SWIFT,        REST,         SUBSTITUTE,   SURF,         SELFDESTRUCT, \
	     EXPLOSION,    BODY_SLAM
	; end

	db BANK(HQwilfishPicFront) ; pic bank

	dname "H-QWILFISH"

	form_end PAL_PURPLEMON
