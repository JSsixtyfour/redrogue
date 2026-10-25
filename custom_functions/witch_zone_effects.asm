; Witch challenge effects that run in the overworld rather than in battle.
;
; Own SECTION, pinned to $3A in layout.link: "rogue" ($38, where
; witch_battle_effects.asm lives) overflowed the debug build by 23 bytes when
; this was added there, 2026-10-03, and the turn/party-limit helpers followed
; to give $38 its room back. Everything here is reached only by farcall/farjp
; (engine/events/poison.asm, RogueRefresh in engine/events/rogue_reward_menu.asm,
; StartBattle in core.asm, PCWitchSetup in witch_setup.asm), so BANK() resolves
; wherever it sits.

SECTION "Witch Zone Effects", ROMX

; ============================================================
; WitchCheckPartyLimit
; Challenge 7 (PARTY_LIMIT): enter a stage with at most X #MON. At departure
; through a lobby stage door, a party larger than
; wPartyLimit (precomputed at roll time by WitchPrepChallengeParams) breaks
; the bargain: BIT_WITCH_ACCEPTED is cleared, so PCWitchSetup grants no prize
; on the next lobby visit and every challenge effect stops, and the player
; is told.
;
; Called only by WarpFound2 after it records the source map/warp, before the
; transition. Only lobby warps 2/3 count. No pending flag is needed: later
; steps, battles, reloads and internal warps never call this entry check.
; Captures and reward gifts after entry may grow the party normally.
; ============================================================
WitchCheckPartyLimit::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_PARTY_LIMIT
	ret nz
	ld a, [wWarpedFromWhichMap]
	cp INDIGO_PLATEAU_LOBBY
	ret nz
	ld a, [wWarpedFromWhichWarp]
	cp 2
	ret c ; a bottom exit, not a zone door
	cp 4
	ret nc ; only the two stage doors
	ld a, [wPartyLimit]
	ld b, a
	ld a, [wPartyCount]
	cp b
	ret c
	ret z ; count <= limit: bargain kept
	ld hl, wRogueFlagsBitfield
	res BIT_WITCH_ACCEPTED, [hl]
	xor a
	ldh [hJoyIgnore], a
	call UpdateSprites
	call EnableAutoTextBoxDrawing
	ld a, TEXT_WITCH_BARGAIN_BROKEN
	ldh [hTextID], a
	jp DisplayTextID

; ============================================================
; WitchReapplyPoison
; Challenge 9 (ALL_POISONED): "Your whole team will be poisoned the whole zone".
; Sets PSN on every party mon that is alive and has no other status. Called:
;   - every overworld step, via ApplyOutOfBattlePoisonDamage, so an Antidote or a
;     heal lasts one step and
;     gyms are covered too;
;   - once at stage load, from the end of RogueRefresh, so the team is
;     poisoned before the first step.
; Skipped in the lobby: the challenge is accepted there, but the zone has not
; started. Fainted mons are left alone (revives expect a clean status), and so
; is a mon already asleep/burned/frozen/paralysed - Gen 1 statuses are
; exclusive, and stacking PSN on top would give it two at once.
; Clobbers af, b, de, hl.
; ============================================================
WitchReapplyPoison::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_ALL_POISONED
	ret nz
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	ret z
	ld a, [wPartyCount]
	and a
	ret z
	ld b, a
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
.loop
	push hl
	ld a, [hli]
	or [hl]
	jr z, .next ; fainted
	ASSERT MON_STATUS == MON_HP + 3
	inc hl
	inc hl ; status
	ld a, [hl]
	and a
	jr nz, .next ; already statused (PSN included)
	set PSN, [hl]
.next
	pop hl
	add hl, de
	dec b
	jr nz, .loop
	ret

; ============================================================
; WitchInitTurnLimit
; Called from StartBattle (engine/battle/core.asm). If CHALLENGE_TURN_LIMIT is
; active, resets the per-battle turn counter and computes this battle's limit
; as 6 + WitchZoneRound. WitchPrepChallengeParams computes the same number at
; offer time for the witch's text, so the X she quotes is the X you get.
;
; Relocated out of core.asm 2026-09-02 for bank $0F pressure, and out of
; "rogue" ($38) into this section 2026-10-03 for the same reason. No inputs and no
; outputs, and StartBattle has nothing live in a/bc/hl across this point - it
; reloads hl, bc and d immediately afterwards - so the farcall's clobbers cost
; nothing. The three in-line gates that used to jump to .noTurnLimitInit
; become plain `ret`s here, which is where a few of the reclaimed bytes come
; from.
; ============================================================
WitchInitTurnLimit::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_TURN_LIMIT
	ret nz
	xor a
	ld [wBattleTurnCount], a
	; fall through
WitchComputeTurnLimit:
	call WitchZoneRound
	add 6            ; limit = 6 + round
	ld [wBattleTurnLimit], a
	ret

; ============================================================
; WitchZoneRound
; a = the round the CURRENT zone belongs to, capped at NUM_ROGUE_ROUNDS:
;   min((wBattleCount - 1) / ROUND_BATTLES, NUM_ROGUE_ROUNDS)
; wBattleCount is the count BEFORE the win, and the leader is fought at a
; multiple of ROUND_BATTLES (step 0, see constants/round_constants.asm), so
; plain wBattleCount / ROUND_BATTLES put the leader one round ahead of the gym
; trainers before them - one extra turn for the leader only. The - 1 puts
; every battle of a zone, leader included, in the same round. In the lobby
; wBattleCount is already the count of the zone's first battle, so the offer
; text and the battles agree.
; Clobbers b.
; ============================================================
WitchZoneRound:
	ld a, [wBattleCount]
	and a
	jr z, .gotCount ; 0 only before Oak's Lab; treat as round 0
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
	cp NUM_ROGUE_ROUNDS + 1
	ret c
	ld a, NUM_ROGUE_ROUNDS ; cap round at the last
	ret

; ============================================================
; WitchPrepChallengeParams
; Called from WitchSetup right after the challenge is rolled. Precomputes the
; number the challenge text prints with text_decimal: challenge 10's turn
; limit, challenge 7's party limit. Both sit in a UNION with the other
; per-challenge parameters, which is safe because only one challenge is ever
; active.
; Clobbers af, b.
; ============================================================
WitchPrepChallengeParams::
	ld a, [wWitchChallenge]
	cp CHALLENGE_TURN_LIMIT
	jr z, WitchComputeTurnLimit
	cp CHALLENGE_PARTY_LIMIT
	ret nz
	; Challenge 7: starter + all progression reward Pokemon - 1, capped at 5.
	; The initial Reward Room adds one; each completed route adds another.
	; WitchZoneRound counts prior rounds. A gym-next visit also includes this
	; round's route reward (including a paired gym's replacement Reward Room).
	; Thus round 2's route allows 2, its gym 3; round 3 allows 3 then 4.
	; Use progression, not actual party size: purchases, rentals, captures or
	; skipped rewards never change the quote. Entry-only enforcement is unchanged.
	call WitchZoneRound
	inc a ; starter + initial reward - 1 + prior rounds' route rewards
	ld b, a
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_GYM_NEXT, a
	ld a, b
	jr z, .capPartyLimit
	inc a ; this round's route reward is available before its gym
.capPartyLimit
	cp PARTY_LENGTH
	jr c, .partyLimitOk
	ld a, PARTY_LENGTH - 1
.partyLimitOk
	ld [wPartyLimit], a
	ret
