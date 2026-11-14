; Run challenges: opt-in handicaps chosen at the Dorm PC between runs, active
; for a whole run, and the badges and best heat a Hall of Fame clear earns with
; them. Bit ids are RUN_CH_* (constants/ram_constants.asm).
;
; State, all saved Main Data outside wGameProgressFlags, so the run reset
; leaves it alone:
;   wRunChallenges       the choice; locked while a run is in progress
;   wRunChallengeBroken  this run's broken badge conditions (cleared at run
;                        start, see the layout below)
;   wChallengeBadges/Hi  RUN_CH_* bits ever cleared with
;   wChallengeBadges2    BIT_CHBADGE_* extras ever earned
;   wBestHeat            the highest heat ever cleared with
;
; Each effect is tested at its own site with the run_challenge macro
; (macros/code.asm) beside the matching witch test, so the effect code is
; shared with the witch's zone challenge of the same kind.
;
; Pinned beside Run Records in $12. The entry points are farcalled, except the
; ones Run Records reaches with a plain call from the same bank.

SECTION "Run Challenges", ROMX, BANK[$12]

; wRunChallengeBroken layout. Bits 0-2 use the BIT_CHBADGE_* index of the badge
; they break, so a clear can award `~broken & RUN_BROKEN_FLAGS` directly.
; Bits 6-7 hold the lowest difficulty heat seen this run, plus 1 (0 = never
; seen; a save converted mid-run counts as no difficulty heat).
DEF RUN_BROKEN_FLAGS EQU (1 << BIT_CHBADGE_IRONMAN) | (1 << BIT_CHBADGE_SET_STYLE) | (1 << BIT_CHBADGE_NO_GIFTS)
DEF RUN_DIFF_HEAT_MASK EQU %11000000
ASSERT BIT_CHBADGE_IRONMAN < 6 && BIT_CHBADGE_SET_STYLE < 6 && BIT_CHBADGE_NO_GIFTS < 6

DEF RUN_HEAT_IRONMAN EQU 3

; ============================================================
; RunChallengesNewGame - true New Game: no choice, no badges, no heat.
; Reached from RunRecordsInit (same bank). Clobbers af.
; ============================================================
RunChallengesNewGame::
	xor a
	ld [wRunChallenges], a
	ld [wRunChallenges + 1], a
	ld [wChallengeBadges], a
	ld [wChallengeBadgesHi], a
	ld [wChallengeBadges2], a
	ld [wBestHeat], a
	ld [wRunChallengeBroken], a
	ret

; ============================================================
; RunChallengesStartRun - a starter was just accepted (RunTimerStart, same
; bank). Every badge condition starts unbroken, then the options as they stand
; are checked once, so a run begun with Ironman off never earns IRONMAN.
; Clobbers af, de, hl.
; ============================================================
RunChallengesStartRun::
	xor a
	ld [wRunChallengeBroken], a
	jr RunChallengesCheckOptions

; ============================================================
; RunChallengesNoteOptions - the options menu just closed (OptionsMenuEngine).
; While a run is in progress, Ironman off breaks IRONMAN, battle style SHIFT
; breaks SET STYLE, and a lower difficulty lowers the run's difficulty heat.
; The title screen's menu reaches this too, after the save is loaded, so a
; change made there before Continue counts. farcall only. Clobbers af, de, hl.
; ============================================================
RunChallengesNoteOptions::
	CheckEvent EVENT_GOT_STARTER
	ret z
	; fall through
RunChallengesCheckOptions:
	ld hl, wRunChallengeBroken
	ld a, [wOptions3]
	bit BIT_IRONMAN, a
	jr nz, .ironmanOn
	set BIT_CHBADGE_IRONMAN, [hl]
.ironmanOn
	ld a, [wOptions]
	bit BIT_BATTLE_SHIFT, a
	jr z, .setStyle
	set BIT_CHBADGE_SET_STYLE, [hl]
.setStyle
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	ld e, a
	ld d, 0
	push hl
	ld hl, RunDifficultyHeat
	add hl, de
	ld e, [hl]
	inc e                         ; e = heat + 1, 1-3
	pop hl
	ld a, [hl]
	and RUN_DIFF_HEAT_MASK
	jr z, .storeDifficulty        ; nothing seen yet this run
	rlca
	rlca                          ; a = stored heat + 1
	cp e
	ret c                         ; already lower
	ret z
.storeDifficulty
	ld a, [hl]
	and LOW(~RUN_DIFF_HEAT_MASK)
	ld d, a
	ld a, e
	rrca
	rrca                          ; heat + 1 into bits 6-7
	or d
	ld [hl], a
	ret

; Indexed by the DIFFICULTY_* value (not display order).
RunDifficultyHeat:
	db 0 ; DIFFICULTY_NORMAL
	db 0 ; DIFFICULTY_EASY
	db 0 ; DIFFICULTY_VERY_EASY
	db 1 ; DIFFICULTY_HARD
	db 2 ; DIFFICULTY_VERY_HARD
ASSERT DIFFICULTY_NORMAL == 0 && DIFFICULTY_EASY == 1 && DIFFICULTY_VERY_EASY == 2
ASSERT DIFFICULTY_HARD == 3 && DIFFICULTY_VERY_HARD == 4

; ============================================================
; RunChallengesCommitClear - the Champion was beaten (HallOfFame script, every
; clear that is not the post-loss AI retry). ORs this run's challenges into the
; badges, awards the unbroken extras and the count combinations, and raises
; wBestHeat. Idempotent, so a later Endless clear can only add to it.
; farcall only. Clobbers af, bc, de, hl.
; ============================================================
RunChallengesCommitClear::
	ld hl, wChallengeBadges
	ld a, [wRunChallenges]
	or [hl]
	ld [hl], a
	ld hl, wChallengeBadgesHi
	ld a, [wRunChallenges + 1]
	or [hl]
	ld [hl], a
	ld a, [wRunChallengeBroken]
	cpl
	and RUN_BROKEN_FLAGS
	ld e, a                       ; e = extras earned
	call RunChallengeCount        ; c = challenges on; keeps de
	ld a, c
	cp 3
	jr c, .gotCombos
	set BIT_CHBADGE_THREE, e
	cp 6
	jr c, .gotCombos
	set BIT_CHBADGE_SIX, e
	cp NUM_RUN_CHALLENGES
	jr c, .gotCombos
	set BIT_CHBADGE_ALL, e
.gotCombos
	ld hl, wChallengeBadges2
	ld a, e
	or [hl]
	ld [hl], a
	call RunChallengeHeat         ; a = this run's heat
	ld hl, wBestHeat
	cp [hl]
	ret c
	ld [hl], a
	ret

; ============================================================
; RunChallengeHeat - a = the heat of the run in progress: the weights of the
; challenges on, plus Ironman kept all run, plus the lowest difficulty seen.
; Also what the Dorm PC list shows as the current heat. Clobbers af, bc, de, hl.
; ============================================================
RunChallengeHeat::
	ld bc, 0                      ; b = heat, c = RUN_CH_* id
.loop
	ld a, c
	call RunChallengeIsOn
	jr z, .off
	ld hl, RunChallengeWeights
	ld e, c
	ld d, 0
	add hl, de
	ld a, [hl]
	add b
	ld b, a
.off
	inc c
	ld a, c
	cp NUM_RUN_CHALLENGES
	jr c, .loop
	ld a, [wRunChallengeBroken]
	ld c, a
	bit BIT_CHBADGE_IRONMAN, a
	jr nz, .noIronman
	ld a, b
	add RUN_HEAT_IRONMAN
	ld b, a
.noIronman
	ld a, c
	and RUN_DIFF_HEAT_MASK
	jr z, .done
	rlca
	rlca
	dec a                         ; the lowest difficulty heat seen
	add b
	ret
.done
	ld a, b
	ret

; ============================================================
; RunChallengeCount - c = how many run challenges are on. Clobbers af, b, hl.
; ============================================================
RunChallengeCount::
	ld bc, NUM_RUN_CHALLENGES << 8 ; b = ids left, c = count
.loop
	ld a, b
	dec a                         ; ids NUM-1 down to 0
	call RunChallengeIsOn
	jr z, .off
	inc c
.off
	dec b
	jr nz, .loop
	ret

; ============================================================
; RunChallengeMask - a = RUN_CH_* id -> hl = its byte in wRunChallenges,
; a = its bit mask. Keeps bc, de.
; RunChallengeIsOn  - the same, then NZ if that challenge is on.
; ============================================================
RunChallengeIsOn::
	call RunChallengeMask
	and [hl]
	ret

RunChallengeMask::
	push bc
	ld b, a
	ld hl, wRunChallenges
	cp 8
	jr c, .lowByte
	inc hl
.lowByte
	ld a, b
	and 7
	ld b, a
	ld a, 1
	inc b
.shift
	dec b
	jr z, .done
	add a
	jr .shift
.done
	pop bc
	ret

; ============================================================
; WitchChallengeIsRunActive - d = a rolled witch challenge id (1-based). Carry
; SET when the run already has it, so PCWitchSetup rolls again: a bargain whose
; downside is already on would pay a prize for nothing. Challenge 12 is both
; recoil halves, so it only counts when both are on. Ids with no run
; counterpart, and witch 1/3, which are harsher than FEWER REWARDS / LESS MONEY,
; stay offerable. The roll always ends: those ids can never be run-active.
; farcall only (keeps d). Clobbers af, bc, hl.
; ============================================================
WitchChallengeIsRunActive::
	ld a, d
	cp CHALLENGE_RECOIL_ATTACKS
	jr z, .recoilBoth
	ld c, a
	ld b, 0
	ld hl, WitchToRunChallenge - 1
	add hl, bc
	ld a, [hl]
	cp NUM_RUN_CHALLENGES
	ret nc                        ; no counterpart: carry clear
	call RunChallengeIsOn
	ret z                         ; off: carry clear from `and`
	scf
	ret
.recoilBoth
	ld a, RUN_CH_RECOIL_PHYSICAL
	call RunChallengeIsOn
	ret z
	ld a, RUN_CH_RECOIL_SPECIAL
	call RunChallengeIsOn
	ret z
	scf
	ret

DEF NO_RUN_CH EQU $FF
; Indexed by witch challenge id - 1.
WitchToRunChallenge:
	db NO_RUN_CH              ; 1  NO_REWARD_POKEMON (harsher than FEWER REWARDS)
	db RUN_CH_NO_RANDOM_ITEM  ; 2  NO_RANDOM_ITEM
	db NO_RUN_CH              ; 3  NO_MONEY (harsher than LESS MONEY)
	db RUN_CH_REDUCED_RARITY  ; 4  REDUCED_RARITY
	db RUN_CH_HIGHER_LEVELS   ; 5  INCREASED_LEVELS
	db RUN_CH_RARER_FOES      ; 6  INCREASED_RARITY_FOES
	db NO_RUN_CH              ; 7  PARTY_LIMIT
	db RUN_CH_SLOWED          ; 8  SLOWED_POKEMON
	db NO_RUN_CH              ; 9  ALL_POISONED
	db RUN_CH_TURN_LIMIT      ; 10 TURN_LIMIT
	db NO_RUN_CH              ; 11 LEGENDARY_BOSS
	db NO_RUN_CH              ; 12 RECOIL_ATTACKS (handled in code)
	db NO_RUN_CH              ; 13 GAMBLERS_PARADISE
	db RUN_CH_SAME_MOVE       ; 14 SAME_MOVE_PENALTY
	db RUN_CH_NO_HEALING      ; 15 NO_HEALING
	db RUN_CH_RECOIL_PHYSICAL ; 16 RECOIL_PHYSICAL
	db RUN_CH_RECOIL_SPECIAL  ; 17 RECOIL_SPECIAL
	db RUN_CH_DOUBLE_PP       ; 18 DOUBLE_PP
ASSERT @ - WitchToRunChallenge == NUM_WITCH_CHALLENGES

; Heat per challenge, indexed by RUN_CH_*. Tune freely: only the Dorm PC's
; heat display and wBestHeat read these.
RunChallengeWeights:
	db 1 ; RUN_CH_REDUCED_RARITY
	db 2 ; RUN_CH_RARER_FOES
	db 2 ; RUN_CH_HIGHER_LEVELS
	db 1 ; RUN_CH_NO_RANDOM_ITEM
	db 2 ; RUN_CH_SLOWED
	db 1 ; RUN_CH_DOUBLE_PP
	db 1 ; RUN_CH_SAME_MOVE
	db 2 ; RUN_CH_TURN_LIMIT
	db 2 ; RUN_CH_NO_HEALING
	db 1 ; RUN_CH_RECOIL_PHYSICAL
	db 1 ; RUN_CH_RECOIL_SPECIAL
	db 1 ; RUN_CH_LESS_MONEY
	db 1 ; RUN_CH_PRICIER_ITEMS
	db 2 ; RUN_CH_FULL_PARTIES
	db 2 ; RUN_CH_FEWER_REWARDS
ASSERT @ - RunChallengeWeights == NUM_RUN_CHALLENGES

; ============================================================
; PostMoveChallengeEffects - e = the post-move self-damage effects that apply
; this turn, for HandlePostPlayerMoveWitchEffects ($38):
;   bit 0 same-move penalty, bit 1 recoil on physical moves, bit 2 recoil on
;   special moves.
; The witch's zone challenge supplies at most one of them (12 is both recoils),
; and the run challenges any mix on top. farcall only: e comes back.
; Clobbers af, hl.
; ============================================================
PostMoveChallengeEffects::
	ld e, 0
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .runChallenges
	ld a, [wWitchChallenge]
	ld e, %001
	cp CHALLENGE_SAME_MOVE_PENALTY
	jr z, .runChallenges
	ld e, %110
	cp CHALLENGE_RECOIL_ATTACKS
	jr z, .runChallenges
	ld e, %010
	cp CHALLENGE_RECOIL_PHYSICAL
	jr z, .runChallenges
	ld e, %100
	cp CHALLENGE_RECOIL_SPECIAL
	jr z, .runChallenges
	ld e, 0
.runChallenges
	run_challenge RUN_CH_SAME_MOVE
	jr z, .noSameMove
	set 0, e
.noSameMove
	run_challenge RUN_CH_RECOIL_PHYSICAL
	jr z, .noPhysical
	set 1, e
.noPhysical
	run_challenge RUN_CH_RECOIL_SPECIAL
	ret z
	set 2, e
	ret
