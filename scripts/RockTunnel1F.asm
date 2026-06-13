RockTunnel1F_Script:

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
	call EnableAutoTextBoxDrawing
	ld hl, RockTunnel1TrainerHeaders
	ld de, RockTunnel1F_ScriptPointers
	ld a, [wRockTunnel1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wRockTunnel1FCurScript], a
	ret

	RogueAutoWalkScripts RockTunnel1F, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_ROCK_TUNNEL_1F, TEXT_ROCKTUNNEL1F_NO_TURNING_BACK, SCRIPT_ROCKTUNNEL1F_PLAYER_IS_MOVING, wRockTunnel1FCurScript

RockTunnel1FEntranceCoords:
	dbmapcoord 33, 15
	db -1

RockTunnel1FNoCoords:
	dbmapcoord 32, 15
	dbmapcoord 31, 15
	db -1

RockTunnel1F_ScriptPointers:
	def_script_pointers
	dw_const RockTunnel1FDefaultScript,             SCRIPT_ROCKTUNNEL1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROCKTUNNEL1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROCKTUNNEL1F_END_BATTLE
	dw_const RockTunnel1FPlayerIsMovingScript,      SCRIPT_ROCKTUNNEL1F_PLAYER_IS_MOVING

RockTunnel1F_TextPointers:
	def_text_pointers
	dw_const RockTunnel1FHiker1Text,       TEXT_ROCKTUNNEL1F_HIKER1
	dw_const RockTunnel1FHiker2Text,       TEXT_ROCKTUNNEL1F_HIKER2
	dw_const RockTunnel1FJrTrainerFText,   TEXT_ROCKTUNNEL1F_JR_TRAINER_F
	dw_const RockTunnel1FPokemaniacText,   TEXT_ROCKTUNNEL1F_POKEMANIAC
	dw_const RockTunnel1FCooltrainerMText, TEXT_ROCKTUNNEL1F_COOLTRAINER_M
    dw_const RandomPickUpItemText,          TEXT_ROCKTUNNEL1F_RANDOM
    dw_const RockTunnel1F_Rogue_Reward_Script_PokeballText_1, TEXT_ROCKTUNNEL1F_ROGUE_REWARD_POKEBALL_1
    dw_const RockTunnel1F_Rogue_Reward_Script_PokeballText_2, TEXT_ROCKTUNNEL1F_ROGUE_REWARD_POKEBALL_2
    dw_const RockTunnel1F_Rogue_Reward_Script_PokeballText_3, TEXT_ROCKTUNNEL1F_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_RockTunnel1F_Reward_Text, TEXT_ROCKTUNNEL1F_REWARD_VENDOR_1
    EXPORT TEXT_ROCKTUNNEL1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const RockTunnel1FSignText,          TEXT_ROCKTUNNEL1F_SIGN
	dw_const RockTunnel1FNoTurningBackText, TEXT_ROCKTUNNEL1F_NO_TURNING_BACK

RockTunnel1TrainerHeaders:
	def_trainers 1
RockTunnel1TrainerHeader0:
	trainer EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_0, 4, RockTunnel1FHiker1BattleText, RockTunnel1FHiker1EndBattleText, RockTunnel1FHiker1AfterBattleText
RockTunnel1TrainerHeader1:
	trainer EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_1, 4, RockTunnel1FHiker2BattleText, RockTunnel1FHiker2EndBattleText, RockTunnel1FHiker2AfterBattleText
RockTunnel1TrainerHeader2:
	trainer EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_2, 3, RockTunnel1FJrTrainerFBattleText, RockTunnel1FJrTrainerFEndBattleText, RockTunnel1FJrTrainerFAfterBattleText
RockTunnel1TrainerHeader3:
	trainer EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_3, 3, RockTunnel1FPokemaniacBattleText, RockTunnel1FPokemaniacEndBattleText, RockTunnel1FPokemaniacAfterBattleText
RockTunnel1TrainerHeader4:
	trainer EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_4, 4, RockTunnel1FCooltrainerMBattleText, RockTunnel1FCooltrainerMEndBattleText, RockTunnel1FCooltrainerMAfterBattleText
	db -1 ; end

RockTunnel1FHiker1Text:
	text_asm
	ld hl, RockTunnel1TrainerHeader0
	jr RockTunnel1FTalkToTrainer

RockTunnel1FHiker2Text:
	text_asm
	ld hl, RockTunnel1TrainerHeader1
	jr RockTunnel1FTalkToTrainer

RockTunnel1FJrTrainerFText:
	text_asm
	ld hl, RockTunnel1TrainerHeader2
	jr RockTunnel1FTalkToTrainer

RockTunnel1FPokemaniacText:
	text_asm
	ld hl, RockTunnel1TrainerHeader3
	jr RockTunnel1FTalkToTrainer

RockTunnel1FCooltrainerMText:
	text_asm
	ld hl, RockTunnel1TrainerHeader4
RockTunnel1FTalkToTrainer:
	call TalkToTrainer
	jp TextScriptEnd

RockTunnel1FHiker1BattleText:
	text_far _RockTunnel1FHiker1BattleText
	text_end

RockTunnel1FHiker1EndBattleText:
	text_far _RockTunnel1FHiker1EndBattleText
	text_end

RockTunnel1FHiker1AfterBattleText:
	text_far _RockTunnel1FHiker1AfterBattleText
	text_end

RockTunnel1FHiker2BattleText:
	text_far _RockTunnel1FHiker2BattleText
	text_end

RockTunnel1FHiker2EndBattleText:
	text_far _RockTunnel1FHiker2EndBattleText
	text_end

RockTunnel1FHiker2AfterBattleText:
	text_far _RockTunnel1FHiker2AfterBattleText
	text_end

RockTunnel1FJrTrainerFBattleText:
	text_far _RockTunnel1FHiker3BattleText
	text_end

RockTunnel1FJrTrainerFEndBattleText:
	text_far _RockTunnel1FHiker3EndBattleText
	text_end

RockTunnel1FJrTrainerFAfterBattleText:
	text_far _RockTunnel1FHiker3AfterBattleText
	text_end

RockTunnel1FPokemaniacBattleText:
	text_far _RockTunnel1FSuperNerdBattleText
	text_end

RockTunnel1FPokemaniacEndBattleText:
	text_far _RockTunnel1FSuperNerdEndBattleText
	text_end

RockTunnel1FPokemaniacAfterBattleText:
	text_far _RockTunnel1FSuperNerdAfterBattleText
	text_end

RockTunnel1FCooltrainerMBattleText:
	text_far _RockTunnel1FCooltrainerF1BattleText
	text_end

RockTunnel1FCooltrainerMEndBattleText:
	text_far _RockTunnel1FCooltrainerF1EndBattleText
	text_end

RockTunnel1FCooltrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, RockTunnel1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROCKTUNNEL1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

RockTunnel1FSignText:
	text_far _RockTunnel1FSignText
	text_end

Rogue_RockTunnel1F_Reward_Text:
script_rogue_reward

RockTunnel1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

RockTunnel1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

RockTunnel1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

RockTunnel1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

RockTunnel1FGreedyText:
	text_far _GreedyText
	text_end
