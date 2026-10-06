; Joint quotas without a hard cooldown. All public entries are farcalled;
; this section has no raw pointers/calls into the rogue bank.
SECTION "Special Encounter Policy", ROMX, BANK[$2E]

; e = eligible kinds (bits 0/1), mandatory (bit 2), both doors special (bit 3).
; One of each before gym 4; two of each before gym 8. Completed encounters
; alone satisfy a quota. Normal routes remain available until the joint
; deficit consumes every remaining route in this half.
SpecialEncounterPolicy::
	ld a, [wObtainedBadges]
	ld c, 0
	ld b, 8
.badges
	srl a
	jr nc, .nextBadge
	inc c
.nextBadge
	dec b
	jr nz, .badges
	ld e, 0
	ld a, c
	and a
	ret z ; opening route
	cp 8
	ret nc ; final sequence
	ld b, 1
	ld d, 4
	cp 4
	jr c, .halfReady
	inc b
	ld d, 8
.halfReady
	ld h, 0 ; combined deficit
	ld a, [wMiniBossCount]
	ld l, a
	ld a, b
	sub l
	jr c, .miniDone
	jr z, .miniDone
	ld h, a
	set 0, e
.miniDone
	ld a, [wWildAreaState]
	and WILD_AREA_COUNT_MASK
	srl a
	srl a
	srl a
	ld l, a
	ld a, b
	sub l
	jr c, .wildDone
	jr z, .wildDone
	add h
	ld h, a
	set 1, e
.wildDone
	ld a, e
	and a
	ret z
	ld a, d
	sub c ; remaining route slots, including this selection
	cp h
	jr c, .mandatory
	jr z, .mandatory
	call SpecialChanceOccur
	jr nc, .none
	ld a, e
	cp 3
	ret nz
	; Occasionally offer both kinds; ordinary-route choices remain usual.
	push de
	call Random
	pop de
	cp 64
	ret nc
	set 3, e
	ret
.mandatory
	set 2, e
	ld a, e
	and 3
	cp 3
	ret nz
	set 3, e
	ret
.none
	ld e, 0
	ret

; Preserve the existing 25/50/75/100% curve. Offering a special does not
; reset it: a declined offer increases next time's pressure, too.
SpecialChanceOccur::
	ld a, [wRoutesSinceSpecial]
	cp 3
	jr nc, .yes
	inc a
	ld [wRoutesSinceSpecial], a
	swap a
	sla a
	sla a
	ld b, a
	push de
	call Random
	pop de
	cp b
	ret
.yes
	scf
	ret

; TrainerBattleVictory calls this only for non-procedural trainer wins.
; Ordinary trainers on a miniboss route do not satisfy its quota. Keep the
; active flag for reward rarity; the trainer's beaten event prevents re-fights.
RecordMiniBossVictory::
	ld a, [wObtainedBadges]
	cp $ff
	ret z ; Victory Road's static Rival is outside the scheduled quota
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_ACTIVE, a
	ret z
	ld a, [wTrainerClass]
	cp RIVAL_MINIBOSS
	jr z, .complete
	cp GIOVANNI_MINIBOSS
	jr z, .complete
	cp KARATE_MINIBOSS
	ret nz
.complete
	ld hl, wMiniBossCount
	ld a, [hl]
	cp MINIBOSS_MIN_PER_RUN
	ret nc
	inc [hl]
	xor a
	ld [wRoutesSinceSpecial], a
	ret

; Called from the existing LoadMapData dispatch, before lobby selection.
RecordStageMapLoad::
	farcall BridgeRecordVisit
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_CAVE_1
	jr z, .complete
	cp PROCEDURAL_FOREST
	jr z, .complete
	cp PROCEDURAL_FACILITY
	jr z, .complete
	cp PROCEDURAL_CEMETERY_4
	ret nz
.complete
	ld hl, wRogueFlagsBitfield
	bit BIT_ROGUE_GYM_NEXT, [hl]
	ret nz ; a subsequent lobby reload must not credit this exit twice
	set BIT_ROGUE_GYM_NEXT, [hl]
	ld a, [wBattleCount]
	add WILD_AREA_EXIT_BATTLES
	jr nc, .countReady
	ld a, $ff
.countReady
	ld [wBattleCount], a
	ld a, [wWildAreaState]
	and WILD_AREA_COUNT_MASK
	cp WILD_AREA_MIN_PER_RUN << WILD_AREA_COUNT_SHIFT
	jr nc, .resetPressure
	ld a, [wWildAreaState]
	add 1 << WILD_AREA_COUNT_SHIFT
	ld [wWildAreaState], a
.resetPressure
	xor a
	ld [wRoutesSinceSpecial], a
	ret
