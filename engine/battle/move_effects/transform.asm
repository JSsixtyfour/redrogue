TransformEffect_:
	ld hl, wBattleMonSpecies
	ld de, wEnemyMonSpecies
	ld bc, wEnemyBattleStatus3
	; bug: on enemy's turn, a is overloaded with hWhoseTurn,
	; before the check for INVULNERABLE
	ld a, [wEnemyBattleStatus1]
	ldh a, [hWhoseTurn]
	and a
	jr nz, .hitTest
; player's turn
	ld hl, wEnemyMonSpecies
	ld de, wBattleMonSpecies
	ld bc, wPlayerBattleStatus3
	ld [wPlayerMoveListIndex], a
	; bug: this should be target's BattleStatus1 (i.e. wEnemyBattleStatus1)
	ld a, [wPlayerBattleStatus1]
.hitTest
	bit INVULNERABLE, a ; is mon invulnerable to typical attacks? (fly/dig)
	                    ; this check doesn't work due to above bugs
	jp nz, .failed
	push hl
	push de
	push bc
	ld hl, wPlayerBattleStatus2
	ldh a, [hWhoseTurn]
	and a
	jr z, .transformEffect
	ld hl, wEnemyBattleStatus2
.transformEffect
; animation(s) played are different if target has Substitute up
	bit HAS_SUBSTITUTE_UP, [hl]
	push af
	ld hl, HideSubstituteShowMonAnim
	ld b, BANK(HideSubstituteShowMonAnim)
	call nz, Bankswitch
	ld a, [wOptions]
	add a
	ld hl, PlayCurrentMoveAnimation
	ld b, BANK(PlayCurrentMoveAnimation)
	jr nc, .gotAnimToPlay
	ld hl, AnimationTransformMon
	ld b, BANK(AnimationTransformMon)
.gotAnimToPlay
	call Bankswitch
	ld hl, ReshowSubstituteAnim
	ld b, BANK(ReshowSubstituteAnim)
	pop af
	call nz, Bankswitch
	pop bc
	ld a, [bc]
	set TRANSFORMED, a ; mon is now transformed
	ld [bc], a
	pop de
	pop hl
	push hl
; transform user into opposing Pokemon
; species
	ld a, [hl]
	ld [de], a
; type 1 and type 2
	ld bc, $5
	add hl, bc
	inc de
	inc de
	inc de
	inc de
	inc de
	ld bc, 2
	call CopyData
; Skip the catch rate byte - do NOT copy it. Vanilla lumped it into a single
; 7-byte "type 1, type 2, catch rate, moves" copy, but in this ROM
; MON_CATCH_RATE is a flag field (ghost / fusion / type variant / special form -
; see MON_CATCH_RATE_BITFIELD_PC.md), so copying it laundered flags between the
; two mons: a transformed Light Ball Pikachu / Thick Club Marowak lost its form
; for the rest of the battle, and an enemy Ditto that transformed into a flagged
; player mon inherited that mon's boosts. The user keeps its own byte instead.
; A preserved flag stays inert while transformed anyway, because the capability
; lookup (GetSpecialFormCaps) is keyed on the struct's species, which Transform
; has already overwritten with the target's.
	inc hl
	inc de
; moves
	ld bc, NUM_MOVES
	call CopyData
	ldh a, [hWhoseTurn]
	and a
	jr z, .next
; save enemy mon DVs at wTransformedEnemyMonOriginalDVs
	ld a, [de]
	ld [wTransformedEnemyMonOriginalDVs], a
	inc de
	ld a, [de]
	ld [wTransformedEnemyMonOriginalDVs + 1], a
	dec de
.next
; DVs
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hli]
	ld [de], a
	inc de
; Skip level and max HP
	inc hl
	inc hl
	inc hl
	inc de
	inc de
	inc de
; Attack, Defense, Speed, and Special stats
	ld bc, (NUM_STATS - 1) * 2
	call CopyData
	ld bc, wBattleMonMoves - wBattleMonPP
	add hl, bc ; ld hl, wBattleMonMoves
	ld b, NUM_MOVES
.copyPPLoop
; 5 PP for all moves
	ld a, [hli]
	and a
	jr z, .lessThanFourMoves
	ld a, 5
	ld [de], a
	inc de
	dec b
	jr nz, .copyPPLoop
	jr .copyStats
.lessThanFourMoves
; 0 PP for blank moves
	xor a
	ld [de], a
	inc de
	dec b
	jr nz, .lessThanFourMoves
.copyStats
; original (unmodified) stats and stat mods
	pop hl
	ld a, [hl]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, wEnemyMonUnmodifiedAttack
	ld de, wPlayerMonUnmodifiedAttack
	call .copyBasedOnTurn ; original (unmodified) stats
	ld hl, wEnemyMonStatMods
	ld de, wPlayerMonStatMods
	call .copyBasedOnTurn ; stat mods
	ld hl, TransformedText
	jp PrintText

.copyBasedOnTurn
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotStatsOrModsToCopy
	push hl
	ld h, d
	ld l, e
	pop de
.gotStatsOrModsToCopy
	ld bc, (NUM_STATS - 1) * 2
	jp CopyData

.failed
	ld hl, PrintButItFailedText_
	jp EffectCallBattleCore

TransformedText:
	text_far _TransformedText
	text_end

; SuperTransformEffect_ is a parallel copy of TransformEffect_ above, not a
; refactor of it - this is deliberate. It's a few dozen duplicated lines, but
; it means normal Transform (used by Mew, wild Ditto, AI trainers, etc.) is
; completely unaffected by this gift-mon-exclusive move; nothing here is
; shared, so nothing here can break it.
;
; The only difference from TransformEffect_: after every step Transform
; normally does (species/type/moves/DVs/stats/stat mods - note stat mods
; already include the target's current stage boosts/drops, e.g. a Swords
; Dance buff, since that's just how vanilla Transform works here), this also
; copies the target's current HP onto the user, clamped to the user's own
; max HP (max HP itself is never touched, same as vanilla Transform - the
; user's HP pool size doesn't change, just how much of it is "filled").
SuperTransformEffect_:
	ld hl, wBattleMonSpecies
	ld de, wEnemyMonSpecies
	ld bc, wEnemyBattleStatus3
	; bug: on enemy's turn, a is overloaded with hWhoseTurn,
	; before the check for INVULNERABLE
	ld a, [wEnemyBattleStatus1]
	ldh a, [hWhoseTurn]
	and a
	jr nz, .hitTest
; player's turn
	ld hl, wEnemyMonSpecies
	ld de, wBattleMonSpecies
	ld bc, wPlayerBattleStatus3
	ld [wPlayerMoveListIndex], a
	; bug: this should be target's BattleStatus1 (i.e. wEnemyBattleStatus1)
	ld a, [wPlayerBattleStatus1]
.hitTest
	bit INVULNERABLE, a ; is mon invulnerable to typical attacks? (fly/dig)
	                    ; this check doesn't work due to above bugs
	jp nz, .failed
	push hl
	push de
	push bc
	ld hl, wPlayerBattleStatus2
	ldh a, [hWhoseTurn]
	and a
	jr z, .transformEffect
	ld hl, wEnemyBattleStatus2
.transformEffect
; animation(s) played are different if target has Substitute up
	bit HAS_SUBSTITUTE_UP, [hl]
	push af
	ld hl, HideSubstituteShowMonAnim
	ld b, BANK(HideSubstituteShowMonAnim)
	call nz, Bankswitch
	ld a, [wOptions]
	add a
	ld hl, PlayCurrentMoveAnimation
	ld b, BANK(PlayCurrentMoveAnimation)
	jr nc, .gotAnimToPlay
	ld hl, AnimationTransformMon
	ld b, BANK(AnimationTransformMon)
.gotAnimToPlay
	call Bankswitch
	ld hl, ReshowSubstituteAnim
	ld b, BANK(ReshowSubstituteAnim)
	pop af
	call nz, Bankswitch
	pop bc
	ld a, [bc]
	set TRANSFORMED, a ; mon is now transformed
	ld [bc], a
	pop de
	pop hl
	push hl
; transform user into opposing Pokemon
; species
	ld a, [hl]
	ld [de], a
; type 1 and type 2
	ld bc, $5
	add hl, bc
	inc de
	inc de
	inc de
	inc de
	inc de
	ld bc, 2
	call CopyData
; Skip the catch rate byte - do NOT copy it. Vanilla lumped it into a single
; 7-byte "type 1, type 2, catch rate, moves" copy, but in this ROM
; MON_CATCH_RATE is a flag field (ghost / fusion / type variant / special form -
; see MON_CATCH_RATE_BITFIELD_PC.md), so copying it laundered flags between the
; two mons: a transformed Light Ball Pikachu / Thick Club Marowak lost its form
; for the rest of the battle, and an enemy Ditto that transformed into a flagged
; player mon inherited that mon's boosts. The user keeps its own byte instead.
; A preserved flag stays inert while transformed anyway, because the capability
; lookup (GetSpecialFormCaps) is keyed on the struct's species, which Transform
; has already overwritten with the target's.
	inc hl
	inc de
; moves
	ld bc, NUM_MOVES
	call CopyData
	ldh a, [hWhoseTurn]
	and a
	jr z, .next
; save enemy mon DVs at wTransformedEnemyMonOriginalDVs
	ld a, [de]
	ld [wTransformedEnemyMonOriginalDVs], a
	inc de
	ld a, [de]
	ld [wTransformedEnemyMonOriginalDVs + 1], a
	dec de
.next
; DVs
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hli]
	ld [de], a
	inc de
; Skip level and max HP
	inc hl
	inc hl
	inc hl
	inc de
	inc de
	inc de
; Attack, Defense, Speed, and Special stats
	ld bc, (NUM_STATS - 1) * 2
	call CopyData
	ld bc, wBattleMonMoves - wBattleMonPP
	add hl, bc ; ld hl, wBattleMonMoves
; full base PP for each copied move (vanilla Transform gives a flat 5
; instead - this is Super Transform's one deliberate behavior difference)
	dec de    ; LoadMovePPs writes starting at de+1, matching its own loop
	predef LoadMovePPs
.copyStats
; original (unmodified) stats and stat mods
	pop hl
	ld a, [hl]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, wEnemyMonUnmodifiedAttack
	ld de, wPlayerMonUnmodifiedAttack
	call .copyBasedOnTurn ; original (unmodified) stats
	ld hl, wEnemyMonStatMods
	ld de, wPlayerMonStatMods
	call .copyBasedOnTurn ; stat mods
; --- Super Transform addition starts here ---
; copy the target's current HP onto the user
	ldh a, [hWhoseTurn]
	and a
	ld hl, wEnemyMonHP
	ld de, wBattleMonHP
	jr z, .gotHPAddrs
	ld hl, wBattleMonHP
	ld de, wEnemyMonHP
.gotHPAddrs
	ld a, [hl]
	ld [de], a
	inc hl
	inc de
	ld a, [hl]
	ld [de], a
; clamp the user's new HP to the user's own (untouched) max HP
	ldh a, [hWhoseTurn]
	and a
	ld hl, wBattleMonMaxHP
	ld de, wBattleMonHP
	jr z, .gotClampAddrs
	ld hl, wEnemyMonMaxHP
	ld de, wEnemyMonHP
.gotClampAddrs
	ld a, [de]
	cp [hl]
	jr c, .noClampNeeded  ; user HP high byte < max HP high byte: fine
	jr nz, .doClamp        ; user HP high byte > max HP high byte: clamp
	inc de
	inc hl
	ld a, [de]
	cp [hl]
	dec de
	dec hl
	jr c, .noClampNeeded  ; high bytes equal, low byte under max: fine
	jr z, .noClampNeeded  ; exactly equal to max already: fine
.doClamp
	ld a, [hl]
	ld [de], a
	inc hl
	inc de
	ld a, [hl]
	ld [de], a
	dec hl
	dec de
.noClampNeeded
; --- Super Transform addition ends here ---
	ld hl, TransformedText
	jp PrintText

.copyBasedOnTurn
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotStatsOrModsToCopy
	push hl
	ld h, d
	ld l, e
	pop de
.gotStatsOrModsToCopy
	ld bc, (NUM_STATS - 1) * 2
	jp CopyData

.failed
	ld hl, PrintButItFailedText_
	jp EffectCallBattleCore
