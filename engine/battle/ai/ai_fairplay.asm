; AI Overhaul Phase 7: fair play as a tier axis. See AI_OVERHAUL_PLAN.md.
;
; Design decision (2026-08-25): hide the player's MOVESET only. Type,
; status, HP and stat stages stay readable at every tier forever, since a
; human opponent can see all of those on screen too - hiding them would read
; as artificial, not fair. That makes this file's one job narrow: record which
; of the player's moves have actually been used this battle, by which party
; member, into wAISeenPlayerMoveMask (the successor of Gen 2's wPlayerUsedMoves).
; AIGetPlayerMoveN (ai_accessors.asm, bank $0E) is the sole consumer, and the
; sole routine Phase 7 edits - see its header for how the two tiers diverge.
;
; PLACEMENT: called once per player turn, not from inside the per-move scoring
; loop, so the Phase 2a "must live in bank $0E" rule does not apply here - see
; ROM_BIBLE.md section 5 and the Phase 4/5/6 precedent for "called
; occasionally, not in the hot per-move loop" AI code living in this pinned
; bank instead. Its own hook site, engine/battle/core.asm's PlayerCanExecuteMove,
; is in Battle Core (bank $0F), which ROM_BIBLE.md records as CLOSED (23 bytes
; minimum) as of Phase 6 - so the hook there is a single farcall, and every
; byte of real logic lives here instead.
;
; REGISTER CONTRACT: deliberately the safest shape a farcall can have in this
; codebase - NO arguments in or out. AITrackSeenPlayerMove reads
; wPlayerSelectedMove and wBattleMonMoves directly (both plain WRAM, already
; live and correct at the hook site) and returns nothing the caller consumes.
; This sidesteps the entire recurring cross-bank register-contract bug class
; (project_cross_bank_call_bug_recurrence) by construction: there is no
; argument register for a nested farcall or a callee's own scratch usage to
; clobber out from under the caller.

; RELOCATED 2026-09-29 from $2C (16 B free on Red) to $0E, to make room for
; the B4 switch-in survival hook in AIReplacementIsBetter. Safe to move: the
; only caller farcalls it with no register contract (above), and nothing
; else in $2C references it.
SECTION "Trainer AI Fair Play", ROMX, BANK[$0E]

; Finds wPlayerSelectedMove's slot in the player's real moveset and sets that
; slot's bit for the active party member (wPlayerMonNumber) in
; wAISeenPlayerMoveMask, so a later fair-play query through
; AIGetPlayerMoveN(slot) returns it for this mon only. Layout: see ram/wram.asm.
;
; Called from PlayerCanExecuteMove right after DisplayUsedMoveText, i.e. once
; the move has genuinely been selected and announced for this turn (a
; paralyzed/asleep/frozen player returns via ExecutePlayerMoveDone earlier and
; never reaches this hook at all, so nothing gets falsely "revealed"). Fires
; whether the move hits or misses, matching Gen 2's own DisplayUsedMoveText
; hook point - a miss still shows the player what move was chosen.
; Clobbers af, bc, de, hl.
AITrackSeenPlayerMove::
	ld a, [wPlayerSelectedMove]
	and a
	ret z ; defensive: 0 is never a real move, so there is nothing to reveal
	ld c, a ; c = the move id just used
	ld hl, wBattleMonMoves
	ld b, 1 ; b = this slot's bit within the party member's nibble
.findSlot
	ld a, [hli]
	cp c
	jr z, .found
	sla b
	bit NUM_MOVES, b
	jr z, .findSlot
	ret ; not in the real moveset (should not happen) - nothing to record
.found
	ld a, [wPlayerMonNumber]
	srl a ; a = mask byte, carry = odd party slot (high nibble)
	jr nc, .gotNibble
	swap b
.gotNibble
	ld e, a
	ld d, 0
	ld hl, wAISeenPlayerMoveMask
	add hl, de
	ld a, [hl]
	or b
	ld [hl], a
	ret
