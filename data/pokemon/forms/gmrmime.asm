; Galarian Mr. Mime - MR_MIME form 1.
;
; Ice/Psychic, both valid Gen 1 types.
; Special split: modern SpA 90 / SpD 90, tie either way -> spc 90.
; Moves/growth/catch rate/base exp/tmhm copied verbatim from Mr. Mime.
	form_record MR_MIME, 1

	db DEX_MR_MIME ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  50,  65,  65, 100,  90
	;   hp  atk  def  spd  spc

	db ICE, PSYCHIC_TYPE ; type
	db 45 ; catch rate
	db 136 ; base exp

	INCBIN "gfx/pokemon/front/gmrmime.pic", 0, 1 ; sprite dimensions
	dw GMrMimePicFront, GMrMimePicBack

	db CONFUSION, BARRIER, NO_MOVE, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset
	tmhm MEGA_PUNCH,   MEGA_KICK,    TOXIC,        BODY_SLAM,    TAKE_DOWN,    \
	     DOUBLE_EDGE,  HYPER_BEAM,   SUBMISSION,   COUNTER,      SEISMIC_TOSS, \
	     RAGE,         SOLARBEAM,    THUNDERBOLT,  THUNDER,      PSYCHIC_M,    \
	     LIGHT_SCREEN, MIMIC,        DOUBLE_TEAM,  REFLECT,      BIDE,         \
	     METRONOME,    SKULL_BASH,   REST,         THUNDER_WAVE, PSYWAVE,      \
	     SUBSTITUTE,   FLASH
	; end

	db BANK(GMrMimePicFront) ; pic bank

	dname "G-MRMIME"

	form_end
