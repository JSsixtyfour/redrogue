; Same bank as grove. Seven saved padding bytes, schema 17.
OptionalEncounterClear::
	xor a
	ld hl, wOptionalEncounterSpecies
	ld bc, 7
	jp FillMemory

; Release has no occurrence roll yet. Debug 2 forces the test fixture.
OptionalForestFixture::
	call OptionalEncounterClear
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	ret z
	jp OptionalForcePink
ENDC
	ret

OptionalForcePink::
	call OptionalEncounterClear
	farcall PCGetBossLevel
	ld a, [wCurEnemyLevel]
	push af
	call GetRunProgress
	cp ROUND_BATTLES + 1 ; through first leader: -1, later: -2
	jr c, .one
	pop af
	dec a
	jr z, .minimum
	jr .reduce
.one
	pop af
.reduce
	dec a
	jr nz, .level
.minimum
	ld a, 1
.level
	ld [wOptionalEncounterLevel], a
	ld a, BUTTERFREE
	ld [wOptionalEncounterSpecies], a
	ld a, 1
	ld [wOptionalEncounterPackage], a
	ld a, PROCEDURAL_FOREST_GROTTO
	ld [wOptionalEncounterMap], a
	ret

OptionalEncounterPatchSprite::
	call FGHasAssignedEncounter
	and a
	ld a, 0
	jr z, .store
	ld a, [wOptionalEncounterState]
	bit 2, a
	ld a, 0
	jr nz, .store
	ld a, SPRITE_MONSTER
.store
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; EngageMapTrainer OW_POKEMON seam. Carry means this owns the request.
OptionalEncounterEngage::
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .no
	call FGHasAssignedEncounter
	and a
	jr z, .no
	ld a, [wOptionalEncounterState]
	and %110
	jr nz, .no
	xor a
	ld [wSpawnForm], a
	ld a, [wOptionalEncounterSpecies]
	ld [wEngagedTrainerClass], a
	ld a, [wOptionalEncounterLevel]
	ld [wEngagedTrainerSet], a ; includes true level >127
	ld a, 1
	ld [wOptionalEncounterBattle], a
	scf
	ret
.no
	and a
	ret

; After the ordinary catch-rate clear. e = flags byte. Consume even rejected
; requests; map/species/package guard prevents leakage into other battles.
OptionalEncounterEnemyFlags::
	push bc
	push hl
	ld a, [wOptionalEncounterBattle]
	ld b, a
	xor a
	ld [wOptionalEncounterBattle], a
	ld a, b
	and a
	jr z, .done
	ldh a, [hIsInBattle]
	cp 1
	jr nz, .done
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .done
	call FGHasAssignedEncounter
	and a
	jr z, .done
	ld a, [wEnemyMonSpecies]
	ld hl, wOptionalEncounterSpecies
	cp [hl]
	jr nz, .done
	set BIT_SPECIAL_FORM, e
.done
	pop hl
	pop bc
	ret

; GivePokemon carry required. Existing helper locates actual party/box gift.
OptionalEncounterFinalizeGift::
	ld e, BRIDGE_MON_FINALIZE_SPECIAL
	farcall BridgeFinalizeGiftMonFar
	ret

; Existing battle-item gate calls here only in an ordinary active battle.
; A failed capture request consumes neither the ball nor the player's turn.
OptionalEncounterCaptureGate::
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .no
	ld a, [wCurItem]
	cp SAFARI_BALL
	jr z, .reject
	cp POKE_BALL + 1
	jr nc, .no
.reject
	xor a
	ld [wActionResultOrTookBattleTurn], a
	ld hl, .text
	call PrintText
	scf
	ret
.no
	and a
	ret
.text
	text "Win its trust!"
	prompt
