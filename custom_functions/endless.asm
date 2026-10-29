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

; ============================================================
; RecycleStagePool / RecycleBridgePool  -- farcalled from the stage picker and
; the gift-room picker (bank $38) at the moment each pool's no-repeat history
; runs out and is cleared.
;
; A run never exhausts either pool; an Endless run does, MID-circuit (routes
; around circuit 3, gift rooms around circuit 4), and the next pick can then be
; a map already cleared earlier in the same circuit: its trainers beaten, its
; reward taken, Bill's PC already switched to the viewer. A continuation resets
; every run event, but nothing resets them mid-circuit.
;
; So every map in the pool goes back to the state a fresh run gives it, by the
; run reset's own three steps restricted to the pool: its run events, its map
; script bytes, and (stages) its hidden objects. The events and script bytes are
; generated (tools/gen_pool_recycle.py, data/events/pool_recycle.asm); the
; player is in the lobby, so no pool map is loaded.
; Clobbers everything.
; ============================================================
RecycleStagePool::
	ld de, StagePoolEventMask
	ld hl, StagePoolScripts
	call RecyclePool
	ASSERT BANK(RogueStageToggleClear) == BANK(@) ; both pinned to $3C
	jp RogueStageToggleClear

RecycleBridgePool::
	ld de, BridgePoolEventMask
	ld hl, BridgePoolScripts
	; fallthrough
; de = the pool's event mask over ZONE 1, hl = its 0-terminated script list.
RecyclePool:
	push de
.script
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	or e
	jr z, .events
	xor a
	ld [de], a                    ; map script 0: its default entry state
	jr .script
.events
	pop de
	ld hl, wEventFlags + RUN_EVENTS_START / 8
	ld c, POOL_MASK_BYTES
.byte
	ld a, [de]
	inc de
	cpl
	and [hl]
	ld [hli], a
	dec c
	jr nz, .byte
	ret

; One accumulator per ZONE 1 byte, OR'd together by pool_event and written out
; by pool_mask_emit, so the generated lists name events, never bit numbers.
DEF POOL_MASK_BYTES EQU (RUN_EVENTS_END + 1 - RUN_EVENTS_START) / 8
ASSERT RUN_EVENTS_START % 8 == 0 && RUN_EVENTS_END % 8 == 7

MACRO pool_mask_begin
	FOR _pool_i, RUN_EVENTS_START / 8, RUN_EVENTS_END / 8 + 1
		DEF POOL_MASK_{d:_pool_i} = 0
	ENDR
ENDM

MACRO pool_event
	ASSERT (\1) >= RUN_EVENTS_START && (\1) <= RUN_EVENTS_END, "\1 is not a run event"
	DEF _pool_byte = (\1) / 8
	DEF POOL_MASK_{d:_pool_byte} |= 1 << ((\1) % 8)
ENDM

MACRO pool_mask_emit
	FOR _pool_i, RUN_EVENTS_START / 8, RUN_EVENTS_END / 8 + 1
		db POOL_MASK_{d:_pool_i}
	ENDR
ENDM

INCLUDE "data/events/pool_recycle.asm"

; ============================================================
; LegendaryPoolUnowned  -- farcalled from legendary_boss_helpers.asm (bank $38,
; which has no room for it).
;
; Challenge 11's per-leader pools, minus the species the player already owns,
; so a recurring gym (Endless) never trades a second copy of the same
; legendary, and the witch never offers a bargain whose only prize is owned.
; Ownership is AllSpeciesCheck's scope, the party and the current box. Every
; pool species is single-stage, so family-wide is the species itself, and this
; needs none of AllSpeciesCheck's wAllSpecies buffer: that shares a UNION with
; live battle state, and the ace roll runs during party generation.
;
; In:  e = trainer class; d = 0 to count only, nonzero to pick one.
; Out: carry SET = the class has a pool with at least one unowned species, and
;      when picking, e = one of them, uniformly. With nothing owned the pick
;      consumes the same draw and lands on the same species as before.
;      carry CLEAR = no pool, or every member owned.
; Clobbers a/bc/hl.
; ============================================================
LegendaryPoolUnowned::
	ld a, e
	call GetLegendaryPoolForClass  ; hl -> count, carry = has a pool
	ret nc
	ld a, [hli]
	ld b, a                        ; b = members left to count
	ld c, 0                        ; c = unowned
	push hl
.count
	ld a, [hli]
	call LegendarySpeciesOwned
	jr c, .counted
	inc c
.counted
	dec b
	jr nz, .count
	pop hl                         ; hl -> first member
	ld a, c
	and a
	ret z                          ; all owned; `and a` cleared carry
	ld a, d
	and a
	jr z, .yes                     ; count only
	call Rangerandom               ; a = 0..c-1; preserves bc/de/hl
	ld b, a                        ; b = unowned members still to skip
.pick
	ld a, [hli]
	ld e, a
	call LegendarySpeciesOwned
	jr c, .pick
	ld a, b
	and a
	jr z, .yes
	dec b
	jr .pick
.yes
	scf
	ret

; a = species -> carry SET if it is in the party or the current box, the
; lists AllSpeciesCheck reads. Preserves bc/de/hl.
LegendarySpeciesOwned:
	push hl
	push bc
	ld b, a
	ld hl, wPartyCount
	call .scan
	jr c, .done
	ld hl, wBoxCount
	call .scan
.done
	pop bc
	pop hl
	ret
; hl -> a count byte and the species list after it. Bounded by the COUNT, not
; the $ff terminator: a debug boot (FIGHT 2) leaves an empty box's list
; unterminated, and a terminator scan ran on into unrelated WRAM and found a
; Ho-Oh byte there (measured 2026-10-28).
.scan
	ld a, [hli]
	ld c, a
.next
	ld a, c
	and a
	ret z                         ; `and a` cleared carry: not found
	dec c
	ld a, [hli]
	cp b
	jr nz, .next
	scf
	ret

; ============================================================
; EndlessLevelBonus  -- farcalled from the level funnels (func_enc_gen.asm,
; RogueApplyTrainerLevelModifiers / RogueApplyWildLevelModifiers), before the
; witch bonus and the LEVELS setting.
;
; Past the original circuit every round-indexed table already sits on its last
; authored row (Victory Road / Elite Four), so content SHAPE stays at its
; maximum; LEVELS keep growing by one curve-derived bonus per round, the same
; for every category, so route < final route < gym < leader < Elite Four, and
; boss over the party, hold exactly as they stand at the end of the original
; circuit. The rows are solved by tools/balance/model.py (--endless), never
; hand-tuned: ENDLESS_MODE_CHECKPOINT_D.md section 3.3.
;
; wCurEnemyLevel += EndlessLevelRows[progress / ROUND_BATTLES - ENDLESS_FIRST_ROUND],
; saturating at 255 (the funnel's RogueApplyDifficulty clamps to 100). Nothing
; at depth 0, so the original circuit cannot change.
; Clobbers a/bc/hl; keeps de.
; ============================================================
EndlessLevelBonus::
	ld a, [wEndlessDepth]
	and a
	ret z
	call GetRunProgress
	ASSERT ROUND_BATTLES == 8
	srl a
	srl a
	srl a                         ; a = global round
	sub ENDLESS_FIRST_ROUND
	ret c                         ; cannot happen at depth >= 1; stay safe
	ld c, a
	ld b, 0
	ld hl, EndlessLevelRows
	add hl, bc
	ld a, [wCurEnemyLevel]
	add [hl]
	jr nc, .store
	ld a, $ff
.store
	ld [wCurEnemyLevel], a
	ret

INCLUDE "data/balance/endless_levels.asm"

; ============================================================
; EndlessRewardLevelBonus  -- farcalled from GetRewardMonLevel
; (rogue_reward_menu.asm) after its REWARD_LEVEL_CAP clamp. The cap holds the
; original circuit's last rewards at 50; past it, the same per-round bonus the
; trainers get goes on top (what tools/balance/model.py join_reward solves
; against), then 1..100. Nothing at depth 0.
; Clobbers a/bc/hl; keeps de.
; ============================================================
EndlessRewardLevelBonus::
	call EndlessLevelBonus
	ld a, [wCurEnemyLevel]
	cp MAX_LEVEL + 1
	ret c
	ld a, MAX_LEVEL
	ld [wCurEnemyLevel], a
	ret

; ============================================================
; EndlessRosterClass  -- farcalled from GetRandMon (func_enc_gen.asm) for every
; rarity-class roster mon at depth >= 1 (ENDLESS_MODE_CHECKPOINT_D.md 3.4, user
; answer Q1: "4 master and then 2 ultra or masters").
;
; Every Endless roster reads the last authored row (6 mons, 2 of them Master),
; and the loop rolls the commonest class first, so wEnemyPartyCount is the slot
; in that order. With s = progress / ROUND_BATTLES - LAST_ROUND (1 in the first
; Endless round), each slot gets a class floor:
;   slots ENDLESS_FLEX_SLOTS..5   Master once slot + s >= PARTY_LENGTH: one more
;                                 slot a round, all four by s = 4
;   slots 0..ENDLESS_FLEX_SLOTS-1 at least Ultra; once all four above are
;                                 Master (from the round after), each rolls
;                                 Ultra or Master, 50/50
; A floor never lowers the class the row (or the witch's bump) already gave.
; In: e = class, GetRandMon's inverted encoding (4 Poke .. 1 Master).
; Out: e = class, raised to the floor. Clobbers a/d/flags.
; ============================================================
DEF ENDLESS_FLEX_SLOTS EQU 2
DEF ROSTER_CLASS_MASTER EQU 1 ; GetRandMon's inverted b: 4 Poke, 3 Great, 2 Ultra
DEF ROSTER_CLASS_ULTRA  EQU 2
EndlessRosterClass::
	call EndlessRoundsSoFar
	ret z
	ld d, a                       ; d = s, Endless rounds so far (1+)
	ld a, [wEnemyPartyCount]      ; slot being rolled
	cp ENDLESS_FLEX_SLOTS
	jr c, .flexSlot
	add d
	cp PARTY_LENGTH
	ret c                         ; this slot's turn has not come yet
	ld e, ROSTER_CLASS_MASTER
	ret
.flexSlot
	ld a, e
	cp ROSTER_CLASS_ULTRA + 1
	jr c, .atLeastUltra
	ld e, ROSTER_CLASS_ULTRA
.atLeastUltra
	; The last fixed slot (ENDLESS_FLEX_SLOTS) turns Master at
	; s = PARTY_LENGTH - ENDLESS_FLEX_SLOTS; the coin flips start one round on.
	ld a, d
	cp PARTY_LENGTH - ENDLESS_FLEX_SLOTS + 1
	ret c
	call Random
	rrca
	ret nc
	ld e, ROSTER_CLASS_MASTER
	ret

; ============================================================
; EndlessRoundsSoFar  (private)
; Out: a = s = progress / ROUND_BATTLES - LAST_ROUND, the Endless rounds so far
;      (1 in the first Endless round); Z set and carry clear when s is 0, which
;      covers depth 0. Clobbers a/flags.
; ============================================================
EndlessRoundsSoFar:
	ld a, [wEndlessDepth]
	and a
	ret z
	call GetRunProgress
	ASSERT ROUND_BATTLES == 8
	srl a
	srl a
	srl a                         ; a = global round
	sub LAST_ROUND
	ret nc
	xor a                         ; cannot happen at depth >= 1; stay safe
	ret

; ============================================================
; EndlessUberStep  -- farcalled wherever a Master boss or trainer ace has just
; been rolled (ENDLESS_MODE_CHECKPOINT_E.md section 3): one more cascade step on
; a two-class Master | Uber table. Uber's base width is ENDLESS_UBER_BASE and
; the bonus is ENDLESS_UBER_STEP x s (EndlessRoundsSoFar), saturating, so it
; grows with the run and never fires at depth 0.
; Out: carry SET = this Master becomes an Uber. Clobbers everything.
; ============================================================
EndlessUberStep::
	call EndlessRoundsSoFar
	ret z                         ; carry clear: stays Master
	ld b, a                       ; b = s
	xor a
.bonus
	add ENDLESS_UBER_STEP
	jr c, .saturate
	dec b
	jr nz, .bonus
	jr .haveBonus
.saturate
	ld a, $ff
.haveBonus
	ld b, a
	call Random
	ld hl, EndlessUberWidths
	call RollSpreadClass          ; c = 1 Master, 2 Uber
	ld a, 1
	cp c                          ; carry when c = 2
	ret

; RollSpreadClass table, read in this bank: one band below the top (Master),
; Uber is the fall-through with ENDLESS_UBER_BASE of 256 before the bonus.
EndlessUberWidths:
	db 1, 256 - ENDLESS_UBER_BASE, 0

; ============================================================
; EndlessSpecAceUber  -- farcalled from PartyGenLegendaryBossAce (bank $39)
; for a spec-built team's LAST slot, its ace, after the slot's species and
; form are final and before AddPartyMon, when Challenge 11 did not swap it.
; (ENDLESS_MODE_CHECKPOINT_E.md 3.2; user answer Q4 plus the mini-bosses.)
;
; At depth >= 1, for this circuit's gym leaders, Elite Four and Champion and
; the three mini-bosses, the ace takes EndlessUberStep; on carry an Uber,
; drawn ignoring ownership, replaces it. Never two: no roll when the drawn ace
; or a mon already in the party is an Uber.
; Out: carry SET = wCurPartySpecies / wSpawnForm now hold the Uber. Clobbers all.
; ============================================================
EndlessSpecAceUber::
	ld a, [wEndlessDepth]
	and a
	ret z
	call EndlessAceClassEligible
	ret nc
	farcall RogueEnemyTeamHasUber
	ccf
	ret nc                        ; already fields an Uber
	call EndlessUberStep
	ret nc
	ld e, 0                       ; opponents ignore ownership (user answer Q2)
	farcall RogueDrawUber         ; carry: d = species, e = form
	ret nc
	ld a, d
	ld [wCurPartySpecies], a
	ld a, e
	ld [wSpawnForm], a
	scf
	ret

; Carry SET if wTrainerClass is a mini-boss, or this circuit's gym leader,
; Elite Four member or Champion (wRunGymLineup, wRunElite4, wRunChampion).
; Clobbers a/bc/hl.
EndlessAceClassEligible:
	ld a, [wTrainerClass]
	ld c, a
	cp RIVAL_MINIBOSS
	jr z, .yes
	cp GIOVANNI_MINIBOSS
	jr z, .yes
	cp KARATE_MINIBOSS
	jr z, .yes
	ld hl, wRunGymLineup
	ld b, NUM_BADGES
	call .scan
	ret c
	ASSERT wRunChampion == wRunElite4 + 4
	ld hl, wRunElite4
	ld b, 4 + 1                   ; the Elite Four, then the Champion
.scan
	ld a, [hli]
	cp c
	jr z, .yes
	dec b
	jr nz, .scan
	and a
	ret
.yes
	scf
	ret

; ============================================================
; LegendaryBossTable
; Challenge 11's leaders and the legendaries each can field, keyed on TRAINER
; CLASS. Never key this on wGymLeaderNo: Kanto and Johto share 1-8 (Morty and
; Erika are both 4, Pryce and Blaine both 7), and gyms are drawn in a random
; order every run, so neither the number nor a "gym N" says who the leader is.
; Every species here must be single-stage (LegendaryPoolUnowned relies on it;
; test_endless_recycle checks it).
;
; Row: db class, count, species x count. Terminated by db 0.
; The witch's offer gate (witch_setup.asm) checks the same seven leaders by
; their gym MAP, since at lobby time no battle has set wTrainerClass. Keep the
; two lists in step.
; ============================================================
LegendaryBossTable:
	db ERIKA,    2, MEW, CELEBI
	db SABRINA,  4, MEWTWO, MEW, CELEBI, LUGIA
	db BLAINE,   2, MEW, HO_OH
	db GIOVANNI, 1, MEWTWO
	db FALKNER,  2, LUGIA, HO_OH
	db MORTY,    1, HO_OH
	db PRYCE,    1, CELEBI
	db 0

; GetLegendaryPoolForClass
; Input:  a = trainer class
; Output: carry SET -> hl = the row's count byte, species follow it
;         carry CLEAR -> the class has no legendary
; Clobbers: a, b, hl
GetLegendaryPoolForClass:
	ld b, a
	ld hl, LegendaryBossTable
.loop
	ld a, [hli]
	and a
	ret z                        ; end of table; `and a` cleared carry
	cp b
	jr z, .found
	ld a, [hli]                  ; count: skip that many species
	add l
	ld l, a
	jr nc, .loop
	inc h
	jr .loop
.found
	scf
	ret
