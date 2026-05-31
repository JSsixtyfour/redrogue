Route9_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route9TrainerHeaders
	ld de, Route9_ScriptPointers
	ld a, [wRoute9CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute9CurScript], a
	ret

Route9_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE9_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE9_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE9_END_BATTLE

Route9_TextPointers:
	def_text_pointers
	dw_const Route9JrTrainerMText,    TEXT_ROUTE9_JR_TRAINER_M
	dw_const Route9JrTrainerFText,    TEXT_ROUTE9_JR_TRAINER_F
	dw_const Route9HikerText,         TEXT_ROUTE9_HIKER
	dw_const Route9BugCatcherText,    TEXT_ROUTE9_BUG_CATCHER
	dw_const Route9CooltrainerMText,  TEXT_ROUTE9_COOLTRAINER_M
	dw_const PickUpItemText,          TEXT_ROUTE9_TM_TELEPORT
    dw_const RandomPickUpItemText,    TEXT_ROUTE9_RANDOM
    dw_const Route9_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE9_ROGUE_REWARD_POKEBALL_1
    dw_const Route9_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE9_ROGUE_REWARD_POKEBALL_2
    dw_const Route9_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE9_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route9_Reward_Text, TEXT_ROUTE9_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE9_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route9SignText,          TEXT_ROUTE9_SIGN

Route9TrainerHeaders:
	def_trainers 1
Route9TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_9_TRAINER_0, 1, Route9JrTrainerMBattleText, Route9JrTrainerMEndBattleText, Route9JrTrainerMAfterBattleText
Route9TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_9_TRAINER_1, 2, Route9JrTrainerFBattleText, Route9JrTrainerFEndBattleText, Route9JrTrainerFAfterBattleText
Route9TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_9_TRAINER_2, 1, Route9HikerBattleText, Route9HikerEndBattleText, Route9HikerAfterBattleText
Route9TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_9_TRAINER_3, 4, Route9BugCatcherBattleText, Route9BugCatcherEndBattleText, Route9BugCatcherAfterBattleText
Route9TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_9_TRAINER_4, 3, Route9CooltrainerMBattleText, Route9CooltrainerMEndBattleText, Route9CooltrainerMAfterBattleText
	db -1 ; end

Route9JrTrainerMText:
	text_asm
	ld hl, Route9TrainerHeader0
	jr Route9TalkToTrainer

Route9JrTrainerFText:
	text_asm
	ld hl, Route9TrainerHeader1
	jr Route9TalkToTrainer

Route9HikerText:
	text_asm
	ld hl, Route9TrainerHeader2
	jr Route9TalkToTrainer

Route9BugCatcherText:
	text_asm
	ld hl, Route9TrainerHeader3
	jr Route9TalkToTrainer

Route9CooltrainerMText:
	text_asm
	ld hl, Route9TrainerHeader4
Route9TalkToTrainer:
	call TalkToTrainer
	jp TextScriptEnd

Route9JrTrainerMBattleText:
	text_far _Route9CooltrainerM1BattleText
	text_end

Route9JrTrainerMEndBattleText:
	text_far _Route9CooltrainerM1EndBattleText
	text_end

Route9JrTrainerMAfterBattleText:
	text_far _Route9CooltrainerM1AfterBattleText
	text_end

Route9JrTrainerFBattleText:
	text_far _Route9CooltrainerF1BattleText
	text_end

Route9JrTrainerFEndBattleText:
	text_far _Route9CooltrainerF1EndBattleText
	text_end

Route9JrTrainerFAfterBattleText:
	text_far _Route9CooltrainerF1AfterBattleText
	text_end

Route9HikerBattleText:
	text_far _Route9Hiker1BattleText
	text_end

Route9HikerEndBattleText:
	text_far _Route9Hiker1EndBattleText
	text_end

Route9HikerAfterBattleText:
	text_far _Route9Hiker1AfterBattleText
	text_end

Route9BugCatcherBattleText:
	text_far _Route9Youngster1BattleText
	text_end

Route9BugCatcherEndBattleText:
	text_far _Route9Youngster1EndBattleText
	text_end

Route9BugCatcherAfterBattleText:
	text_far _Route9Youngster1AfterBattleText
	text_end

Route9CooltrainerMBattleText:
	text_far _Route9Youngster2BattleText
	text_end

Route9CooltrainerMEndBattleText:
	text_far _Route9Youngster2EndBattleText
	text_end

Route9CooltrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route9GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE9_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route9SignText:
	text_far _Route9SignText
	text_end

Rogue_Route9_Reward_Text:
script_rogue_reward

Route9_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route9_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route9_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route9GreedyText:
	text_far _GreedyText
	text_end
