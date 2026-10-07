; pokeballs used for rewards
; d should be the toggleable item for each stage

Rogue_Reward_Script_PokeballText_1::
    ld a, [wRogueFlagsBitfield]
    bit BIT_ROGUE_TRADE_ACTIVE, a
    jr nz, .tradeNPC
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done

    .GetMon
    push de ; d = this ball's toggle index, held across the whole INFO loop
.offer
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	; Phase 2R: name the OFFER with its form name ("A-MEOWTH", not "MEOWTH").
	; Increment 8: read THIS slot's form. wSpawnForm is one byte and all three
	; offers exist at once, so it labelled every ball with the last roll's form.
	ld a, [wRoguePokemonForm1]
	ld [wFormContextForm], a
	ld a, [wNamedObjectIndex]
	ld [wFormContextSpecies], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	; YES / NO / INFO. INFO shows the Pokedex page with this offer's form and
	; DVs, then asks again (the map was reloaded under it: rename, reprint).
	ld e, 1
	farcall RewardOfferChoice
	jr z, .offer
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jp nz, RewardBallDeclined
    push de
    ; Increment 8: the offer was NAMED as a form above; this is what makes the
    ; mon actually BE one. _AddPartyMon reads wSpawnForm, folds it into the new
    ; mon's MON_CATCH_RATE bits 5-6, and zeroes it again on the way out.
    ld a, [wRoguePokemonForm1]
    ld [wSpawnForm], a
    ld a, 1 ; and give it the DVs its INFO screen shows (slot 1)
    ld [wSpawnDVSlot], a
    ld a, [wRoguePokemon1]
	ld b, a
    ld c, 5
	call GivePokemon
    pop de
	jr nc, .done
    
    ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON

    .done
    ret

    ; trade NPC: walking up to him directly runs the same trade dialogue as the
    ; lobby's PCTraderSuperNerdText. Gate on EVENT_GOT_ROGUE_POKEMON so a player
    ; who already grabbed a different pokeball can't also cash in the trade.
    .tradeNPC
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .runTrade
    ld hl, wCompletedInGameTradeFlags
    ld a, TRADE_FOR_RANDOM
    ld c, a
    ld b, FLAG_TEST
    predef FlagActionPredef
    ld a, c
    and a
    jr nz, .runTrade        ; trade already completed elsewhere - let dialogue show its thanks text
    ld hl, GreedyText_Reward
    call PrintText
    ret
    .runTrade
    ld a, TRADE_FOR_RANDOM
    ld [wWhichTrade], a
    ldh a, [hTileAnimations]
    push af
    xor a
    ldh [hTileAnimations], a
    predef RogueDoInGameTradeDialogue
    pop af
    ldh [hTileAnimations], a
    ld hl, wCompletedInGameTradeFlags
    ld a, TRADE_FOR_RANDOM
    ld c, a
    ld b, FLAG_TEST
    predef FlagActionPredef
    ld a, c
    and a
    ret z                   ; declined or wrong mon - NPC stays interactable
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    ret nz                  ; re-talk after a completed trade: the dialogue already showed its after-trade text
    SetEvent EVENT_GOT_ROGUE_POKEMON
    ; RogueDoInGameTradeDialogue prints nothing after a TRADE_FOR_RANDOM trade.
    ; Same message as the reward menu's trade slot. It waits for its own button,
    ; so the TextScriptEnd wait is switched off to avoid a second one.
    ld hl, RewardTradedNPCText
    call PrintText
    jp DisableWaitingAfterTextDisplay

Rogue_Reward_Script_PokeballText_2::
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done

    .GetMon
    push de
.offer
    ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
	; Phase 2R: name the OFFER with its form name ("A-MEOWTH", not "MEOWTH").
	ld a, [wRoguePokemonForm2]
	ld [wFormContextForm], a
	ld a, [wNamedObjectIndex]
	ld [wFormContextSpecies], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	ld e, 2
	farcall RewardOfferChoice
	jr z, .offer
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jp nz, RewardBallDeclined
    push de

    ld a, [wRoguePokemonForm2]
    ld [wSpawnForm], a
    ld a, 2
    ld [wSpawnDVSlot], a
    ld a, [wRoguePokemon2]
	ld b, a
    ld c, 5
	call GivePokemon
    pop de
	jr nc, .done
    
	ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	ret

Rogue_Reward_Script_PokeballText_3::
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done

    .GetMon
    push de
.offer
    ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
	; Phase 2R: name the OFFER with its form name ("A-MEOWTH", not "MEOWTH").
	ld a, [wRoguePokemonForm3]
	ld [wFormContextForm], a
	ld a, [wNamedObjectIndex]
	ld [wFormContextSpecies], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	ld e, 3
	farcall RewardOfferChoice
	jr z, .offer
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jp nz, RewardBallDeclined
    push de

    ld a, [wRoguePokemonForm3]
    ld [wSpawnForm], a
    ld a, 3
    ld [wSpawnDVSlot], a
    ld a, [wRoguePokemon3]
	ld b, a
    ld c, 5
	call GivePokemon
    pop de
	jr nc, .done
    
	ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	ret
    
; NO (or B) at YES / NO / INFO: close the dialogue on that same press, instead
; of leaving the prompt up for DisplayTextID's end-of-text button wait.
RewardBallDeclined:
	ld a, 1
	ldh [hNoWaitAfterText], a
	ret

PickRewardPokeballText:
	text_far _PickPokeBallText
	text_end
    
GreedyText_Reward:
	text_far _GreedyText
	text_end

RewardTradedNPCText:
	text_far _TradedForText
	sound_get_key_item
	text_waitbutton
	text_end