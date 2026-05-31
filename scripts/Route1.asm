Route1_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
	farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, Route1TrainerHeaders
	ld de, Route1_ScriptPointers
	ld a, [wRoute1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute1CurScript], a
	ret

Route1_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE1_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE1_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE1_END_BATTLE

Route1_TextPointers:
	def_text_pointers
	dw_const Route1Youngster4Text,    TEXT_ROUTE1_YOUNGSTER4
	dw_const Route1Youngster5Text,    TEXT_ROUTE1_YOUNGSTER5
	dw_const Route1Youngster6Text,    TEXT_ROUTE1_YOUNGSTER6
	dw_const Route1Youngster7Text,    TEXT_ROUTE1_YOUNGSTER7
	dw_const Route1JrTrainerMText,    TEXT_ROUTE1_JR_TRAINER_M
	dw_const Route1Youngster1Text, TEXT_ROUTE1_YOUNGSTER1
	dw_const Route1Youngster2Text, TEXT_ROUTE1_YOUNGSTER2
    dw_const RandomPickUpItemText, TEXT_ROUTE1_RANDOM
    dw_const Route1_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE1_ROGUE_REWARD_POKEBALL_1
    dw_const Route1_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE1_ROGUE_REWARD_POKEBALL_2
    dw_const Route1_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE1_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route1_Reward_Text, TEXT_ROUTE1_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE1_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route1SignText,       TEXT_ROUTE1_SIGN

Route1TrainerHeaders:
	def_trainers 1
Route1TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_1_TRAINER_0, 3, Route1Youngster4BattleText, Route1Youngster4EndBattleText, Route1Youngster4AfterBattleText
Route1TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_1_TRAINER_1, 2, Route1Youngster5BattleText, Route1Youngster5EndBattleText, Route1Youngster5AfterBattleText
Route1TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_1_TRAINER_2, 4, Route1Youngster6BattleText, Route1Youngster6EndBattleText, Route1Youngster6AfterBattleText
Route1TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_1_TRAINER_3, 4, Route1Youngster7BattleText, Route1Youngster7EndBattleText, Route1Youngster7AfterBattleText
Route1TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_1_TRAINER_4, 4, Route1JrTrainerMBattleText, Route1JrTrainerMEndBattleText, Route1JrTrainerMAfterBattleText
	db -1 ; end

Route1JrTrainerMText:
	text_asm
	ld hl, Route1TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route1JrTrainerMBattleText:
	text_far _Route1Youngster3BattleText
	text_end

Route1JrTrainerMEndBattleText:
	text_far _Route1Youngster3EndBattleText
	text_end

Route1JrTrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon
    ld hl, Route1GreedyText
    call PrintText
    jr .done
    .GetMon
    xor a
    ld a, TEXT_ROUTE1_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route1Youngster4Text:
	text_asm
	ld hl, Route1TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route1Youngster4BattleText:
	text_far _Route1Youngster3BattleText
	text_end

Route1Youngster4EndBattleText:
	text_far _Route1Youngster3EndBattleText
	text_end

Route1Youngster4AfterBattleText:
	text_far _Route1Youngster3AfterBattleText
	text_end

Route1Youngster5Text:
	text_asm
	ld hl, Route1TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route1Youngster5BattleText:
	text_far _Route1Youngster3BattleText
	text_end

Route1Youngster5EndBattleText:
	text_far _Route1Youngster3EndBattleText
	text_end

Route1Youngster5AfterBattleText:
	text_far _Route1Youngster3AfterBattleText
	text_end

Route1Youngster6Text:
	text_asm
	ld hl, Route1TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route1Youngster6BattleText:
	text_far _Route1Youngster3BattleText
	text_end

Route1Youngster6EndBattleText:
	text_far _Route1Youngster3EndBattleText
	text_end

Route1Youngster6AfterBattleText:
	text_far _Route1Youngster3AfterBattleText
	text_end

Route1Youngster7Text:
	text_asm
	ld hl, Route1TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route1Youngster7BattleText:
	text_far _Route1Youngster3BattleText
	text_end

Route1Youngster7EndBattleText:
	text_far _Route1Youngster3EndBattleText
	text_end

Route1Youngster7AfterBattleText:
	text_far _Route1Youngster3AfterBattleText
	text_end

Route1Youngster1Text:
	text_asm
	CheckAndSetEvent EVENT_GOT_POTION_SAMPLE
	jr nz, .got_item
	ld hl, .MartSampleText
	call PrintText
	lb bc, POTION, 1
	call GiveItem
	jr nc, .bag_full
	ld hl, .GotPotionText
	jr .done
.bag_full
	ld hl, .NoRoomText
	jr .done
.got_item
	ld hl, .AlsoGotPokeballsText
.done
	call PrintText
	jp TextScriptEnd

.MartSampleText:
	text_far _Route1Youngster1MartSampleText
	text_end

.GotPotionText:
	text_far _Route1Youngster1GotPotionText
	sound_get_item_1
	text_end

.AlsoGotPokeballsText:
	text_far _Route1Youngster1AlsoGotPokeballsText
	text_end

.NoRoomText:
	text_far _Route1Youngster1NoRoomText
	text_end

Route1Youngster2Text:
	text_far _Route1Youngster2Text
	text_end

Route1SignText:
	text_far _Route1SignText
	text_end

Rogue_Route1_Reward_Text:
script_rogue_reward

Route1_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route1_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route1_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route1GreedyText:
	text_far _GreedyText
	text_end
