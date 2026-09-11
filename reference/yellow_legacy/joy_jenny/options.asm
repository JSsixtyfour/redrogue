; Yellow Legacy YL-6B dormant reference package.
; This file intentionally contains comments only and is not included by main.asm.
; Donor: cRz-Shadows/Pokemon_Yellow_Legacy
; Revision: 15169d137e2ef778e8765f7f3381acc4093dc169
;
; PORTRAIT OPTIONS, deliberately inactive
; JoyPic::  INCBIN "gfx/trainers/joy.pic"
; JennyPic:: INCBIN "gfx/trainers/jenny.pic"
;
; PARTY OPTIONS, exact donor records
; JoyData:
; 	db 65, KANGASKHAN, SNORLAX, STARMIE, PORYGON, EXEGGUTOR, CHANSEY, 0
; JennyData:
; 	db 65, PIDGEOT, BLASTOISE, TANGELA, GENGAR, PARASECT, ARCANINE, 0
;
; SPECIAL MOVE OPTION: JOY, exact donor slot overrides
; 	db JOY, 1
; 	db 1, 1, REST
; 	db 1, 2, DOUBLE_TEAM
; 	db 1, 3, FISSURE
; 	db 2, 2, ICE_BEAM
; 	db 2, 3, AMNESIA
; 	db 2, 4, DOUBLE_TEAM
; 	db 3, 1, RECOVER
; 	db 3, 3, THUNDER_WAVE
; 	db 3, 4, SUBSTITUTE
; 	db 4, 1, REFLECT
; 	db 4, 2, BLIZZARD
; 	db 4, 3, RECOVER
; 	db 4, 4, THUNDER_WAVE
; 	db 5, 1, SOFTBOILED
; 	db 5, 2, REFLECT
; 	db 5, 3, DREAM_EATER
; 	db 6, 1, SOFTBOILED
; 	db 6, 2, REFLECT
; 	db 6, 3, EGG_BOMB
; 	db 6, 4, THUNDER_WAVE
; 	db 0
;
; SPECIAL MOVE OPTION: JENNY, exact donor slot overrides
; 	db JENNY, 1
; 	db 1, 1, TAKE_DOWN
; 	db 1, 4, TOXIC
; 	db 2, 1, SURF
; 	db 2, 2, EARTHQUAKE
; 	db 2, 4, BODY_SLAM
; 	db 3, 2, SLEEP_POWDER
; 	db 3, 3, MIMIC
; 	db 4, 1, PSYCHIC_M
; 	db 4, 4, THUNDERBOLT
; 	db 5, 4, LEECH_LIFE
; 	db 6, 1, REFLECT
; 	db 6, 2, FIRE_BLAST
; 	db 6, 3, BODY_SLAM
; 	db 6, 4, DIG
; 	db 0
;
; DONOR JOY LIFECYCLE OPTION, adapt rather than paste
; 1. Run the normal healing service first.
; 2. Test donor wGameStage and EVENT_BEAT_NURSE_JOY.
; 3. Offer the challenge with YesNoChoice.
; 4. Set OPP_JOY / trainer 1 and a post-battle map script.
; 5. On a win, set EVENT_BEAT_NURSE_JOY and print post-battle text.
; 6. On a loss, skip the win event and restore the default map script.
;
; DONOR JENNY LIFECYCLE OPTION, adapt rather than paste
; 1. Preserve the pre-battle Squirtle gift behavior.
; 2. After the gift, test donor wGameStage.
; 3. Offer the challenge with YesNoChoice.
; 4. Set OPP_JENNY / trainer 1 and a post-battle map script.
; 5. Donor rematches are enabled because its EVENT_BEAT_JENNY gate is commented.
;
; RED ROGUE ACTIVATION PLACEHOLDERS, deliberately unresolved
; INCLUDE "reference/yellow_legacy/joy_jenny/options.asm"
; const JOY
; const JENNY
; dw JoyData
; dw JennyData
; dwbank JoyPic
; dwbank JennyPic
