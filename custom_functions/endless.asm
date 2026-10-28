; Endless mode: continuing a run past the Champion into another eight-gym
; circuit (ENDLESS_MODE_IMPLEMENTATION_PLAN.md, ENDLESS_MODE_CHECKPOINT_A.md in
; Red Rogue Files). Farcall entry points only; everything else is local.
;
; THE CONTRACT. A continuation is NOT a run reset followed by a rebuild: it
; never calls RogueResetRunState, ApplyKeyItemTierEffects or anything else that
; refills item charges or overwrites earned effects. It clears only the
; circuit-local state listed in EndlessContinue and keeps everything else:
; party, boxes, daycare, bag, TMs, money, Credits, item charges, earned prizes
; and bridge effects, Ironman's fallen log, options, route/gift/wild-area
; history.
;
; NO SAVE. Accepting warps straight to the next route without saving. A reset
; before the player's next save reloads the pre-Champion save, in which
; wEndlessDepth was never incremented, so nothing can apply twice and Continue
; routing needs no Endless case.

SECTION "Endless", ROMX, BANK[$3C] ; pinned: floating, first-fit moved ~480 B of other code between $06 and $07 (measured 2026-10-28)

; ============================================================
; EndlessOffer  -- farcalled from HallOfFameResetEventsAndSaveScript on a normal
; clear (never an AI retry), right after the Hall of Fame presentation.
;
; Eligible when the AI has ever been defeated (EVENT_AI_DEFEATED, ZONE 0, so it
; survives every run reset) or Debug 2's unsaved override is set. Asks; on YES,
; prepares the next circuit and sets up the warp to its first route, which the
; caller detects as BIT_WARP_FROM_CUR_SCRIPT set in wStatusFlags3. NO or not
; eligible returns with nothing changed.
;
; AnimateHallOfFame leaves a white screen, the font loaded and sprites off. The
; prompt draws over that and is cleared again before returning, so the decline
; path's closing beat looks as it always did.
; Clobbers everything.
; ============================================================
EndlessOffer::
	CheckEvent EVENT_AI_DEFEATED
	jr nz, .eligible
	ld a, [wEndlessDebugOverride]
	and a
	ret z
.eligible
	call ClearScreen
	call GBPalNormal
	ld hl, EndlessPromptText
	call PrintText
	call YesNoChoice              ; cursor starts on YES
	ldh a, [hCurrentMenuItem]
	push af
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	pop af
	and a
	ret nz                        ; NO (or B)
	call EndlessContinue
	; The route's first warp, as a lobby door would take it (PatchWarpEntry:
	; every stage is entered at its first-listed warp_event, id 0).
	ld a, [wRogueMap]
	ldh [hWarpDestinationMap], a
	xor a
	ld [wDestinationWarpID], a
	ld a, HALL_OF_FAME
	ld [wLastMap], a
	ld hl, wStatusFlags3
	set BIT_WARP_FROM_CUR_SCRIPT, [hl]
	ret

; Inline rather than text_far: growing a floating text section moved other
; sections between banks (measured 2026-10-28). PrintText reads it from this bank.
EndlessPromptText:
	text "Continue on to"
	line "endless mode?"
	done

; One kept event: its bit is pushed (as a's masked byte) across the range reset.
MACRO endless_keep_event
	ld a, [wEventFlags + (\1) / 8]
	and 1 << ((\1) % 8)
	push af
ENDM

; Pops in the reverse order of endless_keep_event and ORs the bit back.
MACRO endless_restore_event
	pop af
	ld hl, wEventFlags + (\1) / 8
	or [hl]
	ld [hl], a
ENDM

; ============================================================
; EndlessContinue  (private)
; Prepares the next circuit. Order matters where noted.
; ============================================================
EndlessContinue:
	; --- 1. Gym history. The first continuation discards prior-run history:
	; the next circuit must exclude exactly the eight gyms THIS run completed.
	; Later continuations leave the mask alone, and RogueRollGymLineup's own
	; "fewer than eight left -> clear" rule then gives the 16-gym rotation
	; (Johto) or a fresh 8 every circuit (Kanto only). Before the depth bump.
	ld a, [wEndlessDepth]
	and a
	call z, EndlessSeedGymHistory
	ld hl, wEndlessDepth
	ld a, [hl]
	cp ENDLESS_DEPTH_MAX
	jr z, .depthDone
	inc [hl]
.depthDone

	; --- 2. Settle any accepted witch bargain, exactly as the lobby would on
	; arrival, BEFORE step 5 clears wRogueFlagsBitfield (BIT_WITCH_ACCEPTED).
	farcall WitchSettlePendingPrize

	; --- 3. Elapsed progress. Daycare growth/price and rental time are
	; (wBattleCount - deposit snapshot) mod 256, so moving every snapshot by the
	; same delta as the count keeps each elapsed value exact. After the
	; farcall above, which would clobber b.
	ld a, [wBattleCount]
	dec a                         ; delta: the count becomes 1 below
	ld b, a
	ld a, [wDayCareDepositBattleCount]
	sub b
	ld [wDayCareDepositBattleCount], a
	ld a, [wDayCareDepositBattleCount2]
	sub b
	ld [wDayCareDepositBattleCount2], a
	ld a, 1                       ; the count Oak's Lab leaves a new run on
	ld [wBattleCount], a

	; --- 4. Every map's script byte, the stage cache and the stale reward
	; offers: one fill over the CurScript span, which interleaves three fields
	; that must survive it (see the note at wGameProgressFlags).
	ASSERT wTurnRewindUsages > wGameProgressFlags && wTurnRewindUsages < wRogueMap
	ASSERT wFusionSecondaryForm > wGameProgressFlags && wFusionSecondaryForm < wRogueMap
	ASSERT wFallenCount > wGameProgressFlags && wFallenCount < wRogueMap
	ld a, [wTurnRewindUsages]
	push af
	ld a, [wFusionSecondaryForm]
	ld d, a
	ld a, [wFallenCount]
	ld e, a
	ld hl, wGameProgressFlags
	ld bc, wRogueMap + 1 - wGameProgressFlags
	xor a
	call FillMemory               ; preserves de
	ld a, d
	ld [wFusionSecondaryForm], a
	ld a, e
	ld [wFallenCount], a
	pop af
	ld [wTurnRewindUsages], a

	; --- 5. Circuit-local scheduling, per-circuit quotas and per-visit state.
	; History bits are kept: wVisitedStagesBitfield, the bridge offered mask
	; and the wild-area type cycle. Only their packed per-run counts restart.
	xor a
	ld [wRogueFlagsBitfield], a   ; route next; no trade, bargain or mini-boss
	ld [wRoutesSinceSpecial], a
	ld [wMiniBossCount], a
	ld [wProcCemBossBattle], a
	ld [wDebug2ForcedDoor1], a
	ld [wDebug2ForcedDoor2], a
	ld [wWitchChallenge], a
	ld [wWitchPrize], a
	ld [wWitchLevelBonus], a      ; challenge parameter union, both bytes
	ld [wBattleTurnCount], a
	ld [wGymChoice], a
	ld [wObtainedBadges], a       ; the trainer card's badges restart per circuit
	ld [wStageEvent], a
	ld [wCurOpponent], a
	ld a, [wWildAreaState]
	and ~WILD_AREA_COUNT_MASK & $ff
	ld [wWildAreaState], a
	ld a, [wBridgeState]
	and ~BRIDGE_COUNT_MASK & $ff
	ld [wBridgeState], a
	; Lineup, defeat order, Elite Four and Champion: rolled fresh below and at
	; Victory Road. The mask that follows them is the gym history, kept.
	ASSERT wBadgeSlotOrder == wRunGymLineup + 8 && wRunElite4 == wBadgeSlotOrder + 8
	ASSERT wRunChampion == wRunElite4 + 4 && wGymsUsedMask == wRunChampion + 1
	ld hl, wRunGymLineup
	ld bc, wGymsUsedMask - wRunGymLineup
	xor a
	call FillMemory
	; What the Hall of Fame script would have reset on its way to the wipe.
	ld hl, wStatusFlags7
	res BIT_NO_MAP_MUSIC, [hl]
	ld hl, wElite4Flags
	res BIT_STARTED_ELITE_4, [hl]
	ld a, SILPH_CO_DORM           ; a blackout still ends the run in the Dorm
	ld [wLastBlackoutMap], a

	; --- 6. Run-scoped events, so recycled maps start fresh, except the
	; starter and intro flags that keep Oak's Lab and the bridge intro from
	; replaying in a run that is not new.
	endless_keep_event EVENT_GOT_STARTER
	endless_keep_event EVENT_ESTABLISHED_STARTER
	endless_keep_event EVENT_BATTLED_RIVAL_IN_OAKS_LAB
	endless_keep_event EVENT_BRIDGE_INTRO
	ResetEventRange RUN_EVENTS_START, RUN_EVENTS_END
	endless_restore_event EVENT_BRIDGE_INTRO
	endless_restore_event EVENT_BATTLED_RIVAL_IN_OAKS_LAB
	endless_restore_event EVENT_ESTABLISHED_STARTER
	endless_restore_event EVENT_GOT_STARTER
	farcall RogueRunToggleClear   ; objects stage scripts hid come back

	; --- 7. The next circuit's eight gyms.
	farcall RogueRollGymLineup

	; --- 8. Heal HP, status and PP. Ironman's dead are already out of the
	; party; no item charge is touched.
	predef HealParty

	; --- 9. The first route, and the reward category a lobby door would have
	; chosen for it.
	farcall _PickRandomUnvisitedStage ; -> wRogueMap
	ld c, 4                       ; HEALING / STAT / TM / MONEY
	call Rangerandom
	ld [wRogueDoorSelection], a
	ret

; ============================================================
; EndlessSeedGymHistory  (private)
; wGymsUsedMask = exactly the pool bits of this run's lineup. Janine shares
; Koga's pool index (the Fuchsia slot), so she counts as that one gym.
; Clobbers a/bc/de/hl.
; ============================================================
EndlessSeedGymHistory:
	xor a
	ld [wGymsUsedMask], a
	ld [wGymsUsedMask + 1], a
	ld de, wRunGymLineup
	ld b, NUM_BADGES
.slot
	ld a, [de]
	inc de
	cp JANINE
	jr nz, .haveClass
	ld a, KOGA
.haveClass
	push de
	push bc
	ld b, a
	ld hl, EndlessGymPool
	ld c, 0                       ; pool index
.scan
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	ld a, c
	cp NUM_GYM_POOL_ALL
	jr c, .scan
	jr .next                      ; not a pool leader (0 = unrolled): no bit
.found
	ld hl, wGymsUsedMask
	ld a, c
	cp 8
	jr c, .lowByte
	sub 8
	inc hl
.lowByte
	inc a                         ; so index 0 exits after one dec
	ld b, a
	ld a, 1
.shift
	dec b
	jr z, .gotBit
	add a
	jr .shift
.gotBit
	or [hl]
	ld [hl], a
.next
	pop bc
	pop de
	dec b
	jr nz, .slot
	ret

; The roller's own pool, expanded from the same macro (random_stage_selection.asm).
EndlessGymPool:
	gym_leader_pool_rows
ASSERT @ - EndlessGymPool == NUM_GYM_POOL_ALL
