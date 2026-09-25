; Balance knobs. The single place to tune run difficulty, EXP, wild areas and
; money. See BALANCE_SYSTEM.md (Red Rogue Files) for what each one drives and
; for tools/balance/model.py, which reads this file to predict the effect of a
; change before any ROM is built.
;
; Everything here is a DEF, so this file costs zero ROM bytes by itself.

; --- Experience -------------------------------------------------------------

; 1 = wild battles pay the same EXP as trainer battles (the 1.5x trainer boost
; applies to every battle). 0 = vanilla: wild battles pay 2/3 of a trainer
; battle. Wild-area bosses are OW_POKEMON, so they are wild battles here too.
DEF WILD_EXP_MATCHES_TRAINER EQU 1

; --- Trainer level tables (data, not DEFs) -----------------------------------
; These live in data/balance/ because they are byte tables read at runtime:
;   trainer_levels.asm    route trainers (wBattleCount mod 10 = 1-5) and gym
;                         trainers (6-9), one 11-byte block per round. Also
;                         the source of every reward level (GetRewardMonLevel).
;   miniboss_levels.asm   Rival / Giovanni mini-boss tier, 4 bytes per round.
;   wild_levels.asm       wild-area encounter levels, one byte per round.
;   wild_boss_levels.asm  wild-area boss levels, one byte per round.

; --- Gym leaders ------------------------------------------------------------
; Per round (= badge about to be earned): team size, level of slot 0, and the
; level added per slot. The ace (last slot) is BASE + (MONS - 1) * STEP.
; Read by gym_team_spec in data/trainers/party_specs.asm.
DEF GYM_R1_MONS EQU 2
DEF GYM_R1_BASE EQU 12
DEF GYM_R1_STEP EQU 2
DEF GYM_R2_MONS EQU 2
DEF GYM_R2_BASE EQU 18
DEF GYM_R2_STEP EQU 3
DEF GYM_R3_MONS EQU 3
DEF GYM_R3_BASE EQU 18
DEF GYM_R3_STEP EQU 3
DEF GYM_R4_MONS EQU 3
DEF GYM_R4_BASE EQU 25
DEF GYM_R4_STEP EQU 2
DEF GYM_R5_MONS EQU 4
DEF GYM_R5_BASE EQU 37
DEF GYM_R5_STEP EQU 2
DEF GYM_R6_MONS EQU 4
DEF GYM_R6_BASE EQU 37
DEF GYM_R6_STEP EQU 2
DEF GYM_R7_MONS EQU 5
DEF GYM_R7_BASE EQU 39
DEF GYM_R7_STEP EQU 2
DEF GYM_R8_MONS EQU 6
DEF GYM_R8_BASE EQU 40
DEF GYM_R8_STEP EQU 2

; --- Elite Four -------------------------------------------------------------
; Tier t (1-4, from wBattleCount 86-89): slot 0 is E4_BASE_LEVEL + t, and each
; slot adds E4_LEVEL_STEP. Read by e4_team_spec in party_specs.asm.
DEF E4_BASE_LEVEL EQU 51
DEF E4_LEVEL_STEP EQU 2

; --- Wild-area stage-event trainers (optional battle) ------------------------
; Jessie & James, Psychic, Burglar, Joy, Jenny... One spec per round (1-9).
; Slot 0 is BASE, each slot adds STAGE_EVENT_LEVEL_STEP. Beating one pays money
; and trainer EXP but never advances wBattleCount (core.asm TrainerBattleVictory).
; How often one appears is STAGE_EVENT_CHANCE (out of 256).
; Read by stage_event_team_spec in data/trainers/party_specs.asm.
DEF STAGE_EVENT_R1_MONS EQU 2
DEF STAGE_EVENT_R1_BASE EQU 5
DEF STAGE_EVENT_R2_MONS EQU 2
DEF STAGE_EVENT_R2_BASE EQU 15
DEF STAGE_EVENT_R3_MONS EQU 3
DEF STAGE_EVENT_R3_BASE EQU 20
DEF STAGE_EVENT_R4_MONS EQU 3
DEF STAGE_EVENT_R4_BASE EQU 25
DEF STAGE_EVENT_R5_MONS EQU 4
DEF STAGE_EVENT_R5_BASE EQU 33
DEF STAGE_EVENT_R6_MONS EQU 4
DEF STAGE_EVENT_R6_BASE EQU 37
DEF STAGE_EVENT_R7_MONS EQU 5
DEF STAGE_EVENT_R7_BASE EQU 41
DEF STAGE_EVENT_R8_MONS EQU 5
DEF STAGE_EVENT_R8_BASE EQU 45
DEF STAGE_EVENT_R9_MONS EQU 6
DEF STAGE_EVENT_R9_BASE EQU 52
DEF STAGE_EVENT_LEVEL_STEP EQU 1

; --- Prize money -------------------------------------------------------------
; Money won = base x level of the enemy's last mon (BCD), plus Amulet Coin
; +10/15/20%. Read by data/trainers/pic_pointers_money.asm.
DEF MONEY_BASE_TRAINER EQU 75
DEF MONEY_BASE_LEADER EQU 200
DEF MONEY_BASE_LEADER_GIOVANNI EQU 150 ; GIOVANNI's own gym-leader row differs from the other leaders
DEF MONEY_BASE_E4 EQU 200
DEF MONEY_BASE_RIVAL1 EQU 100
DEF MONEY_BASE_RIVAL2 EQU 150
DEF MONEY_BASE_CHAMPION EQU 300 ; RIVAL3, FINAL_AI
DEF MONEY_BASE_OAK EQU 300
DEF MONEY_BASE_MINIBOSS_RIVAL EQU 100
DEF MONEY_BASE_MINIBOSS_GIOVANNI EQU 200

; --- Economy -------------------------------------------------------------
; BCD, $3000 = Y3000. Read by engine/movie/oak_speech/init_player_data.asm.
DEF START_MONEY EQU $3000

; --- Wild areas ---------------------------------------------------------
; Encounter chance per step = rate/256. Read by data/wild/maps/Procedural*.asm.
DEF WILD_AREA_ENCOUNTER_RATE EQU 10
; Per-round battle budget, saturating at 255: BASE + wBattleCount/DIVISOR.
; Read by the cave/forest/cemetery/facility generators.
DEF WILD_BUDGET_BASE EQU 10
DEF WILD_BUDGET_DIVISOR EQU 5
; wBattleCount credit on exiting a wild area. Must stay 5 while the round
; math is "10 battles per round": it stands in for the 5 route trainers a
; wild area replaces. Read by procedural_stage_hooks.asm.
DEF WILD_AREA_EXIT_BATTLES EQU 5

; Wild encounter base level per round (0-8); the caller adds 0-2. Emitted in
; two banks, so it is a macro rather than one table: PCWildLevelTable
; (data/balance/wild_levels.asm, every procedural stage's grass encounters) and
; PFacFakeWildLevelTable (the facility's four fake-ball Voltorb/Electrode
; encounters, procedural_facility_gen.asm). They used to be two typed-out
; copies that could drift apart.
MACRO wild_area_levels
	db 5, 9, 13, 17, 21, 25, 29, 33, 37
ENDM

; Chance out of 256 that an offered wild area carries a stage-event trainer.
; 256 = every offered wild area carries one. StageEventRoll (wild_area_selection.asm)
; skips its `cp` entirely at that value rather than comparing against an
; 8-bit-unrepresentable 256, so the knob still works for any value below it.
DEF STAGE_EVENT_CHANCE EQU 256

; --- Reward levels --------------------------------------------------------
; GetRewardMonLevel (rogue_reward_menu.asm) = min + range/2 of the current
; round's gym-trainer block (data/balance/trainer_levels.asm), clamped to
; [FLOOR, CAP]. The range/2 itself is code (srl a), not a knob. Drives stage
; balls, the salesman, daycares and the bridge gift.
DEF REWARD_LEVEL_FLOOR EQU 5
DEF REWARD_LEVEL_CAP EQU 50

; --- Lobby sink prices ------------------------------------------------------
; All BCD thousands bytes: $20 = Y2000. Read by scripts/IndigoPlateauLobby.asm.
DEF SALESMAN_PRICE_POKEBALL_BCD EQU $20
DEF SALESMAN_PRICE_GREATBALL_BCD EQU $60
DEF SALESMAN_PRICE_ULTRABALL_BCD EQU $90
; Used twice by the move relearner (PCMoveTutorText): once for the
; HasEnoughMoney check, once for the deduction. The player pays it once.
DEF MOVE_RELEARNER_PRICE_BCD EQU $50
; BCD $0500 = Y500 per round. Read by engine/events/lobby_daycare.asm.
DEF DAYCARE_PRICE_PER_ROUND_BCD EQU $5
; The Psychic's price is computed (Y1000 x (badges + 1)), not a literal here.

; --- Lobby NPC appearance odds ----------------------------------------------
; Chance out of 256 that each optional lobby resident is present on a lobby
; visit, rolled on every lobby entry. Debug 1 and Debug 2 (BIT_DEBUG_MODE)
; skip the roll and always show them. The Witch is still hidden for the
; Elite Four stretch, and the Psychic only ever appears when a gym is next.
; Rolled in custom_functions/witch_setup.asm (Witch) and
; engine/events/lobby_psychic.asm (the other four).
DEF LOBBY_WITCH_CHANCE EQU 85     ; ~1/3
DEF LOBBY_PSYCHIC_CHANCE EQU 128  ; 1/2
DEF LOBBY_SALESMAN_CHANCE EQU 85  ; ~1/3
DEF LOBBY_TRADER_CHANCE EQU 85    ; ~1/3
DEF LOBBY_TUTOR_CHANCE EQU 85     ; ~1/3
