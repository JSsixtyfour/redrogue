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
	call RunChallengeWeightSum
	ld b, a
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
; RunChallengeWeightSum - a = the summed heat weights of the challenges on, and
; nothing else: what the Dorm PC list shows between runs, before Ironman and the
; difficulty are known. Clobbers af, bc, de, hl.
; ============================================================
RunChallengeWeightSum:
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
	db RUN_CH_FEWER_REWARDS   ; 7  PARTY_LIMIT (its quote assumes one reward per round)
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

; ============================================================
; RewardChallengeFlags - e = which of a stage's rewards are withheld, from the
; witch's accepted challenge and the run challenges together:
;   bit 0 hide the reward balls and trade NPC
;   bit 1 hide the random item
; FEWER REWARDS hides the balls on the rounds set in FEWER_REWARDS_ROUND_MASK.
; farcall only (e comes back). Clobbers af, bc, hl.
; ============================================================
RewardChallengeFlags::
	ld e, 0
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .runChallenges
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_REWARD_POKEMON
	jr nz, .notNoRewards
	set 0, e
.notNoRewards
	cp CHALLENGE_NO_RANDOM_ITEM
	jr nz, .runChallenges
	set 1, e
.runChallenges
	run_challenge RUN_CH_NO_RANDOM_ITEM
	jr z, .noItemRun
	set 1, e
.noItemRun
	run_challenge RUN_CH_FEWER_REWARDS
	ret z
	; b = this stage's 0-based round, as WitchZoneRound computes it
	call GetRunProgress
	and a
	jr z, .gotCount
	dec a
.gotCount
	ld b, 0
.divLoop
	cp ROUND_BATTLES
	jr c, .divDone
	sub ROUND_BATTLES
	inc b
	jr .divLoop
.divDone
	ld a, b
	cp NUM_ROGUE_ROUNDS
	ret nc                        ; Victory Road and Endless keep their rewards
	inc b
	ld a, FEWER_REWARDS_ROUND_MASK
.shift
	dec b
	jr z, .gotBit
	srl a
	jr .shift
.gotBit
	bit 0, a
	ret z
	set 0, e
	ret

; ============================================================
; RunChallengesMenu - the Dorm PC's CHALLENGES list, farcalled from RoomPC
; (custom_functions/room_pc.asm), which restores its own screen on return.
; One row per RUN_CH_* id with an ON/OFF column, RUN_CH_PAGE rows to a page
; (UP past the first row or DOWN past the last turns the page), the heat of
; the choice, and the highlighted row's description in the text box through
; RoomPrintDescription's cursor hook. A toggles the row, B leaves. While a run
; is in progress (EVENT_GOT_STARTER) the list is read only.
; wBuffer: +29 nonzero (the description hook), +8 page, +9 cursor row, +10 rows on this
; page, +11 row being drawn, +12 scratch, +14 page's first id (the scroll offset
; RoomPrintDescription adds to the cursor), +27/+28 = 0 (no ownership filter).
; Clobbers everything.
; ============================================================
DEF RUN_CH_PAGE EQU 8
DEF RUN_CH_PAGES EQU (NUM_RUN_CHALLENGES + RUN_CH_PAGE - 1) / RUN_CH_PAGE

RunChallengesMenu::
	xor a
	ld [wBuffer + 8], a
	ld [wBuffer + 9], a
	ld [wBuffer + 27], a
	ld [wBuffer + 28], a
	inc a
	ld [wBuffer + 29], a          ; RoomPrintDescription hands the draw to this bank
.redraw
	call LoadScreenTilesFromBuffer2
	ldh a, [hUILayoutFlags]
	set BIT_DOUBLE_SPACED_MENU, a ; inverted name: SET gives a 1-row stride
	ldh [hUILayoutFlags], a
	; The page's first id and how many rows it has, then the cursor kept inside it.
	ld a, [wBuffer + 8]
	add a
	add a
	add a
	ld [wBuffer + 14], a
	ld b, a
	ld a, NUM_RUN_CHALLENGES
	sub b
	cp RUN_CH_PAGE
	jr c, .gotRows
	ld a, RUN_CH_PAGE
.gotRows
	ld [wBuffer + 10], a
	dec a
	ld hl, wBuffer + 9
	cp [hl]
	jr nc, .cursorOk
	ld [hl], a                    ; the cursor was beyond this page's last row
.cursorOk
	hlcoord 0, 0
	lb bc, RUN_CH_PAGE + 1, 18    ; the rows plus the heat line
	call TextBoxBorder
	call UpdateSprites
	xor a
	ld [wBuffer + 11], a
.drawRow
	ld a, [wBuffer + 14]
	ld hl, wBuffer + 11
	add [hl]                      ; this row's RUN_CH_* id
	ld [wBuffer + 12], a
	add a
	ld c, a
	ld b, 0
	ld hl, RunChallengeNames
	add hl, bc
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ld a, [wBuffer + 11]
	inc a                         ; screen row 1 + row
	hlcoord 2, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	push hl
	call PlaceString
	pop hl
	ld bc, 14
	add hl, bc                    ; the ON/OFF column
	push hl                       ; RunChallengeIsOn returns its own hl
	ld a, [wBuffer + 12]
	call RunChallengeIsOn
	pop hl                        ; keeps the flags
	ld de, .OnText
	jr nz, .placeValue
	ld de, .OffText
.placeValue
	call PlaceString
	ld hl, wBuffer + 11
	inc [hl]
	ld a, [wBuffer + 10]
	cp [hl]
	jr nz, .drawRow
	; The heat line: HEAT n, LOCKED during a run, and the page.
	hlcoord 2, RUN_CH_PAGE + 1
	ld de, .HeatText
	call PlaceString
	CheckEvent EVENT_GOT_STARTER
	jr z, .betweenRuns
	call RunChallengeHeat         ; the run's own, Ironman and difficulty included
	ld b, a
	hlcoord 9, RUN_CH_PAGE + 1
	ld de, .LockedText
	push bc
	call PlaceString
	pop bc
	ld a, b
	jr .showHeat
.betweenRuns
	call RunChallengeWeightSum
.showHeat
	ld [wBuffer + 12], a
	ld de, wBuffer + 12
	hlcoord 7, RUN_CH_PAGE + 1
	lb bc, 1, 2
	call PrintNumber
	hlcoord 16, RUN_CH_PAGE + 1
	ld a, [wBuffer + 8]
	add CHARVAL("1")
	ld [hli], a
	ld a, CHARVAL("/")
	ld [hli], a
	ld [hl], CHARVAL("0") + RUN_CH_PAGES

	ld a, [wBuffer + 9]
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 1
	ld [hli], a                   ; wTopMenuItemY
	ld [hli], a                   ; wTopMenuItemX
	inc hl                        ; skip wTileBehindCursor
	ld a, [wBuffer + 10]
	dec a
	ld [hli], a                   ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a                   ; wMenuWatchedKeys
	xor a
	ld hl, wListScrollOffset      ; overlaps the flag below, so zero it first
	ld [hli], a
	ld [hl], a
	inc a
	ld [wMenuWatchMovingOutOfBounds], a ; a push past the ends turns the page
	ld hl, wBagPocketsFlags
	set BIT_ROOM_DESC_BOX, [hl]
	call RunChallengePrintDescription
	call HandleMenuInput
	ld hl, wBagPocketsFlags
	res BIT_ROOM_DESC_BOX, [hl]   ; leaves a alone - it still holds the keys pressed
	ld b, a
	xor a
	ld [wMenuWatchMovingOutOfBounds], a ; other menus assume it clear
	ld a, b
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	ret nz                        ; RoomPC's jp .menu restores the screen
	bit B_PAD_A, a
	jr nz, .select
	bit B_PAD_UP, a
	jr nz, .previousPage
	ld a, [wBuffer + 8]           ; DOWN past the last row: the next page, wrapping
	inc a
	cp RUN_CH_PAGES
	jr c, .newPage
	xor a
.newPage
	ld [wBuffer + 8], a
	xor a
	ld [wBuffer + 9], a           ; its first row
	jp .redraw
.previousPage
	ld a, [wBuffer + 8]
	and a
	jr nz, .notFirstPage
	ld a, RUN_CH_PAGES
.notFirstPage
	dec a
	ld [wBuffer + 8], a
	ld a, $FF
	ld [wBuffer + 9], a           ; clamped to its last row on the redraw
	jp .redraw
.select
	ldh a, [hCurrentMenuItem]
	ld [wBuffer + 9], a
	CheckEvent EVENT_GOT_STARTER
	jp nz, .redraw                ; locked: the list is only shown
	ld a, [wBuffer + 9]
	ld b, a
	ld a, [wBuffer + 14]
	add b
	call RunChallengeMask         ; hl = its byte, a = its bit
	xor [hl]
	ld [hl], a
	jp .redraw

.HeatText:
	db "HEAT@"
.LockedText:
	db "LOCKED@"
.OnText:
	db "ON @"
.OffText:
	db "OFF@"

; The highlighted row's description, drawn into the text box. The cursor-move
; hook reaches it through RoomPrintDescription (bank $2D), which cannot read
; strings in this bank, while wBuffer + 29 is nonzero. Clobbers af, bc, de, hl.
RunChallengePrintDescription::
	hlcoord 1, 14
	lb bc, 3, SCREEN_WIDTH - 2
	call ClearScreenArea
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld a, [wBuffer + 14]          ; the page's first id
	add c
	add a
	ld c, a
	ld b, 0
	ld hl, RunChallengeDescs
	add hl, bc
	ld a, [hli]
	ld d, [hl]
	ld e, a
	hlcoord 1, 14
	jp PlaceString

MACRO run_challenge_text
	; \1 = label suffix, \2 = name (14 characters at most), \3 = description
	; (two lines of 18 characters at most)
RunChallengeName\1: db \2, "@"
RunChallengeDesc\1: db \3, "@"
ENDM

RunChallengeNames:
	dw RunChallengeNameRarity, RunChallengeNameFoes, RunChallengeNameLevels
	dw RunChallengeNameItem, RunChallengeNameSlowed, RunChallengeNamePP
	dw RunChallengeNameSame, RunChallengeNameTurns, RunChallengeNameHeal
	dw RunChallengeNamePhys, RunChallengeNameSpec, RunChallengeNameMoney
	dw RunChallengeNamePrice, RunChallengeNameFull, RunChallengeNameFewer
RunChallengeDescs:
	dw RunChallengeDescRarity, RunChallengeDescFoes, RunChallengeDescLevels
	dw RunChallengeDescItem, RunChallengeDescSlowed, RunChallengeDescPP
	dw RunChallengeDescSame, RunChallengeDescTurns, RunChallengeDescHeal
	dw RunChallengeDescPhys, RunChallengeDescSpec, RunChallengeDescMoney
	dw RunChallengeDescPrice, RunChallengeDescFull, RunChallengeDescFewer
ASSERT (RunChallengeDescs - RunChallengeNames) == NUM_RUN_CHALLENGES * 2

	run_challenge_text Rarity, "POOR REWARDS", "Rewards roll less<NEXT>rare Pokemon."
	run_challenge_text Foes, "RARER FOES", "Trainers field<NEXT>rarer Pokemon."
	run_challenge_text Levels, "HIGHER LEVELS", "Trainer levels go<NEXT>up by a tenth."
	run_challenge_text Item, "NO RANDOM ITEM", "No random item<NEXT>on each route."
	run_challenge_text Slowed, "SLOWED", "Speed of your team<NEXT>is halved."
	run_challenge_text PP, "DOUBLE PP", "Your moves use up<NEXT>2 PP per use."
	run_challenge_text Same, "SAME MOVE HURT", "Repeating a move<NEXT>costs 1/8 max HP."
	run_challenge_text Turns, "TURN LIMIT", "Battles drain HP<NEXT>after a turn limit."
	run_challenge_text Heal, "NO HEALING", "No medicine used<NEXT>outside battle."
	run_challenge_text Phys, "PHYS RECOIL", "Physical moves<NEXT>recoil you 1/4."
	run_challenge_text Spec, "SPEC RECOIL", "Special moves<NEXT>recoil you 1/4."
	run_challenge_text Money, "LESS MONEY", "Prize money is<NEXT>cut by a quarter."
	run_challenge_text Price, "PRICIER ITEMS", "Marts charge a<NEXT>quarter extra."
	run_challenge_text Full, "FULL PARTIES", "Trainers always<NEXT>field full teams."
	run_challenge_text Fewer, "FEWER REWARDS", "No Pokemon rewards<NEXT>after gym 1 and 5."

; ============================================================
; RunChallengesRecordsShow - RECORDS' CHALLENGES pages (RoomRecordsMenu):
; 1/2 each run challenge with + once cleared with it on, - if not (the same
; bit in wChallengeBadges / Hi); 2/2 the badges with no toggle and BEST HEAT.
; A turns the page, B leaves. Clobbers everything.
; ============================================================
RunChallengesRecordsShow::
	xor a
	ld [wBuffer + 1], a           ; page
.page
	call ClearScreen
	hlcoord 0, 0
	lb bc, 16, 18
	call TextBoxBorder
	hlcoord 2, 1
	ld de, .Title
	call PlaceString
	hlcoord 16, 1
	ld a, [wBuffer + 1]
	add CHARVAL("1")
	ld [hli], a
	ld a, CHARVAL("/")
	ld [hli], a
	ld [hl], CHARVAL("2")
	ld a, [wBuffer + 1]
	and a
	jr nz, .extras
	xor a
	ld [wBuffer + 2], a               ; id being drawn
.challengeRow
	ld a, [wBuffer + 2]
	add a
	ld c, a
	ld b, 0
	ld hl, RunChallengeNames
	add hl, bc
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ld a, [wBuffer + 2]
	add 2                         ; screen row 2 + id
	hlcoord 2, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	push hl
	call PlaceString
	ld a, [wBuffer + 2]
	ld hl, wChallengeBadges
	cp 8
	jr c, .lowIds
	sub 8
	ld hl, wChallengeBadgesHi
.lowIds
	call .bitSet
	pop hl
	ld bc, 15
	add hl, bc                    ; the marker column
	call .placeMarker
	ld hl, wBuffer + 2
	inc [hl]
	ld a, [hl]
	cp NUM_RUN_CHALLENGES
	jr c, .challengeRow
	jr .wait
.extras
	xor a
	ld [wBuffer + 2], a               ; BIT_CHBADGE_* being drawn
.extraRow
	ld a, [wBuffer + 2]
	add a
	ld c, a
	ld b, 0
	ld hl, .ExtraNames
	add hl, bc
	ld a, [hli]
	ld d, [hl]
	ld e, a
	ld a, [wBuffer + 2]
	add 3                         ; screen row 3 + badge
	hlcoord 2, 0
	ld bc, SCREEN_WIDTH
	call AddNTimes
	push hl
	call PlaceString
	ld a, [wBuffer + 2]
	ld hl, wChallengeBadges2
	call .bitSet
	pop hl
	ld bc, 15
	add hl, bc
	call .placeMarker
	ld hl, wBuffer + 2
	inc [hl]
	ld a, [hl]
	cp NUM_CHBADGE_EXTRA
	jr c, .extraRow
	hlcoord 2, 11
	ld de, .BestHeat
	call PlaceString
	ld de, wBestHeat
	hlcoord 13, 11
	lb bc, 1, 3
	call PrintNumber
.wait
	call UpdateSprites
	call WaitForTextScrollButtonPress
	ldh a, [hJoy5]
	bit B_PAD_B, a
	ret nz
	ld a, [wBuffer + 1]
	xor 1
	ld [wBuffer + 1], a
	jp .page

; a = bit 0-7, hl = a byte -> NZ if that bit is set. Clobbers af, b.
.bitSet
	ld b, a
	ld a, 1
	inc b
.shift
	dec b
	jr z, .shifted
	add a
	jr .shift
.shifted
	and [hl]
	ret

; NZ (from .bitSet) -> "+", else "-", at hl.
.placeMarker
	ld a, CHARVAL("-")
	jr z, .gotMarker
	ld a, CHARVAL("+")
.gotMarker
	ld [hl], a
	ret

.Title
	db "CHALLENGES@"
.BestHeat
	db "BEST HEAT@"
.ExtraNames
	dw .Ironman, .SetStyle, .NoGifts, .Three, .Six, .All
	ASSERT 6 == NUM_CHBADGE_EXTRA
.Ironman:  db "IRONMAN@"
.SetStyle: db "SET STYLE@"
.NoGifts:  db "NO GIFTS@"
.Three:    db "3+ AT ONCE@"
.Six:      db "6+ AT ONCE@"
.All:      db "ALL AT ONCE@"
