; Light Screen / Reflect: an "actions bought" handler (2026-11-12). INCLUDEd into
; "Battle Engine 7" (bank $0E); AI_SMART's dispatch table reaches AISmart_Screen.
;
; WHY. Measured over 250 autoplay seeds: Light Screen was the AI's most picked
; setup move and 69% of the ones that ran were wasted (the user fainted without
; acting again). Every one faced a player whose REAL moveset was mixed, and a
; screen in this engine protects only its user (EnemySendOutFirstMon clears it)
; and is ignored by critical hits (core.asm, the crit resets both stats).
;
; THE TEST. Count the actions our mon gets before the player's best believed hit
; (fair play, max roll) KOs it:
;   without the screen, attacking: k hits to KO us; we act k times if faster,
;   k - 1 if slower (the hit lands first each turn);
;   with the screen: this turn is spent, and from the next hit on the player's
;   best is the best believed hit estimated with the screen up (the engine's own
;   damage path, CP4), so a mixed moveset buys little. Faster: k' hits at that
;   rate, k' - 1 actions.
;   Slower: this turn's hit lands unscreened first, then the rest.
; More actions with it: encourage (by AI_STRONG if two or more); fewer: discourage
; strongly (a turn for nothing, the old wrong-category case); equal: no change.
; AI_SCREEN_FASTER_ONLY (ai_constants.asm) withholds the encouragement from a
; slower mon, for the A/B that decides whether speed should be required.
;
; SCRATCH: wBuffer + 20..29 while AI_SMART runs. AI_DAMAGE (+20..27) and AI_PLAN
; (+20..28) write those bytes later in the decision; AI_SETUP's +29 is spent.

; Dispatch contract (ai_dispatch): a = magnitude, carry = encourage, nc = discourage
; (a = 0: no change). Clobbers af, bc, de, hl.
AISmart_Screen:
	call AIPlayerBestHitByCategory
	ld hl, wBuffer + AI_BUF_SCREEN_HITS
	ld de, 0
	call .max
	call .max
	call .max ; de = the player's best hit, any kind
	ld a, d
	ld [wBuffer + AI_BUF_SCREEN_BEST], a
	ld a, e
	ld [wBuffer + AI_BUF_SCREEN_BEST + 1], a
	or d
	ret z ; no damaging move believed: no opinion (a = 0, carry clear)
; Rescan with the screen staged (AI review CP4, 2026-11-12): set its bit in
; wEnemyBattleStatus3 and the estimator's GetDamageVarsForPlayerAttack doubles
; our Defense or Special exactly as the real hit will, through the 999 cap and the
; /4 scaling, which halving the finished damage did not model (a 999 stat gains
; nothing from a screen). An opposite screen already up stays in the byte, and a
; near-certain crit ignores the bit in both scans. The byte is put back as found.
	ld a, [wEnemyMoveEffect]
	cp REFLECT_EFFECT
	ld b, 1 << HAS_REFLECT_UP
	jr z, .stage
	ld b, 1 << HAS_LIGHT_SCREEN_UP
.stage
	ld a, [wEnemyBattleStatus3]
	push af
	or b
	ld [wEnemyBattleStatus3], a
	call AIPlayerBestHitByCategory
	pop af
	ld [wEnemyBattleStatus3], a
	ld hl, wBuffer + AI_BUF_SCREEN_HITS
	ld de, 0
	call .max
	call .max
	call .max ; de = the player's best hit once the screen is up
	ld a, d
	ld [wBuffer + AI_BUF_SCREEN_AFTER], a
	ld a, e
	ld [wBuffer + AI_BUF_SCREEN_AFTER + 1], a
	call AIEnemyIsFaster ; carry = we act first
	jr nc, .slower
; Faster: k actions without; with it, k' - 1 (the screen took this turn).
	call .bestHits
	push af ; a = without
	ld hl, wBuffer + AI_BUF_SCREEN_AFTER
	call .loadDE
	call .ourHits
	dec a ; a = with
	pop bc ; b = without
	jr .compare
.slower
; Slower: k - 1 actions without. With it, this turn's unscreened hit lands first.
	call .bestHits
	dec a
	push af ; a = without
	ld hl, wBuffer + AI_BUF_SCREEN_BEST
	call .loadDE
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld c, [hl]
	ld b, a ; bc = our HP
	ld a, c
	sub e
	ld l, a
	ld a, b
	sbc d
	ld h, a ; hl = HP after the first hit
	jr c, .noScreenTurn
	or l
	jr z, .noScreenTurn
	push hl
	ld hl, wBuffer + AI_BUF_SCREEN_AFTER
	call .loadDE
	pop hl
	call .hitsOn
	dec a ; a = with
	jr .slowerWith
.noScreenTurn
	xor a ; the first hit KOs us: the screen never helps
.slowerWith
	pop bc ; b = without
IF AI_SCREEN_FASTER_ONLY
	cp b
	jr c, .compare
	jr z, .compare
	ld a, b ; a slower mon is never encouraged to screen
ENDC
.compare ; a = actions with the screen, b = without
	sub b
	jr z, .none
	jr c, .worse
	cp 2
	ld a, AI_STRONG ; ld keeps the flags
	jr nc, .encourage
	ld a, AI_NUDGE
.encourage
	scf
	ret
.worse
	ld a, AI_STRONG
	and a
	ret
.none
	xor a
	ret

; a = hits for the player's best (unscreened) hit to KO us. Clobbers af, b, de, hl.
.bestHits
	ld hl, wBuffer + AI_BUF_SCREEN_BEST
	call .loadDE
; a = hits for de per hit to KO our current HP. Clobbers af, b, hl.
.ourHits
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld l, [hl]
	ld h, a
; a = hits for de per hit to take hl HP: 1 to AI_SG_MAX_HITS, else
; AI_SG_MAX_HITS + 1 (also for de = 0). Clobbers af, b, hl.
.hitsOn
	ld a, d
	or e
	ld a, AI_SG_MAX_HITS + 1
	ret z
	ld b, 0
.hit
	inc b
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	jr c, .reached
	or l
	jr z, .reached
	ld a, b
	cp AI_SG_MAX_HITS
	jr c, .hit
	inc b
.reached
	ld a, b
	ret

; de = the big-endian word at hl. Clobbers a, hl.
.loadDE
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ret

; de = max(de, the big-endian word at hl); hl += 2. Clobbers a.
.max
	push bc
	ld a, [hli]
	ld b, a
	ld c, [hl]
	inc hl
	ld a, e
	sub c
	ld a, d
	sbc b ; carry iff de < bc
	jr nc, .keep
	ld d, b
	ld e, c
.keep
	pop bc
	ret

; Fills AI_BUF_SCREEN_HITS with the largest possible delivery into us of the
; player's believed moves, per kind: physical, special (both big-endian words)
; and fixed (power 0-1: Seismic Toss, Night Shade, Super Fang and the like, which
; no screen touches; status moves land here at 0). A near-certain crit (Slash
; from a fast mon, AI review CP2) also goes to fixed: a crit ignores screens.
; Borrows the wPlayerMove* block
; as _AIScanPlayerMovesForKO does and puts it back. Clobbers af, bc, de, hl.
AIPlayerBestHitByCategory:
	ld hl, wBuffer + AI_BUF_SCREEN_HITS
	xor a
	ld b, 6
.clear
	ld [hli], a
	dec b
	jr nz, .clear
	ld hl, wPlayerMoveNum
	ld de, wBuffer + AI_BUF_MOVESAVE
	ld bc, MOVE_LENGTH
	call CopyData
	xor a
	ld [wBuffer + AI_BUF_SCANSLOT], a
.nextSlot
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	cp NUM_MOVES
	jr nc, .done
	call AIGetPlayerMoveN
	and a
	jr z, .skip ; unrevealed with no guess, or an empty slot
	call AIReadMoveIntoPlayerBlock
	farcall AIEstimatePlayerMoveDamage ; carry = estimated as a crit (ai_crit.asm)
	push af
	call AIAdjustPlayerDamageForPossibleDelivery
	pop af
	ld hl, wBuffer + AI_BUF_SCREEN_HITS + 4 ; fixed
	jr c, .bucket ; a near-certain crit ignores screens, like fixed damage
	ld a, [wPlayerMovePower]
	cp 2
	jr c, .bucket
	ld hl, wBuffer + AI_BUF_SCREEN_HITS ; physical
	ld a, [wPlayerMoveType]
	cp SPECIAL
	jr c, .bucket
	ld hl, wBuffer + AI_BUF_SCREEN_HITS + 2 ; special
.bucket ; keep the larger of the estimate and the word at hl
	ld a, [wAIDamageEstimate + 1]
	inc hl
	sub [hl]
	dec hl
	ld a, [wAIDamageEstimate]
	sbc [hl]
	jr c, .skip ; this move is smaller
	ld a, [wAIDamageEstimate]
	ld [hli], a
	ld a, [wAIDamageEstimate + 1]
	ld [hl], a
.skip
	ld hl, wBuffer + AI_BUF_SCANSLOT
	inc [hl]
	jr .nextSlot
.done
	jp _AIScanPlayerMovesForKO.restorePlayerMove
