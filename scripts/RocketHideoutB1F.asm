RocketHideoutB1F_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call RocketHideoutB1FDoorCallbackScript
	call EnableAutoTextBoxDrawing
	ld hl, RocketHideout1TrainerHeaders
	ld de, RocketHideoutB1F_ScriptPointers
	ld a, [wRocketHideoutB1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wRocketHideoutB1FCurScript], a
	ret

RocketHideoutB1FDoorCallbackScript:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_ENTERED_ROCKET_HIDEOUT
	jr nz, .door_open
	CheckEventReuseA EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4
	jr nz, .play_sound_door_open
	ld a, $54 ; Door Block
	jr .set_door_block
.play_sound_door_open
	ld a, SFX_GO_INSIDE
	call PlaySound
	; BUG: should be SetEvent to avoid the SFX playing every time you enter the map
	CheckEventHL EVENT_ENTERED_ROCKET_HIDEOUT
.door_open
	ld a, $e ; Floor Block
.set_door_block
	ld [wNewTileBlockID], a
	lb bc, 8, 12
	predef_jump ReplaceTileBlock

RocketHideoutB1F_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROCKETHIDEOUTB1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROCKETHIDEOUTB1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROCKETHIDEOUTB1F_END_BATTLE

RocketHideoutB1F_TextPointers:
	def_text_pointers
	dw_const RocketHideoutB1FRocket1Text, TEXT_ROCKETHIDEOUTB1F_ROCKET1
	dw_const RocketHideoutB1FRocket2Text, TEXT_ROCKETHIDEOUTB1F_ROCKET2
	dw_const RocketHideoutB1FRocket3Text, TEXT_ROCKETHIDEOUTB1F_ROCKET3
	dw_const RocketHideoutB1FRocket4Text, TEXT_ROCKETHIDEOUTB1F_ROCKET4
	dw_const RocketHideoutB1FRocket5Text, TEXT_ROCKETHIDEOUTB1F_ROCKET5
	dw_const PickUpItemText,              TEXT_ROCKETHIDEOUTB1F_ESCAPE_ROPE
	dw_const PickUpItemText,              TEXT_ROCKETHIDEOUTB1F_HYPER_POTION
    dw_const RandomPickUpItemText,        TEXT_ROCKETHIDEOUTB1F_RANDOM
    dw_const RocketHideoutB1F_Rogue_Reward_Script_PokeballText_1, TEXT_ROCKETHIDEOUTB1F_ROGUE_REWARD_POKEBALL_1
    dw_const RocketHideoutB1F_Rogue_Reward_Script_PokeballText_2, TEXT_ROCKETHIDEOUTB1F_ROGUE_REWARD_POKEBALL_2
    dw_const RocketHideoutB1F_Rogue_Reward_Script_PokeballText_3, TEXT_ROCKETHIDEOUTB1F_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_RocketHideoutB1F_Reward_Text, TEXT_ROCKETHIDEOUTB1F_REWARD_VENDOR_1
    EXPORT TEXT_ROCKETHIDEOUTB1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm

RocketHideout1TrainerHeaders:
	def_trainers 1
RocketHideout1TrainerHeader0:
	trainer EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_0, 3, RocketHideoutB1FRocket1BattleText, RocketHideoutB1FRocket1EndBattleText, RocketHideoutB1FRocket1AfterBattleText
RocketHideout1TrainerHeader1:
	trainer EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_1, 2, RocketHideoutB1FRocket2BattleText, RocketHideoutB1FRocket2EndBattleText, RocketHideoutB1FRocket2AfterBattleText
RocketHideout1TrainerHeader2:
	trainer EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_2, 2, RocketHideoutB1FRocket3BattleText, RocketHideoutB1FRocket3EndBattleText, RocketHideoutB1FRocket3AfterBattleText
RocketHideout1TrainerHeader3:
	trainer EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_3, 3, RocketHideoutB1FRocket4BattleText, RocketHideoutB1FRocket4EndBattleText, RocketHideoutB1FRocket4AfterBattleText
RocketHideout1TrainerHeader4:
	trainer EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4, 3, RocketHideoutB1FRocket5BattleText, RocketHideoutB1FRocket5EndBattleText, RocketHideoutB1FRocket5AfterBattleText
	db -1 ; end

RocketHideoutB1FRocket1Text:
	text_asm
	ld hl, RocketHideout1TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

RocketHideoutB1FRocket2Text:
	text_asm
	ld hl, RocketHideout1TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

RocketHideoutB1FRocket3Text:
	text_asm
	ld hl, RocketHideout1TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

RocketHideoutB1FRocket4Text:
	text_asm
	ld hl, RocketHideout1TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

RocketHideoutB1FRocket5Text:
	text_asm
	ld hl, RocketHideout1TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

RocketHideoutB1FRocket5EndBattleText:
	text_far _RocketHideoutB1FRocket5EndBattleText
	text_asm
	SetEvent EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4
	ld hl, .prompt_end
	ret

.prompt_end:
	text_promptbutton
	text_end

RocketHideoutB1FRocket1BattleText:
	text_far _RocketHideoutB1FRocket1BattleText
	text_end

RocketHideoutB1FRocket1EndBattleText:
	text_far _RocketHideoutB1FRocket1EndBattleText
	text_end

RocketHideoutB1FRocket1AfterBattleText:
	text_far _RocketHideoutB1FRocket1AfterBattleText
	text_end

RocketHideoutB1FRocket2BattleText:
	text_far _RocketHideoutB1FRocket2BattleText
	text_end

RocketHideoutB1FRocket2EndBattleText:
	text_far _RocketHideoutB1FRocket2EndBattleText
	text_end

RocketHideoutB1FRocket2AfterBattleText:
	text_far _RocketHideoutB1FRocket2AfterBattleText
	text_end

RocketHideoutB1FRocket3BattleText:
	text_far _RocketHideoutB1FRocket3BattleText
	text_end

RocketHideoutB1FRocket3EndBattleText:
	text_far _RocketHideoutB1FRocket3EndBattleText
	text_end

RocketHideoutB1FRocket3AfterBattleText:
	text_far _RocketHideoutB1FRocket3AfterBattleText
	text_end

RocketHideoutB1FRocket4BattleText:
	text_far _RocketHideoutB1FRocket4BattleText
	text_end

RocketHideoutB1FRocket4EndBattleText:
	text_far _RocketHideoutB1FRocket4EndBattleText
	text_end

RocketHideoutB1FRocket4AfterBattleText:
	text_far _RocketHideoutB1FRocket4AfterBattleText
	text_end

RocketHideoutB1FRocket5BattleText:
	text_far _RocketHideoutB1FRocket5BattleText
	text_end

RocketHideoutB1FRocket5AfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, RocketHideoutB1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROCKETHIDEOUTB1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Rogue_RocketHideoutB1F_Reward_Text:
script_rogue_reward

RocketHideoutB1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

RocketHideoutB1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

RocketHideoutB1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

RocketHideoutB1FGreedyText:
	text_far _GreedyText
	text_end
