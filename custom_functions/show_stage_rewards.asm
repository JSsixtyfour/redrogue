; custom_functions/show_stage_rewards.asm
;
; ============================================================
; RogueShowStageRewards - show the stage's reward objects now.
;
; For a stage that hides its reward pokeballs and trade NPC at setup and
; reveals them later (SS Anne B1F: once all five SSAnneB1FRooms trainers are
; beaten). Shows the same set RogueRefresh (engine/events/rogue_reward_menu.asm)
; would: trade NPC in place of pokeball 1 while BIT_ROGUE_TRADE_ACTIVE, and
; nothing at all under the witch's no-reward-pokemon challenge. Keep the two in
; step. The stage's random item is not touched (it may already be picked up).
;
; Must run on the stage map itself (ShowObject calls UpdateSprites).
; farcall only. Clobbers everything.
; ============================================================
RogueShowStageRewards::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .show
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_REWARD_POKEMON
	ret z                          ; that challenge keeps them hidden
.show
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	jr z, .gotFirst
	ld a, TOGGLE_ROGUE_TRADE_NPC
.gotFirst
	call .showObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	call .showObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
.showObject
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject
