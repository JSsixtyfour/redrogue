; pokeballs used for rewards
; d should be the toggleable item for each stage

Rogue_Reward_Script_PokeballText_1::
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon1]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
    
    ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd
    
Rogue_Reward_Script_PokeballText_2::
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon2]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
    
	ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd

Rogue_Reward_Script_PokeballText_3::
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText_Reward
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickRewardPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

    ld a, [wRoguePokemon3]
	ld b, a
    ld c, 5
	call GivePokemon
	jr nc, .done
    
	ld a, d
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd
    
PickRewardPokeballText:
	text_far _PickPokeBallText
	text_end
    
GreedyText_Reward:
	text_far _GreedyText
	text_end