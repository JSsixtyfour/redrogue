; custom_functions/rogue_boss_after_battle.asm
;
; ============================================================
; RogueBossAfterBattle - the decision half of every route boss's
; AfterBattleText (the boss in slot 5: its re-talk / post-battle line).
;
; It lives out here, not in each route, because the route scripts sit in the
; tightest map banks (Route 1's bank had 3 bytes free when this was written).
; Each route keeps only a small stub: compute "all of the route's trainers beaten", farcall this,
; then act on the answer in d.
;
; The rules:
;   - reward not claimed AND all trainers beaten (ROUTE_BATTLES, boss included) -> open the reward menu.
;     EVENT_ROGUE_POKEMON_OFFERED is set here so the map script's auto-offer
;     cannot fire it a second time (Tower 7F shows this text automatically at
;     the end of every rocket battle).
;   - otherwise the boss says its own normal after-battle line - unless the
;     talking sprite is a mini-boss, which gets its own line, printed here.
;
; The mini-boss test reads the TALKING sprite's trainer class, the byte
; MiniBossApplyStageTrainer patches (wMapSpriteExtraData + (slot-1)*2), not
; BIT_MINIBOSS_ACTIVE. That covers Victory Road's static Rival too, and needs
; no list of which maps Giovanni can appear on.
;
; INPUT:  e = 0 iff all of the route's trainers are beaten
;         hSpriteIndex = the talking sprite (set by DisplayTextID / the caller)
; OUTPUT: d = BOSS_AFTER_NORMAL  caller prints its own after-battle line
;         d = BOSS_AFTER_REWARD  caller opens its reward menu (DisplayTextID)
;         d = BOSS_AFTER_DONE    mini-boss line already printed; caller just ends
;   The answer is in d because farcall's Bankswitch keeps only d/e/flags.
; Clobbers everything else.
; ============================================================
	const_def
	const BOSS_AFTER_NORMAL ; 0
	const BOSS_AFTER_REWARD ; 1
	const BOSS_AFTER_DONE   ; 2

RogueBossAfterBattle::
	call Delay3
	CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr nz, .talk
	ld a, e
	and a
	jr nz, .talk
	SetEvent EVENT_ROGUE_POKEMON_OFFERED
	ld d, BOSS_AFTER_REWARD
	ret

.talk
	ld d, BOSS_AFTER_NORMAL
	ldh a, [hSpriteIndex]
	and a
	ret z                           ; no sprite (defensive): normal line
	dec a
	add a
	ld c, a
	ld b, 0
	ld hl, wMapSpriteExtraData
	add hl, bc
	ld a, [hl]                      ; talking sprite's trainer class
	ld hl, RivalMiniBossAfterBattleText
	cp OPP_RIVAL_MINIBOSS
	jr z, .miniBoss
	ld hl, GiovanniMiniBossAfterBattleText
	cp OPP_GIOVANNI_MINIBOSS
	ret nz
.miniBoss
	call PrintText
	ld d, BOSS_AFTER_DONE
	ret


RivalMiniBossAfterBattleText:
	text "I heard #MON"
	line "LEAGUE has many"
	cont "tough trainers!"

	para "I have to figure"
	line "out how to get"
	cont "past them!"

	para "You should quit"
	line "dawdling and get"
	cont "a move on!"
	done

GiovanniMiniBossAfterBattleText:
	text "I see that you"
	line "raise #MON"
	cont "with utmost care."

	para "A child like you"
	line "would never"
	cont "understand what I"
	cont "hope to achieve."

	para "I shall step"
	line "aside this time!"

	para "I hope we meet"
	line "again..."
	done
