INCLUDE "engine/pokemon/rarity.asm"
INCLUDE "engine/rogue_pointers.asm"
INCLUDE "engine/pokemon/random_pokemon_selection.asm"

OaksLab_Script:
   CheckEvent EVENT_ESTABLISHED_STARTER
   jr nz, .default
   
   call Random
   farcall Random_Pokemon_Selection
   ld hl, LAB_POKEMON_1
   ld [hl], d
   call Random
   farcall Random_Pokemon_Selection
   ld hl, LAB_POKEMON_2
   ld [hl], d
   call Random
   farcall Random_Pokemon_Selection
   ld hl, LAB_POKEMON_3
   ld [hl], d
   SetEvent EVENT_ESTABLISHED_STARTER
   
   .default
   jp EnableAutoTextBoxDrawing


OaksLab_TextPointers:
	def_text_pointers
	dw_const Rogue_Lab_Script_PokeballText_1, TEXT_ROGUE_STARTER_POKEBALL_1
    dw_const Rogue_Lab_Script_PokeballText_2, TEXT_ROGUE_STARTER_POKEBALL_2
    dw_const Rogue_Lab_Script_PokeballText_3, TEXT_ROGUE_STARTER_POKEBALL_3

Rogue_Lab_Script_PokeballText_1:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    ld a, [LAB_POKEMON_1]
	ld [wNamedObjectIndex], a
    call GetMonName
    ld hl, PickPokeballText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jr nz, .done

	ld b, d
    ld c, 5
	call GivePokemon
	jr nc, .done
    
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
.done
	jp TextScriptEnd
    
Rogue_Lab_Script_PokeballText_2:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    call Random
    farcall Random_Pokemon_Selection

	ld b, d
    ld c, 5
	call GivePokemon
	jr nc, .done
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
    .done
	jp TextScriptEnd
    
Rogue_Lab_Script_PokeballText_3:
	text_asm
    CheckEvent EVENT_GOT_STARTER
	jr z, .GetMon
    
	ld hl, GreedyText
	call PrintText
	jr .done
    
    .GetMon
    call Random
    farcall Random_Pokemon_Selection

	ld b, d
    ld c, 5
	call GivePokemon
	jr nc, .done
	ld a, TOGGLE_ROGUE_STARTER_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
    SetEvent EVENT_GOT_STARTER
.done
	jp TextScriptEnd
    
GreedyText:
	text_far _GreedyText
	text_end
    
PickPokeballText:
	text_far _PickPokeBallText
	text_end
    
LAB_POKEMON_1:
db 0x0
LAB_POKEMON_2:
db 0x0
LAB_POKEMON_3:
db 0x0