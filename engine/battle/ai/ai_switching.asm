; AI switching engine (AI_OVERHAUL_PLAN.md Phase 4).
;
; PINNED to bank $2C, deliberately, and NOT floated like ai_core.asm's section:
; ROM_BIBLE.md section 5 rule 6 ("pin any new floating section once its intended
; budget matters") applies here because Red, Blue and Debug first-fit
; independently, and Debug is consistently the tightest of the three - a floated
; section of this size could land in a different, tight bank in one variant
; only. $2C is the established relocation bank (10 KB free, already holds a
; pinned section) and section 5 rule 3 names it first for general relocated
; leaves.
;
; WHY THIS CAN LIVE OUTSIDE BANK $0E AT ALL, unlike every AILayer* routine:
; switching is decided ONCE PER TURN, from TrainerAI, not once per move from
; AIEnemyTrainerChooseMoves' same-bank `jp hl` dispatch. The Phase 2a rule that
; forces scoring-loop code into bank $0E simply does not reach this file. See
; ai_score_helpers.asm's header for that rule and why it exists.
;
; FARCALL RETURN CONVENTION, verified from home/bankswitch.asm rather than
; assumed, because it is what lets the predicates here live out-of-bank at all:
; Bankswitch's return path is `pop bc / ld a, b / ldh [hLoadedROMBank], a /
; ld [rROMB], a / ret`. NONE of those instructions touch flags, and `pop bc`
; only touches bc. So across a farcall RETURN:
;   - CARRY survives      -> a predicate may return a boolean in carry
;   - de and hl survive   -> a routine may return a value in either
;   - a and bc are DESTROYED (a is reused, bc receives the saved bank)
; This is the mirror of the better-known inbound rule (an argument cannot travel
; in a, because Bankswitch's FIRST instruction is `ldh a, [hLoadedROMBank]`).

SECTION "Trainer AI Switching", ROMX, BANK[$2C]

; Chooses which party mon the enemy sends out, replacing the first-healthy-mon
; scan that EnemySendOut used to run inline (engine/battle/core.asm). Writes the
; chosen slot to hWhichPokemon and returns; the caller falls straight through to
; its .next3 label, which reads hWhichPokemon and loads that mon.
;
; CONTRACT INHERITED FROM THE SCAN THIS REPLACES, and not optional: on return
; hWhichPokemon must name a LIVING party slot that is not the one currently out.
; The vanilla scan had no bounds check and looped until it found one, relying
; entirely on the caller never reaching here unless such a mon exists. This
; version bounds itself by wEnemyPartyCount instead, which is strictly safer,
; but the .noCandidate path is still load-bearing rather than defensive padding:
; if it were ever reached, EnemySendOut would load a fainted mon and the battle
; would break.
;
; SELECTION RULE (Phase 4 Opus portion): pick the candidate the player's PRIMARY
; type hurts least. That is the single highest-value half of "who to switch to" -
; not walking a fresh mon into a type it dies to - and it is deliberately the
; whole rule for now. AIScoreParty's fuller weight table (offensive matchup,
; HP, revealed player moves) is the Sonnet half of this phase and slots in at
; the marked call site below without changing this routine's shape.
;
; Clobbers af, bc, de, hl.
AISelectSendOut::
; Save the three bytes forged below. PreviewTypeMatchup reads its defender types
; from wEnemyMonType and its attacking type from wPlayerMoveType, so those are
; borrowed rather than passed - the same forge-and-restore shape AIEstimateDamage
; uses on the damage path, and for the same reason: the routine being reused is
; engine-exact, and reimplementing dual-type stacking a fourth time would be
; strictly worse than briefly borrowing three bytes.
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af

; The player's primary type is the attacker for every comparison in the loop, so
; it is set once here rather than per candidate.
	ld a, [wBattleMonType1]
	ld [wPlayerMoveType], a

	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a ; worse than any real multiplier (max 80)
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a  ; $ff = nothing chosen yet
	xor a
	ld [wBuffer + AI_BUF_SCANSLOT], a

.nextSlot
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	ld b, a
	ld a, [wEnemyPartyCount]
	cp b
	jr z, .done ; scanned every slot

	ld a, [wEnemyMonPartyPos]
	cp b
	jr z, .skip ; never pick the mon that is already out

; hl = &wEnemyMon1 + slot * PARTYMON_STRUCT_LENGTH
	ld hl, wEnemyMon1
	ld a, b
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes

; Fainted candidates are skipped. HP is a big-endian word at struct offset +1.
	push hl
	inc hl
	ld a, [hli]
	ld c, a
	ld a, [hl]
	or c
	pop hl
	jr z, .skip

; Forge this candidate as the "defender" PreviewTypeMatchup will read. Type1 and
; Type2 sit at struct offsets +5 and +6 (box_struct: Species, HP.w, BoxLevel,
; Status, Type1, Type2 - see macros/ram.asm).
	ld bc, 5
	add hl, bc
	ld a, [hli]
	ld [wEnemyMonType1], a
	ld a, [hl]
	ld [wEnemyMonType2], a

	farcall PreviewTypeMatchup ; -> e = multiplier in twentieths
	                           ; (0, 5, 10, 20, 40, 80). LOWER is better for us:
	                           ; it is how hard the PLAYER hits this candidate.
	                           ; e survives the farcall return - see the header.

	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	jr c, .skip ; current best is already lower (better) - keep it
	jr z, .skip ; a tie keeps the EARLIER slot, so selection stays deterministic
	            ; and the scenarios built on it cannot go flaky
	ld a, e
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a

.skip
	ld hl, wBuffer + AI_BUF_SCANSLOT
	inc [hl]
	jr .nextSlot

.done
; Restore in exactly reverse push order.
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a

	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jr z, .noCandidate
	ldh [hWhichPokemon], a
	ret

.noCandidate
; Unreachable by the contract documented above - EnemySendOut only calls here
; when a living replacement exists. Kept because the alternative on a broken
; assumption is loading a fainted mon: slot 0 at least keeps the battle
; structurally valid while making the fault obvious in a scenario's telemetry,
; rather than corrupting state silently.
	xor a
	ldh [hWhichPokemon], a
	ret
