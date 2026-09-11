GymStatues:
; if in a gym and have the corresponding badge, a = GymStatueText2_id and jp PrintPredefTextID
; if in a gym and don't have the corresponding badge, a = GymStatueText1_id and jp PrintPredefTextID
; else ret
	call EnableAutoTextBoxDrawing
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
; Which badge this gym awards comes from wRogueCurGymBadgeMask, NOT from the map
; id. It used to be a MapBadgeFlags lookup keyed on hCurMap, which was correct
; only while gym map == leader == badge bit. With a rolled gym lineup the badge
; is decided by the slot the player entered through, so a gym reached through
; slot 3 checks bit 3 whatever building it is. The table is gone; see
; GYM_LEADER_EXPANSION_PLAN.md Phase 6 Correction 2.
;
; The table's search loop also doubled as an "am I in a gym?" test, which is not
; needed: GymStatues is reachable only from gym maps, bound per map at fixed
; coordinates by data/events/hidden_events.asm.
	ld a, [wRogueCurGymBadgeMask]
	and a
	ret z               ; no gym selected (e.g. a debug warp) - say nothing
	ld b, a
	ld a, [wObtainedBadges]
	and b
	cp b
	tx_pre_id GymStatueText2
	jr z, .haveBadge
	tx_pre_id GymStatueText1
.haveBadge
	jp PrintPredefTextID

; ============================================================
; RogueAwardCurrentGymBadge  (predef)
; Sets the badge bit for the gym the player just beat.
;
; Reached as a predef, not a call, for a size reason that is load-bearing:
; `predef X` is `ld a, n` + `call Predef` = exactly 5 bytes, the same size as
; the `ld hl, wObtainedBadges` + `set BIT_x, [hl]` it replaces at all 16 gym
; sites. Four of those sites live in bank $17, which has 2 bytes free, so a
; 6-byte farcall would not fit; HOME is equally unaffordable. Zero delta per
; site is the only shape that works. See GYM_LEADER_EXPANSION_PLAN.md Phase 6.
;
; Input:  wRogueCurGymBadgeMask (pre-shifted, 0 = unset)
; Output: wObtainedBadges updated
; ============================================================
RogueAwardCurrentGymBadge::
	ld a, [wRogueCurGymBadgeMask]
	and a
	jr z, .noMask
.award
	ld hl, wObtainedBadges
	or [hl]
	ld [hl], a
	ret

.noMask
; Reached when the player got here without passing through _PickNextGym - a
; debug-menu warp straight into a gym. Award the lowest unset badge bit so the
; run still progresses; awarding nothing would soft-lock gym advancement.
	ld a, [wObtainedBadges]
	cp $ff
	ret z               ; all eight already earned, nothing to award
	ld b, a
	ld a, 1
.findClear
	ld c, a
	and b
	jr z, .foundClear
	sla c
	ld a, c
	jr .findClear
.foundClear
	ld a, c
	jr .award

GymStatueText1::
	text_far _GymStatueText1
	text_end

GymStatueText2::
	text_far _GymStatueText2
	text_end
