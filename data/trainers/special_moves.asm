; Yellow entry format:
;	db trainerclass, trainerid
;	repeat { db partymon location, partymon move, move id }
;	db 0

SpecialTrainerMoves:
	db BROCK, 1
	db 2, 3, BIDE ;Onix has bide in the third slot
	db 0

	db MISTY, 1
	db 2, 3, BUBBLEBEAM ;Starmie has Bubblebeam in the third slot
	db 0

	db LT_SURGE, 1
	db 3, 3, THUNDERBOLT ;Raichu has Thunderbolt in the third slot
	db 0

	db ERIKA, 1
	db 3, 3, MEGA_DRAIN ;Vileplume has Mega Drain in the third slot
	db 0

	db KOGA, 1
	db 4, 3, TOXIC ;Weezing has Toxic in the third slot
	db 0

	db BLAINE, 1
	db 4, 3, FIRE_BLAST ; Arcanine has Fire Blast in the third slot
	db 0

	db SABRINA, 1
	db 4, 3, PSYWAVE ; Alakazam has Psywave in the third slot
	db 0

	db GIOVANNI, 3
	db 5, 3, FISSURE ; Rhydon has Fissure in the third slot
	db 0

; LORELEI / BRUNO / AGATHA / LANCE wTrainerNo 1 and RIVAL3 wTrainerNo 1-3
; rows removed (Trainer Revamp, 2026-09-23). Those numbers now reach a party
; spec whose teams are rolled from a pool, so a slot-addressed move would land
; on whatever species rolled there - Barrier on a random slot-5 Lance mon,
; Blizzard on the rival's Charizard. The spec's own moveset mix covers them.

; Phase 7f: donor move records from reference/yellow_legacy/joy_jenny/options.asm
; (cRz-Shadows/Pokemon_Yellow_Legacy), kept verbatim - only the trainer id
; changed. wTrainerNo 9 is the stage event's final round tier, the one place
; the built team is guaranteed the donor's original six mons, so these are
; flavour for that tier rather than a fixed team: whatever six species the
; round-9 pool rolls receives these moves in these slots, same as every other
; SpecialTrainerMoves entry in this file.
	db NURSE_JOY, 9
	db 1, 1, REST
	db 1, 2, DOUBLE_TEAM
	db 1, 3, FISSURE
	db 2, 2, ICE_BEAM
	db 2, 3, AMNESIA
	db 2, 4, DOUBLE_TEAM
	db 3, 1, RECOVER
	db 3, 3, THUNDER_WAVE
	db 3, 4, SUBSTITUTE
	db 4, 1, REFLECT
	db 4, 2, BLIZZARD
	db 4, 3, RECOVER
	db 4, 4, THUNDER_WAVE
	db 5, 1, SOFTBOILED
	db 5, 2, REFLECT
	db 5, 3, DREAM_EATER
	db 6, 1, SOFTBOILED
	db 6, 2, REFLECT
	db 6, 3, EGG_BOMB
	db 6, 4, THUNDER_WAVE
	db 0

	db OFFICER_JENNY, 9
	db 1, 1, TAKE_DOWN
	db 1, 4, TOXIC
	db 2, 1, SURF
	db 2, 2, EARTHQUAKE
	db 2, 4, BODY_SLAM
	db 3, 2, SLEEP_POWDER
	db 3, 3, MIMIC
	db 4, 1, PSYCHIC_M
	db 4, 4, THUNDERBOLT
	db 5, 4, LEECH_LIFE
	db 6, 1, REFLECT
	db 6, 2, FIRE_BLAST
	db 6, 3, BODY_SLAM
	db 6, 4, DIG
	db 0

	db -1 ; end