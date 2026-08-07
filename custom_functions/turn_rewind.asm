; custom_functions/turn_rewind.asm
;
; LIVE as of 2026-08-07. This was briefly cut because wiring it in overflowed
; "Battle Core" (that ROM bank had ~1 free byte). It was reattached once the
; ELEMENT PRISM work reclaimed ~117 bytes there by relocating
; HandleRecoilChallenge out to custom_functions/witch_battle_effects.asm; the
; four hooks below need 37 of those bytes. See KEY_ITEM_EFFECTS_PLAN_PC.md §5.
;
; TURN REWIND (reduced scope - see KEY_ITEM_EFFECTS_PLAN_PC.md §5). Restores
; only the player's active mon's HP/PP/status/stat-mods/battle-status from
; the START of the most recent turn - not a full battle-state snapshot.
; Refuses if no snapshot exists yet (turn 1) or if the player switched mons
; since the snapshot was taken (sTurnRewindBuf byte 0 doubles as both the
; saved wPlayerMonNumber AND, via a $ff sentinel, the "no snapshot yet" flag
; - a real party slot index is always 0-5, so $ff can never collide).
;
; Snapshot happens once per turn, at move-commit time (MainInBattleLoop's
; .selectEnemyMove seam, engine/battle/core.asm) - at that instant the state
; is still "start of turn N", so restoring it during turn N+1's menu undoes
; turn N exactly. This deliberately does NOT restore the enemy side (HP
; dealt/stat boosts applied last turn stay applied), which is a real,
; intentional asymmetry - see the plan doc.
;
; Field layout in sTurnRewindBuf (34 bytes, byte 33 spare):
;   0      wPlayerMonNumber (sentinel: $ff = no snapshot)
;   1-2    wBattleMonHP
;   3      wBattleMonStatus
;   4-7    wBattleMonPP            (NUM_MOVES, contiguous per battle_struct)
;   8-15   wBattleMonAttack..Special (contiguous per battle_struct)
;   16-23  wPlayerMonStatMods..End (contiguous named span, incl 2 pad bytes)
;   24-32  9 scattered single-byte fields (see the field list below) - each
;          copied individually rather than assumed contiguous, since only
;          the three runs above are macro-guaranteed to be adjacent

; ============================================================
; RogueSetTurnRewindLabel — called every DisplayBattleMenu entry
; (engine/battle/core.asm), right after DisplayTextBoxID. Repurposes the
; ITEM menu slot: "UNDO" if TURN REWIND is active, blank otherwise (items
; are never usable in battle any more - see HandleTurnRewindMenuSelection in
; core.asm). Only for a genuine normal battle: Safari's menu template places
; completely different text at this same screen position (x=2 start versus
; the normal template's x=10, so (10,16) lands mid-word in "THROW ROCK"),
; and the old-man tutorial drives this slot programmatically - touching
; either would corrupt them, not just look wrong.
;
; HandleTurnRewindMenuSelection (core.asm) infers "was this active" by
; re-reading the tile this routine draws, rather than a second
; GetKeyItemPower farcall - valid because key items can't change ownership
; mid-battle, and it's only reached when wBattleType is already confirmed 0
; by its own dispatch gate, so the tile is guaranteed to be one of the two
; strings below, never Safari/old-man's unrelated text.
; ============================================================
RogueSetTurnRewindLabel::
	ld a, [wBattleType]
	and a
	ret nz                          ; Safari / old-man tutorial - leave their own text alone

	ld a, TURN_REWIND
	ld [wCurItem], a
	call GetKeyItemPower            ; same bank as key_item_pocket.asm - plain call
	and a
	ld de, .BlankLabel
	jr z, .gotLabel
	ld de, .RewindLabel
.gotLabel
	hlcoord 10, 16
	jp PlaceString                  ; tail call - PlaceString's own ret covers us

.RewindLabel:
	db "UNDO@"
.BlankLabel:
	db "    @"

; ============================================================
; TurnRewindInit — call once at battle start (InitBattleCommon,
; engine/battle/core.asm). Marks "no snapshot yet" for this battle.
; ============================================================
TurnRewindInit::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, $ff
	ld [sTurnRewindBuf], a
	xor a
	ld [rRAMG], a
	ret

; ============================================================
; TurnRewindSnapshot — call once per turn, at move-commit time. No-ops if
; TURN REWIND isn't active, so the caller doesn't need to check first.
; CLOBBERS: af, bc, de, hl
; ============================================================
TurnRewindSnapshot::
	ld a, TURN_REWIND
	ld [wCurItem], a
	call GetKeyItemPower           ; same bank as key_item_pocket.asm - plain call
	and a
	ret z                          ; not active - nothing to snapshot

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a

	ld a, [wPlayerMonNumber]
	ld [sTurnRewindBuf + 0], a

	ld a, [wBattleMonHP]
	ld [sTurnRewindBuf + 1], a
	ld a, [wBattleMonHP + 1]
	ld [sTurnRewindBuf + 2], a

	ld a, [wBattleMonStatus]
	ld [sTurnRewindBuf + 3], a

	ld hl, wBattleMonPP
	ld de, sTurnRewindBuf + 4
	ld bc, NUM_MOVES
	call CopyData

	ld hl, wBattleMonAttack
	ld de, sTurnRewindBuf + 8
	ld bc, 8
	call CopyData

	ld hl, wPlayerMonStatMods
	ld de, sTurnRewindBuf + 16
	ld bc, wPlayerMonStatModsEnd - wPlayerMonStatMods
	call CopyData

	ld a, [wPlayerBattleStatus1]
	ld [sTurnRewindBuf + 24], a
	ld a, [wPlayerBattleStatus2]
	ld [sTurnRewindBuf + 25], a
	ld a, [wPlayerBattleStatus3]
	ld [sTurnRewindBuf + 26], a
	ld a, [wPlayerDisabledMove]
	ld [sTurnRewindBuf + 27], a
	ld a, [wPlayerDisabledMoveNumber]
	ld [sTurnRewindBuf + 28], a
	ld a, [wPlayerConfusedCounter]
	ld [sTurnRewindBuf + 29], a
	ld a, [wPlayerToxicCounter]
	ld [sTurnRewindBuf + 30], a
	ld a, [wPlayerSubstituteHP]
	ld [sTurnRewindBuf + 31], a
	ld a, [wPlayerNumAttacksLeft]
	ld [sTurnRewindBuf + 32], a

	xor a
	ld [rRAMG], a
	ret

; ============================================================
; TurnRewindRestore — called from the battle menu's TURN REWIND selection
; (engine/battle/core.asm). Caller has already confirmed the item is active
; (via the drawn menu label, see HandleTurnRewindMenuSelection); this only
; checks whether a usable snapshot exists.
; OUTPUT: Z set = refused (no snapshot yet, or switched since it was taken),
;         Z clear (NZ) = restored. Flags survive the farcall back to the
;         caller (Bankswitch preserves flags).
; CLOBBERS: af, bc, de, hl
; ============================================================
TurnRewindRestore::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a

	; jp, not jr: .refuse sits past the whole restore body, ~150 bytes away.
	ld a, [sTurnRewindBuf + 0]
	cp $ff
	jp z, .refuse                  ; no snapshot taken yet this battle
	ld b, a
	ld a, [wPlayerMonNumber]
	cp b
	jp nz, .refuse                 ; switched mons since the snapshot was taken

	ld a, [sTurnRewindBuf + 1]
	ld [wBattleMonHP], a
	ld a, [sTurnRewindBuf + 2]
	ld [wBattleMonHP + 1], a

	ld a, [sTurnRewindBuf + 3]
	ld [wBattleMonStatus], a

	ld hl, sTurnRewindBuf + 4
	ld de, wBattleMonPP
	ld bc, NUM_MOVES
	call CopyData

	ld hl, sTurnRewindBuf + 8
	ld de, wBattleMonAttack
	ld bc, 8
	call CopyData

	ld hl, sTurnRewindBuf + 16
	ld de, wPlayerMonStatMods
	ld bc, wPlayerMonStatModsEnd - wPlayerMonStatMods
	call CopyData

	ld a, [sTurnRewindBuf + 24]
	ld [wPlayerBattleStatus1], a
	ld a, [sTurnRewindBuf + 25]
	ld [wPlayerBattleStatus2], a
	ld a, [sTurnRewindBuf + 26]
	ld [wPlayerBattleStatus3], a
	ld a, [sTurnRewindBuf + 27]
	ld [wPlayerDisabledMove], a
	ld a, [sTurnRewindBuf + 28]
	ld [wPlayerDisabledMoveNumber], a
	ld a, [sTurnRewindBuf + 29]
	ld [wPlayerConfusedCounter], a
	ld a, [sTurnRewindBuf + 30]
	ld [wPlayerToxicCounter], a
	ld a, [sTurnRewindBuf + 31]
	ld [wPlayerSubstituteHP], a
	ld a, [sTurnRewindBuf + 32]
	ld [wPlayerNumAttacksLeft], a

; sync restored HP/status to the party slot too, exactly like TryKODefiance's
; revival does (engine/battle/core.asm, ~line 1358) - Gen 1 keeps wPartyMonN
; and wBattleMon as two separate copies that must be kept in sync manually.
	ld a, [wPlayerMonNumber]
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1HP
	call AddNTimes
	push hl
	ld a, [wBattleMonHP]
	ld [hl], a
	inc hl
	ld a, [wBattleMonHP + 1]
	ld [hl], a
	pop hl
	ld bc, MON_STATUS - MON_HP
	add hl, bc
	ld a, [wBattleMonStatus]
	ld [hl], a

	xor a
	ld [rRAMG], a
	ld a, 1
	and a                           ; a=1 -> NZ = success
	ret
.refuse
	xor a
	ld [rRAMG], a
	ret                             ; a=0 from the xor above -> Z = refused

; ============================================================
; RogueTurnRewindAttempt — the full TURN REWIND menu-selection logic.
; Reached via a single farcall from HandleTurnRewindMenuSelection
; (engine/battle/core.asm), which is kept to the bare minimum that must
; stay same-bank as DisplayBattleMenu - see that routine's comment for why.
; Handles the active check, the restore, and printing the refusal message
; (PrintText is HOME-bank and callable from anywhere, and the text stub
; below lives in this same bank, so no cross-bank stub issue). The caller
; doesn't need a return value: it unconditionally redraws the HUD and
; returns to DisplayBattleMenu either way, since a refusal here has already
; printed its own message.
;
; "Is it active" is inferred by reading back the tile
; RogueSetTurnRewindLabel already drew this DisplayBattleMenu cycle, rather
; than a second GetKeyItemPower call - valid because key items can't change
; ownership mid-battle, and HandleTurnRewindMenuSelection is only reached
; when wBattleType is already confirmed 0 by its own dispatch gate, so the
; tile is guaranteed to be one of RogueSetTurnRewindLabel's two strings.
; ============================================================
RogueTurnRewindAttempt::
	lda_coord 10, 16
	cp 'U'                          ; first char of "UNDO" - blank starts with a space
	jr nz, .refuse
	call TurnRewindRestore         ; NZ = restored, Z = refused (no snapshot / switched)
	ret nz
.refuse
	ld hl, TurnRewindRefuseText
	call PrintText
	ret

TurnRewindRefuseText:
	text_far _TurnRewindRefuseText
	text_end
