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
	; The next gym's doors (wGymChoice): rolled afresh, or the gym not taken
	; when this badge opens a back-to-back pair.
	jp RoguePairAfterBadge

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

; ============================================================
; Back-to-back gyms (PAIR_BADGES_A/B, player feedback #2, 2026-10-09)
;
; The badge that brings the count to PAIR_BADGES_A or _B skips the next
; round's route. The flow is gym A's leader -> the Reward Room (the route's
; reward and its ROUTE_BATTLES credit) -> the lobby's single door to the gym
; the player was offered but did not take -> gym B.
;
; No saved state of its own. "A pair is waiting for its Reward Room" is
; derived: the badge count is a pair count AND BIT_ROGUE_GYM_NEXT is clear.
; That holds only from gym A's `res 0` until the Reward Room sets the bit
; again (without pairs it means "route next", which a pair count never has).
; ============================================================

; OUT: a = number of badges; z = a pair count. Clobbers b, c.
RogueIsPairBadgeCount::
	ld a, [wObtainedBadges]
	ld c, 0
	ld b, NUM_BADGES
.count
	srl a
	jr nc, .next
	inc c
.next
	dec b
	jr nz, .count
	ld a, c
	cp PAIR_BADGES_A
	ret z
	cp PAIR_BADGES_B
	ret

; Tail of RogueAwardCurrentGymBadge, the badge already set. Off a pair the
; choice is cleared (the next gym-next lobby rolls two). On a pair the gym
; not taken becomes the next lobby's single door: revealed if it was door 1
; (always shown) or the Psychic was paid, else hidden for the Psychic to
; reveal. Then the leader's exits are pointed at the Reward Room.
RoguePairAfterBadge:
	call RogueIsPairBadgeCount
	jr nz, .clear
	ld a, [wGymChoice]
	bit BIT_GYM_CHOICE_LATCHED, a
	jr z, .clear                ; nothing latched (a debug warp): roll afresh
	ld d, a                     ; d = the old choice
	and GYM_CHOICE_DOOR1_MASK
	ld e, a                     ; e = door 1's slot
	ld a, d
	and GYM_CHOICE_DOOR2_MASK
	rrca
	rrca
	rrca
	ASSERT GYM_CHOICE_DOOR2_SHIFT == 3
	cp e
	jr z, .clear                ; a single door: there is no other gym
	ld c, a                     ; c = door 2's slot
	ld a, e
	call .maskForSlot
	ld hl, wRogueCurGymBadgeMask
	cp [hl]
	jr z, .wonDoor1
	ld a, c
	call .maskForSlot
	cp [hl]
	jr nz, .clear               ; neither door's gym (a debug warp)
	; Won door 2's gym: door 1's, always shown, is the one left.
	ld a, e
	ld b, 1 << BIT_GYM_CHOICE_REVEALED
	jr .keep
.wonDoor1
	; Door 2's gym is left, shown only if the Psychic revealed it.
	ld a, d
	and 1 << BIT_GYM_CHOICE_REVEALED
	ld b, a
	ld a, c
.keep
	ld c, a
	add a
	add a
	add a
	or c                        ; the same slot behind both fields
	or b
	or 1 << BIT_GYM_CHOICE_LATCHED
	ld [wGymChoice], a
	jr RoguePatchExitsToRewardRoom
.clear
	xor a
	ld [wGymChoice], a
	ret

; a = slot -> a = 1 << slot. Clobbers b.
.maskForSlot
	ld b, a
	inc b
	xor a
	scf
.shift
	rla
	dec b
	jr nz, .shift
	ret

; Every warp of the current map that leads to the lobby leads to the Reward
; Room instead (its first warp, which is the same 0-based id the gyms' exits
; already hold). Clobbers a, c, hl.
RoguePatchExitsToRewardRoom:
	ld a, [wNumberOfWarps]
	and a
	ret z
	ld c, a
	ld hl, wWarpEntries + 3     ; first entry's map id (y, x, warp id, map)
.warp
	ld a, [hl]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .nextWarp
	ld [hl], REWARD_ROOM
.nextWarp
	inc hl
	inc hl
	inc hl
	inc hl
	dec c
	jr nz, .warp
	ret

; Farcalled from RecordStageMapLoad on every map load: a reload of gym A
; after its leader (Continue, a battle) rebuilds the warps from the map's
; data, so point them at the Reward Room again while the pair is waiting.
RoguePairMapLoad::
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_GYM_NEXT, a
	ret nz
	call RogueIsPairBadgeCount
	ret nz
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	ret z
	jr RoguePatchExitsToRewardRoom

; Farcalled from RewardRoom_Script's entry setup when a badge is already won
; (the run-start visit has none). Stands in for the skipped route: credits its
; ROUTE_BATTLES once, makes the next lobby a gym-next visit, re-arms the reward
; vendor, and sends both doors to the lobby. The doors are ROGUE_MAP warps,
; resolved through wLobbyDoor1/2StageMap at warp time, so they still lead to
; the lobby after a Continue in the room.
RoguePairRewardRoomEntry::
	ResetEvent EVENT_STEP_FORWARD
	ResetEvent EVENT_GOT_ROGUE_POKEMON
	ResetEvent EVENT_ROGUE_POKEMON_OFFERED
	ld hl, wRogueFlagsBitfield
	bit BIT_ROGUE_GYM_NEXT, [hl]
	jr nz, .credited            ; a re-entry must not credit the route twice
	set BIT_ROGUE_GYM_NEXT, [hl]
	ld a, [wBattleCount]
	add ROUTE_BATTLES
	jr nc, .countReady
	ld a, $ff
.countReady
	ld [wBattleCount], a
.credited
	ld a, INDIGO_PLATEAU_LOBBY
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a
	ret

; Farcalled from RewardRoom_Script mid-run, after the offers and item are rolled.
; Shows what a route shows (the item ball, under the witch's rules, and the ball
; colours) via RogueRefresh, then hides the three Poke Balls again: the reward is
; the vendor's menu, as on a route, because the balls hand out a flat run-start
; level.
RoguePairRewardRoomObjects::
	farcall RogueRefresh
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
	ret
