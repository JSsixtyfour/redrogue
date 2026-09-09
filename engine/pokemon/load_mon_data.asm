LoadMonData_::
; Load monster [hWhichPokemon] from list [wMonDataLocation]:
;  0: partymon
;  1: enemymon
;  2: boxmon
;  3: daycaremon
; Return monster id at wCurPartySpecies and its data at wLoadedMon.
; Also load base stats at wMonHeader for convenience.
    ld a, [wMonDataLocation]
    cp DAYCARE_DATA2
	
    jr nz, .DayCare1check
	ld a, [wDayCareMon2Species]
    ld [wCurPartySpecies], a
    jp .GetMonHeader
    
    .DayCare1check
    ld a, [wDayCareMonSpecies]
	ld [wCurPartySpecies], a
	ld a, [wMonDataLocation]
	cp DAYCARE_DATA
	jr z, .GetMonHeader

	ldh a, [hWhichPokemon]
	ld e, a
	callfar GetMonSpecies

.GetMonHeader
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a

; Species Groups Phase 2R: the `call GetMonHeader` USED TO BE HERE, before the
; source struct was even located. That is too early for a form clone - the form
; index lives in the mon's own MON_CATCH_RATE, so the struct has to be found
; before the header can be loaded correctly. The struct-location block below was
; therefore moved ABOVE the header load; the copy itself still happens last, so
; this routine's tail call and its register state on return are unchanged.
;
; This is the highest-traffic GetMonHeader call site in the game - party, enemy,
; box and daycare all route through here - which is why it is the first site
; wired for forms and why the reorder was kept as small as possible.

	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	ld a, [wMonDataLocation]
	cp ENEMY_PARTY_DATA
	jr c, .getMonEntry

	ld hl, wEnemyMons
	jr z, .getMonEntry

	cp BOX_DATA
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH
	jr z, .getMonEntry

    cp DAYCARE_DATA2
    jr nz, .DayCare1copy
    ld hl, wDayCareMon2
	jr .haveStruct

    .DayCare1copy
	ld hl, wDayCareMon
	jr .haveStruct

.getMonEntry
	ldh a, [hWhichPokemon]
	call AddNTimes

.haveStruct
; hl = the source struct. Publish this mon's form context, then load the header.
; Publishing UNCONDITIONALLY, form 0 included, is the point: ApplyFormOverride
; consumes the context on read, so a slot with no form actively clears whatever
; the previous slot published. That is what stops a party menu walking an Alolan
; Meowth in slot 1 and a vanilla Meowth in slot 2 from rendering both as Alolan.
	push hl
	call PublishFormContext ; hl = struct base; HOME, see home/pokemon.asm
	call GetMonHeader       ; preserves hl, but the struct pointer is popped
	pop hl                  ; below defensively - this is the register-contract
	                        ; bug class that has bitten this project repeatedly

.copyMonData
	ld de, wLoadedMon
	ld bc, PARTYMON_STRUCT_LENGTH
	jp CopyData
