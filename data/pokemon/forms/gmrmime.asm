; Galarian Mr. Mime - MR_MIME form 1.
;
; Ice/Psychic, both valid Gen 1 types.
; Stats: Mr. Mime's with speed and special swapped (user decision 2026-10-27).
; Level-1 moves, growth, catch rate, base exp and tmhm follow Mr. Rime, its
; evolution; the level-up learnset is in form_evos_moves/gmrmime.asm.
	form_record MR_MIME, 1

	db DEX_MR_MIME ; pokedex id (documentation only - GetMonHeader overwrites
	              ; byte 0 with the species index right after the patch)

	db  40,  45,  65, 100,  90
	;   hp  atk  def  spd  spc

	db ICE, PSYCHIC_TYPE ; type
	db 45 ; catch rate
	db 136 ; base exp

	INCBIN "gfx/pokemon/front/gmrmime.dim" ; sprite dimensions
	dw GMrMimePicFront, GMrMimePicBack

	db CONFUSION, BARRIER, REFLECT, NO_MOVE ; level 1 learnset
	db GROWTH_MEDIUM_FAST ; growth rate

	; tm/hm learnset - Mr. Rime's
	tmhm MEGA_PUNCH,   LIGHT_SCREEN, MEGA_KICK,    TOXIC,        BODY_SLAM,    \
	     TAKE_DOWN,    DOUBLE_EDGE,  ICE_BEAM,     BLIZZARD,     HYPER_BEAM,   \
	     SUBMISSION,   COUNTER,      SEISMIC_TOSS, RAGE,         SOLARBEAM,    \
	     THUNDERBOLT,  THUNDER,      PSYCHIC_M,    MIMIC,        DOUBLE_TEAM,  \
	     REFLECT,      BIDE,         METRONOME,    SKULL_BASH,   REST,         \
	     THUNDER_WAVE, PSYWAVE,      SUBSTITUTE,   FLASH
	; end

	db BANK(GMrMimePicFront) ; pic bank

	dname "G-MRMIME"

	form_end PAL_CYANMON
