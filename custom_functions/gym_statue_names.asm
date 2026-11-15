; The gym statue's city and leader names (FOLLOWUPS #101).
;
; wGymCityName / wGymLeaderName are read only by _GymStatueText1/2. Every gym
; map script used to copy its names into them on every map-script tick (they
; are not saved, so a Continue inside a gym needed them rebuilt). The statue now
; loads them when it is read, from this one table, and the gym scripts no
; longer touch them.
;
; Pinned beside "Run Challenges" in $12, which has room; a new floating section
; would first-fit and could reshuffle other floaters (ROM_BIBLE).

SECTION "Gym Statue Names", ROMX, BANK[$12]

; Copies the current gym's names into wGymCityName / wGymLeaderName. A map with
; no row leaves the buffers alone (statues are bound only to gym maps).
; Clobbers af, bc, de, hl.
LoadGymStatueNames::
	ldh a, [hCurMap]
	cp FUCHSIA_GYM
	jr nz, .lookup
	farcall FuchsiaGymIsJanine ; Z = Janine leads Fuchsia this run; flags survive
	ld hl, GymStatueNames_FuchsiaCity
	ld de, GymStatueNames_Janine
	jp z, LoadGymLeaderAndCityName
	ldh a, [hCurMap]
.lookup
	ld c, a
	ld hl, GymStatueNameTable
.find
	ld a, [hli]
	cp $ff
	ret z
	cp c
	jr z, .found
	inc hl
	inc hl
	inc hl
	inc hl
	jr .find
.found
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a ; de = city
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = leader
	push hl
	ld h, d
	ld l, e
	pop de ; hl = city, de = leader, as LoadGymLeaderAndCityName takes them
	jp LoadGymLeaderAndCityName

GymStatueNameTable:
	db PEWTER_GYM
	dw GymStatueNames_PewterCity, GymStatueNames_Brock
	db CERULEAN_GYM
	dw GymStatueNames_CeruleanCity, GymStatueNames_Misty
	db VERMILION_GYM
	dw GymStatueNames_VermilionCity, GymStatueNames_LtSurge
	db CELADON_GYM
	dw GymStatueNames_CeladonCity, GymStatueNames_Erika
	db FUCHSIA_GYM
	dw GymStatueNames_FuchsiaCity, GymStatueNames_Koga
	db SAFFRON_GYM
	dw GymStatueNames_SaffronCity, GymStatueNames_Sabrina
	db CINNABAR_GYM
	dw GymStatueNames_CinnabarIsland, GymStatueNames_Blaine
	db VIRIDIAN_GYM
	dw GymStatueNames_ViridianCity, GymStatueNames_Giovanni
	db VIOLET_GYM
	dw GymStatueNames_VioletCity, GymStatueNames_Falkner
	db AZALEA_GYM
	dw GymStatueNames_AzaleaTown, GymStatueNames_Bugsy
	db GOLDENROD_GYM
	dw GymStatueNames_GoldenrodCity, GymStatueNames_Whitney
	db ECRUTEAK_GYM
	dw GymStatueNames_EcruteakCity, GymStatueNames_Morty
	db CIANWOOD_GYM
	dw GymStatueNames_CianwoodCity, GymStatueNames_Chuck
	db OLIVINE_GYM
	dw GymStatueNames_OlivineCity, GymStatueNames_Jasmine
	db MAHOGANY_GYM
	dw GymStatueNames_MahoganyTown, GymStatueNames_Pryce
	db BLACKTHORN_GYM
	dw GymStatueNames_BlackthornCity, GymStatueNames_Clair
	db $ff

; LoadGymLeaderAndCityName copies GYM_CITY_LENGTH / NAME_LENGTH bytes whatever
; the string length, exactly as it did from the gym scripts; the bytes after a
; terminator are never printed.
GymStatueNames_PewterCity:     db "PEWTER CITY@"
GymStatueNames_Brock:          db "BROCK@"
GymStatueNames_CeruleanCity:   db "CERULEAN CITY@"
GymStatueNames_Misty:          db "MISTY@"
GymStatueNames_VermilionCity:  db "VERMILION CITY@"
GymStatueNames_LtSurge:        db "LT.SURGE@"
GymStatueNames_CeladonCity:    db "CELADON CITY@"
GymStatueNames_Erika:          db "ERIKA@"
GymStatueNames_FuchsiaCity:    db "FUCHSIA CITY@"
GymStatueNames_Koga:           db "KOGA@"
GymStatueNames_Janine:         db "JANINE@"
GymStatueNames_SaffronCity:    db "SAFFRON CITY@"
GymStatueNames_Sabrina:        db "SABRINA@"
GymStatueNames_CinnabarIsland: db "CINNABAR ISLAND@"
GymStatueNames_Blaine:         db "BLAINE@"
GymStatueNames_ViridianCity:   db "VIRIDIAN CITY@"
GymStatueNames_Giovanni:       db "GIOVANNI@"
GymStatueNames_VioletCity:     db "VIOLET CITY@"
GymStatueNames_Falkner:        db "FALKNER@"
GymStatueNames_AzaleaTown:     db "AZALEA TOWN@"
GymStatueNames_Bugsy:          db "BUGSY@"
GymStatueNames_GoldenrodCity:  db "GOLDENROD CITY@"
GymStatueNames_Whitney:        db "WHITNEY@"
GymStatueNames_EcruteakCity:   db "ECRUTEAK CITY@"
GymStatueNames_Morty:          db "MORTY@"
GymStatueNames_CianwoodCity:   db "CIANWOOD CITY@"
GymStatueNames_Chuck:          db "CHUCK@"
GymStatueNames_OlivineCity:    db "OLIVINE CITY@"
GymStatueNames_Jasmine:        db "JASMINE@"
GymStatueNames_MahoganyTown:   db "MAHOGANY TOWN@"
GymStatueNames_Pryce:          db "PRYCE@"
GymStatueNames_BlackthornCity: db "BLACKTHORN CITY@"
GymStatueNames_Clair:          db "CLAIR@"
	; the last string must still be followed by NAME_LENGTH bytes of ROM to copy
	ds NAME_LENGTH - 1, 0
