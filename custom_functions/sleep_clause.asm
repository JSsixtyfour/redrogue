; custom_functions/sleep_clause.asm
;
; SLEEP CLAUSE, Smogon RBY's Sleep Clause Mod: a side may not put a second
; opposing mon to sleep while one it already put to sleep is still asleep.
; Applies to both sides, in every battle (wild included).
;
; State is one byte, wSleepClauseState: low nibble = the player's mon the enemy
; put to sleep, high nibble = the enemy's mon the player put to sleep, each as
; party slot + 1 (0 = none). Zeroed by InitBattleVariables, so sleep carried in
; from an earlier battle never counts.
;
; Only SleepEffect (opponent-inflicted sleep) records a holder. Rest writes its
; sleep counter itself in heal.asm and never comes through here, so it neither
; sets the clause nor is ever blocked by it.
;
; The holder is validated lazily: the clause is active only while that mon
; still has HP and SLP bits, and a stale holder is cleared on the spot. That
; covers waking up, Awakening/Full Heal/Poke Flute, Haze, fainting and
; switching with no hook at any of those sites. The one case it cannot tell
; apart is a holder that woke and then used Rest (its sleep would look like
; the opponent's), so RestPrecheck clears the user's side when the user is
; the holder. TURN REWIND needs no snapshot of the byte for the same reason:
; it restores the player's mon status, and the lazy check reads that status.
;
; Lives in "Bridge Extended Effects" (bank $34) because Battle Core is full;
; RestPrecheck relies on that to plain-call BridgePlayerRestIsBlocked.

; In: d = SLEEP_CLAUSE_PLAYER_SIDE / SLEEP_CLAUSE_ENEMY_SIDE, the side whose
;     party the sleep move would target.
; Out: carry = the clause is active against that side.
; Clobbers af, bc, hl. Preserves de. Farcall-safe (only d and flags cross).
SleepClauseIsActive::
	call SleepClauseGetHolder
	and a
	ret z ; no holder; `and a` cleared carry
	dec a
	ld c, a ; c = holder's party slot
	call SleepClauseActiveSlot
	cp c
	jr nz, .benched
	ld hl, wBattleMonHP
	ld a, d
	and a
	jr z, .check
	ld hl, wEnemyMonHP
	jr .check
.benched
	ld hl, wPartyMon1HP
	ld a, d
	and a
	jr z, .gotParty
	ld hl, wEnemyMon1HP
.gotParty
	ld a, c
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes ; preserves de
.check ; hl -> HP (2 bytes), status 3 bytes later in both struct layouts
	ld a, [hli]
	or [hl]
	jr z, .stale ; fainted
	inc hl
	inc hl
	ld a, [hl]
	and SLP_MASK
	jr z, .stale ; awake
	scf
	ret
.stale
	call SleepClauseClearSide
	and a
	ret

ASSERT wBattleMonStatus - wBattleMonHP == MON_STATUS - MON_HP
ASSERT wEnemyMonStatus - wEnemyMonHP == MON_STATUS - MON_HP
ASSERT MON_STATUS - MON_HP == 3

; Called by SleepEffect once the move has passed every other check, including
; the accuracy roll (Showdown's order: a miss still reads as a miss). The
; target is the side opposite hWhoseTurn.
; Out: carry = blocked, "SLEEP CLAUSE prevents it!" already printed. No carry
;      = allowed, and the target is now recorded as this side's holder.
; Preserves de: SleepEffect writes the sleep counter through it afterwards
; (measured: without this the counter went to $01xx, an MBC register).
; Clobbers af, bc, hl.
SleepClauseCheckAndClaim::
	push de
	call .run
	pop de ; leaves F intact
	ret
.run
	ldh a, [hWhoseTurn]
	xor 1
	ld d, a ; target side
	call SleepClauseIsActive
	jr c, .blocked
	call SleepClauseActiveSlot
	inc a ; slot + 1
	bit 0, d
	jr z, .gotNibble
	swap a
.gotNibble
	ld c, a
	call SleepClauseClearSide ; a = state with this side's nibble cleared
	or c
	ld [wSleepClauseState], a
	and a
	ret
.blocked
	ld hl, SleepClausePreventsText
	call PrintText
	scf
	ret

SleepClausePreventsText:
	text "SLEEP CLAUSE"
	line "prevents it!"
	prompt

; Replaces RestEffect's direct BridgePlayerRestIsBlocked farcall.
; Out: carry = Rest is blocked (Bridge status immunity). Once Rest is going
; ahead, its sleep is self-inflicted: if the user is its own side's holder
; (slept by the opponent, woke, now resting), drop the clause for that side.
; Clobbers af, bc, de, hl.
RestPrecheck::
	call BridgePlayerRestIsBlocked
	ret c
	ldh a, [hWhoseTurn]
	ld d, a ; user's side
	call SleepClauseGetHolder
	and a
	ret z
	dec a
	ld c, a
	call SleepClauseActiveSlot
	cp c
	jr nz, .done
	call SleepClauseClearSide
.done
	and a
	ret

ASSERT BANK(RestPrecheck) == BANK(BridgePlayerRestIsBlocked)

; In: d = side. Out: a = that side's holder nibble (slot + 1, 0 = none).
SleepClauseGetHolder:
	ld a, [wSleepClauseState]
	bit 0, d
	jr z, .low
	swap a
.low
	and $0f
	ret

; In: d = side. Out: a = that side's active party slot. A wild mon has no
; party, and wEnemyMonPartyPos is not maintained for it, so it is always 0.
SleepClauseActiveSlot:
	ld a, d
	and a
	jr nz, .enemy
	ld a, [wPlayerMonNumber]
	ret
.enemy
	ldh a, [hIsInBattle]
	cp 2
	ld a, 0
	ret nz ; wild battle
	ld a, [wEnemyMonPartyPos]
	ret

; In: d = side. Out: a = new wSleepClauseState with that side's nibble cleared
; (also stored).
SleepClauseClearSide:
	ld a, [wSleepClauseState]
	bit 0, d
	jr nz, .enemy
	and $f0
	jr .store
.enemy
	and $0f
.store
	ld [wSleepClauseState], a
	ret
