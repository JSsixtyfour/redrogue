Route25_Script:

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
	call Route25ToggleBillsScript
	call EnableAutoTextBoxDrawing
	ld hl, Route25TrainerHeaders
	ld de, Route25_ScriptPointers
	ld a, [wRoute25CurScript]
	call ExecuteCurMapScriptInTable
	ld [wRoute25CurScript], a
	ret

Route25ToggleBillsScript:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	ret z
	CheckEventHL EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING
	ret nz
	CheckEventReuseHL EVENT_MET_BILL_2
	jr nz, .met_bill
	ResetEventReuseHL EVENT_BILL_SAID_USE_CELL_SEPARATOR
	ld a, TOGGLE_BILL_POKEMON
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject
.met_bill
	CheckEventAfterBranchReuseHL EVENT_GOT_SS_TICKET, EVENT_MET_BILL_2
	ret z
	SetEventReuseHL EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING
	ld a, TOGGLE_NUGGET_BRIDGE_GUY
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_BILL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_BILL_2
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject

Route25_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ROUTE25_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ROUTE25_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ROUTE25_END_BATTLE

Route25_TextPointers:
	def_text_pointers
	dw_const Route25YoungsterText,     TEXT_ROUTE25_YOUNGSTER
	dw_const Route25LassText,          TEXT_ROUTE25_LASS
	dw_const Route25JrTrainerMText,    TEXT_ROUTE25_JR_TRAINER_M
	dw_const Route25HikerText,         TEXT_ROUTE25_HIKER
	dw_const Route25CooltrainerMText,  TEXT_ROUTE25_COOLTRAINER_M
	dw_const PickUpItemText,           TEXT_ROUTE25_TM_SEISMIC_TOSS
    dw_const RandomPickUpItemText,     TEXT_ROUTE25_RANDOM
    dw_const Route25_Rogue_Reward_Script_PokeballText_1, TEXT_ROUTE25_ROGUE_REWARD_POKEBALL_1
    dw_const Route25_Rogue_Reward_Script_PokeballText_2, TEXT_ROUTE25_ROGUE_REWARD_POKEBALL_2
    dw_const Route25_Rogue_Reward_Script_PokeballText_3, TEXT_ROUTE25_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_Route25_Reward_Text, TEXT_ROUTE25_REWARD_VENDOR_1
    EXPORT TEXT_ROUTE25_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const Route25BillSignText,      TEXT_ROUTE25_BILL_SIGN

Route25TrainerHeaders:
	def_trainers 1
Route25TrainerHeader0:
	trainer EVENT_BEAT_ROUTE_25_TRAINER_0, 1, Route25YoungsterBattleText, Route25YoungsterEndBattleText, Route25YoungsterAfterBattleText
Route25TrainerHeader1:
	trainer EVENT_BEAT_ROUTE_25_TRAINER_1, 2, Route25LassBattleText, Route25LassEndBattleText, Route25LassAfterBattleText
Route25TrainerHeader2:
	trainer EVENT_BEAT_ROUTE_25_TRAINER_2, 2, Route25JrTrainerMBattleText, Route25JrTrainerMEndBattleText, Route25JrTrainerMAfterBattleText
Route25TrainerHeader3:
	trainer EVENT_BEAT_ROUTE_25_TRAINER_3, 2, Route25HikerBattleText, Route25HikerEndBattleText, Route25HikerAfterBattleText
Route25TrainerHeader4:
	trainer EVENT_BEAT_ROUTE_25_TRAINER_4, 4, Route25CooltrainerMBattleText, Route25CooltrainerMEndBattleText, Route25CooltrainerMAfterBattleText
	db -1 ; end

Route25YoungsterText:
	text_asm
	ld hl, Route25TrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

Route25LassText:
	text_asm
	ld hl, Route25TrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

Route25JrTrainerMText:
	text_asm
	ld hl, Route25TrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

Route25HikerText:
	text_asm
	ld hl, Route25TrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

Route25CooltrainerMText:
	text_asm
	ld hl, Route25TrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

Route25YoungsterBattleText:
	text_far _Route25Youngster1BattleText
	text_end

Route25YoungsterEndBattleText:
	text_far _Route25Youngster1EndBattleText
	text_end

Route25YoungsterAfterBattleText:
	text_far _Route25Youngster1AfterBattleText
	text_end

Route25LassBattleText:
	text_far _Route25CooltrainerF1BattleText
	text_end

Route25LassEndBattleText:
	text_far _Route25CooltrainerF1EndBattleText
	text_end

Route25LassAfterBattleText:
	text_far _Route25CooltrainerF1AfterBattleText
	text_end

Route25JrTrainerMBattleText:
	text_far _Route25CooltrainerMBattleText
	text_end

Route25JrTrainerMEndBattleText:
	text_far _Route25CooltrainerMEndBattleText
	text_end

Route25JrTrainerMAfterBattleText:
	text_far _Route25CooltrainerMAfterBattleText
	text_end

Route25HikerBattleText:
	text_far _Route25Hiker1BattleText
	text_end

Route25HikerEndBattleText:
	text_far _Route25Hiker1EndBattleText
	text_end

Route25HikerAfterBattleText:
	text_far _Route25Hiker1AfterBattleText
	text_end

Route25CooltrainerMBattleText:
	text_far _Route25Hiker3BattleText
	text_end

Route25CooltrainerMEndBattleText:
	text_far _Route25Hiker3EndBattleText
	text_end

Route25CooltrainerMAfterBattleText:
    text_asm
    farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, Route25GreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_ROUTE25_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Route25BillSignText:
	text_far _Route25BillSignText
	text_end

Rogue_Route25_Reward_Text:
script_rogue_reward

Route25_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

Route25_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

Route25_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

Route25GreedyText:
	text_far _GreedyText
	text_end
