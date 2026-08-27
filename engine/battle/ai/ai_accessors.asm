; Player-state accessor seam (AI_OVERHAUL_PLAN.md). Every heuristic reads the
; player's state through these rather than touching wBattleMon* directly.
;
; Phase 7 (2026-08-26) landed the fair-play decision the user locked in
; 2026-08-25: hide the MOVESET only. Type, status and HP stay live at every
; tier forever - a human opponent can see all of those on screen, so hiding
; them would read as artificial rather than fair. AIGetTargetType1/2 and
; AIGetTargetStatus are therefore UNCHANGED and always return live data.
; AIGetPlayerMoveN is the one routine that branches on AI_OMNISCIENT: an
; omniscient tier (T2/T3) still reads the real wBattleMonMoves; a fair-play
; tier (T0/T1, AI_OMNISCIENT cleared in ai_core.asm's AITierLayers) reads
; wAISeenPlayerMoves instead, which only holds moves the player has actually
; used this battle (populated by AITrackSeenPlayerMove, ai_fairplay.asm, bank
; $2C, hooked at engine/battle/core.asm's PlayerCanExecuteMove). No heuristic
; needed editing: every consumer already goes through this seam.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), same bank as trainer_ai.asm and
; every AILayer* routine. These MUST be in this bank, for two independent
; reasons, and they were not until Phase 3 Step 2:
;
; 1. They are called from inside the per-move scoring loop, so the Phase 2a rule
;    applies (see ai_score_helpers.asm's header and ROM_BIBLE.md's 2026-08-25
;    entries): a plain same-bank `call` is the only cheap way to reach them, and
;    a plain `call` to another bank is undefined behaviour that assembles and
;    links silently.
;
; 2. AIGetPlayerMoveN takes its input in `a`, and `a` CANNOT survive a farcall -
;    Bankswitch's very first instruction is `ldh a, [hLoadedROMBank]`, which
;    overwrites the argument before the callee runs. So this routine is not
;    merely cheaper in-bank, it is impossible to call correctly out-of-bank
;    without changing its contract. See project_farcall_home_clobbers_a.
;
; BUG HISTORY: these lived in ai_core.asm (a separately-floated section that
; landed in bank $06) through Phase 2b, while AISmart_DreamEater in bank $0E did
; a plain `call AIGetTargetStatus`. That call resolved to $0E:7FA8 - inside this
; bank's empty tail - so on the release ROMs (padded $00 = `nop`) it slid
; through the padding and off the end of the bank into VRAM, and on the debug
; ROM (padded $FF) it hit `rst $38`. It never fired in testing only because no
; scenario gave an enemy a Dream Eater move, which is the same
; "the covered path was the no-op path" gap that hid the Phase 2a bugs.

; OUTPUT: a = the player mon's first type.
AIGetTargetType1::
	ld a, [wBattleMonType1]
	ret

; OUTPUT: a = the player mon's second type.
AIGetTargetType2::
	ld a, [wBattleMonType2]
	ret

; OUTPUT: a = the player mon's status byte.
AIGetTargetStatus::
	ld a, [wBattleMonStatus]
	ret

; INPUT:  a = move slot 0-3
; OUTPUT: a = the move id the AI believes is in that slot, 0 if none/unknown.
; Clobbers bc, de, hl.
;
; The slot number has to survive a farcall to AIHasFlag (which itself clobbers
; a/bc, and uses de/hl as its own scratch - see ai_core.asm - so neither
; register is safe to stash it in across the call). Pushed onto the stack
; instead, per project_cross_bank_call_bug_recurrence's fifth instance: trust
; the stack across a farcall, never a "this register survives" claim about a
; specific callee. POP BC (unlike POP AF) never touches flags, so the z flag
; AIHasFlag returned in is still live for the branch below.
AIGetPlayerMoveN::
	ld c, a
	push bc
	ld de, AI_OMNISCIENT
	farcall AIHasFlag ; z clear = this tier is omniscient; z set = fair play
	pop bc
	ld hl, wBattleMonMoves
	jr nz, .known ; omniscient: read the real moveset
	ld hl, wAISeenPlayerMoves ; fair play: only what has actually been shown
.known
	ld a, c
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hl]
.exit ; named for hookability (project convention); a holds the result here
	ret
