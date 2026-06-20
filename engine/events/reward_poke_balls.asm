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
    call DisableWaitingAfterTextDisplay
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
    push de
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jr nz, .done
    push de
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
    SetEvent EVENT_GOT_ROGUE_POKEMON
    ret

Rogue_Reward_Script_PokeballText_2::
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done

    .GetMon
    call DisableWaitingAfterTextDisplay
    ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
    push de
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jr nz, .done

    ld a, [wRoguePokemon2]
	ld b, a
    ld c, 5
    push de
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
    call DisableWaitingAfterTextDisplay
    ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
    push de
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
    pop de
	jr nz, .done

    ld a, [wRoguePokemon3]
	ld b, a
    ld c, 5
    push de
	call GivePokemon
    pop de
	jr nc, .done
    
	ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	ret
    
PickRewardPokeballText:
	text_far _PickPokeBallText
	text_end
    
GreedyText_Reward:
	text_far _GreedyText
	text_end