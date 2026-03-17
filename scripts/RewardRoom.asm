RewardRoom_Script:
    ;CheckEvent EVENT_ENTER_ROOM
    ;jr nz, .check_2
    
    ;SetEvent EVENT_ENTER_ROOM
    ;call rogue_pokemon_randomized_batch
    
    .check_2
    ;CheckEvent EVENT_GOT_ROGUE_POKEMON
    ;jr nz, .default
    
    ;call Rogue_Pokemon_Display_1
    
    .default
	jp EnableAutoTextBoxDrawing

RewardRoom_TextPointers:
	def_text_pointers
	dw_const Route2SignText,             TEXT_ROUTE2_OPTION_1
    dw_const Route2SignText,             TEXT_ROUTE2_OPTION_2
	

RewardRoom1SignText:
	text_far _Route2SignText
	text_end

RewardRoom2SignText:
	text_far _Route2DiglettsCaveSignText
	text_end
    
Rogue_Route2_Script_PokeballText_1:
	text_asm
    CheckEvent EVENT_GOT_ROGUE_POKEMON
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickPokeballText
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
    
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    SetEvent EVENT_GOT_ROGUE_POKEMON
    
    .done
	jp TextScriptEnd
