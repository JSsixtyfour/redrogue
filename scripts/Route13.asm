Route13_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route13TrainerHeaders
	ld de, Route13_ScriptPointers
	ld a, [wRoute13CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute13CurScript], a
	ret

Route13_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE13_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE13_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE13_END_BATTLE

Route13_TextPointers:
	def_text_pointers
	dw_const Route13BirdKeeperText,    TEXT_ROUTE13_BIRD_KEEPER
	dw_const Route13BeautyText,        TEXT_ROUTE13_BEAUTY
	dw_const Route13JrTrainerFText,    TEXT_ROUTE13_JR_TRAINER_F
	dw_const Route13BikerText,         TEXT_ROUTE13_BIKER
	dw_const Route13CooltrainerMText,  TEXT_ROUTE13_COOLTRAINER_M
    dw_const RandomPickUpItemText,     TEXT_ROUTE13_RANDOM
    dw_const Route13_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE13_ROGUE_REWARD_POKEBALL_1
    dw_const Route13_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE13_ROGUE_REWARD_POKEBALL_2
    dw_const Route13_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE13_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route13_Reward_Text, TEXT_ROUTE13_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE13_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route13TrainerTips1Text,  TEXT_ROUTE13_TRAINER_TIPS1
	dw_const Route13TrainerTips2Text,  TEXT_ROUTE13_TRAINER_TIPS2
	dw_const Route13SignText,          TEXT_ROUTE13_SIGN

Route13TrainerHeaders:
	def_trainers 1
Route13TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_13_TRAINER_0, 2, Route13BirdKeeperBattleText, Route13BirdKeeperEndBattleText, Route13BirdKeeperAfterBattleText
Route13TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_13_TRAINER_1, 2, Route13BeautyBattleText, Route13BeautyEndBattleText, Route13BeautyAfterBattleText
Route13TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_13_TRAINER_2, 2, Route13JrTrainerFBattleText, Route13JrTrainerFEndBattleText, Route13JrTrainerFAfterBattleText
Route13TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_13_TRAINER_3, 2, Route13BikerBattleText, Route13BikerEndBattleText, Route13BikerAfterBattleText
Route13TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_13_TRAINER_4, 4, Route13CooltrainerMBattleText, Route13CooltrainerMEndBattleText, Route13CooltrainerMAfterBattleText
	db -1 ; end

Route13BirdKeeperText:
	text_asm
	ld hl, Route13TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route13BirdKeeperBattleText:
	text_far _Route13CooltrainerM1BattleText
	text_end

Route13BirdKeeperEndBattleText:
	text_far _Route13CooltrainerM1EndBattleText
	text_end

Route13BirdKeeperAfterBattleText:
	text_far _Route13CooltrainerM1AfterBattleText
	text_end

Route13BeautyText:
	text_asm
	ld hl, Route13TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route13BeautyBattleText:
	text_far _Route13Beauty1BattleText
	text_end

Route13BeautyEndBattleText:
	text_far _Route13Beauty1EndBattleText
	text_end

Route13BeautyAfterBattleText:
	text_far _Route13Beauty1AfterBattleText
	text_end

Route13JrTrainerFText:
	text_asm
	ld hl, Route13TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route13JrTrainerFBattleText:
	text_far _Route13CooltrainerF1BattleText
	text_end

Route13JrTrainerFEndBattleText:
	text_far _Route13CooltrainerF1EndBattleText
	text_end

Route13JrTrainerFAfterBattleText:
	text_far _Route13CooltrainerF1AfterBattleText
	text_end

Route13BikerText:
	text_asm
	ld hl, Route13TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route13BikerBattleText:
	text_far _Route13BikerBattleText
	text_end

Route13BikerEndBattleText:
	text_far _Route13BikerEndBattleText
	text_end

Route13BikerAfterBattleText:
	text_far _Route13BikerAfterBattleText
	text_end

Route13CooltrainerMText:
	text_asm
	ld hl, Route13TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route13CooltrainerMBattleText:
	text_far _Route13CooltrainerM3BattleText
	text_end

Route13CooltrainerMEndBattleText:
	text_far _Route13CooltrainerM3EndBattleText
	text_end

Route13CooltrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route13GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE13_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route13TrainerTips1Text:
	text_far _Route13TrainerTips1Text
	text_end

Route13TrainerTips2Text:
	text_far _Route13TrainerTips2Text
	text_end

Route13SignText:
	text_far _Route13SignText
	text_end

Rogue_Route13_Reward_Text:
script_rogue_reward

Route13_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route13_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route13_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route13GreedyText:
	text_far _GreedyText
	text_end
