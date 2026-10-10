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
;   wild_levels.asm       wild-area encounter levels, one byte per round.
;   wild_boss_levels.asm  wild-area boss levels, one byte per round.

; --- Gym leaders ------------------------------------------------------------
; Per round (= badge about to be earned): team size, level of slot 0, and the
; level added per slot. The ace (last slot) is BASE + (MONS - 1) * STEP.
; Read by gym_team_spec in data/trainers/party_specs.asm.
DEF GYM_R1_MONS EQU 2
DEF GYM_R1_BASE EQU 9
DEF GYM_R1_STEP EQU 2
DEF GYM_R2_MONS EQU 2
DEF GYM_R2_BASE EQU 15
DEF GYM_R2_STEP EQU 3
DEF GYM_R3_MONS EQU 3
DEF GYM_R3_BASE EQU 19
DEF GYM_R3_STEP EQU 3
DEF GYM_R4_MONS EQU 3
DEF GYM_R4_BASE EQU 27
DEF GYM_R4_STEP EQU 2
DEF GYM_R5_MONS EQU 4
DEF GYM_R5_BASE EQU 31
DEF GYM_R5_STEP EQU 2
DEF GYM_R6_MONS EQU 4
DEF GYM_R6_BASE EQU 38
DEF GYM_R6_STEP EQU 2
DEF GYM_R7_MONS EQU 5
DEF GYM_R7_BASE EQU 43
DEF GYM_R7_STEP EQU 2
DEF GYM_R8_MONS EQU 6
DEF GYM_R8_BASE EQU 47
DEF GYM_R8_STEP EQU 2

; --- Curated moveset level window --------------------------------------------
; A curated set (MSRC_SET) is written for a level range. When no set of the
; mix's tier covers a mon's exact level, PartyGenApplySetMoveset widens the
; window once, DOWNWARD only: a set whose range ends up to this many levels
; under the mon also qualifies. Only after that does the slot take its mix
; row's fallback source. Never upward - a set written for higher levels would
; hand the mon its moves early.
DEF SET_LEVEL_SLACK_BELOW EQU 10

; --- Elite Four -------------------------------------------------------------
; Tier t (1-4, from wBattleCount 86-89): slot 0 is E4_BASE_LEVEL + t, and each
; slot adds E4_LEVEL_STEP. Read through the E4_T curve in party_specs.asm.
DEF E4_BASE_LEVEL EQU 49
DEF E4_LEVEL_STEP EQU 2

; --- Champions (RIVAL3, Champion Lance, Prof. Oak) ----------------------------
; Six mons: slot 0 is CHAMPION_BASE_LEVEL, each slot adds CHAMPION_LEVEL_STEP,
; the ace last. Read by champion_spec in party_specs.asm.
DEF CHAMPION_BASE_LEVEL EQU 59
DEF CHAMPION_LEVEL_STEP EQU 1
; The same curve under the names banded_round_spec builds (<curve><round>_*):
; every Champion is one round of six (party roster Phase 5, 2026-10-07).
DEF CHAMPION_R1_MONS EQU 6
DEF CHAMPION_R1_BASE EQU CHAMPION_BASE_LEVEL
DEF CHAMPION_R1_STEP EQU CHAMPION_LEVEL_STEP

; --- Mini-bosses (Rival, Giovanni, Karate Master) -----------------------------
; One spec per round (1-9). The round is read from wBattleCount when the battle
; starts (PartyGenSpecIndex, engine/battle/rogue_build_party.asm), never from
; the trainer's set number, so the Victory Road rival is round 9 wherever he
; is met. Slot 0 is BASE, each slot adds STEP; the ace (last slot) is
; BASE + (MONS - 1) * STEP.
;
; MONS is that round's LARGEST route team, as for the wild-area trainers: the
; mini-boss stands in for the route's final trainer (party roster Phase 4,
; 2026-10-07; was a flat 5 with randomly rolled levels).
; test_party_roster_curves.py fails if the two drift apart.
;
; Levels come from the old trainer_difficulty_settings_miniboss rows (Curve F,
; 2026-10-02, BALANCE_LEVEL_SPIKE.md): BASE is the old min_level, and STEP is
; the largest whole step that keeps the ace within the old min + range - 1, so
; the mini-boss still lands between the route's final trainer and the round's
; leader. Round 1 is never reached (mini-bosses start at
; MINIBOSS_FIRST_BATTLECOUNT) but has a record, so every index is covered.
; Read by miniboss_records in data/trainers/party_specs.asm.
DEF MINIBOSS_R1_MONS EQU 2
DEF MINIBOSS_R1_BASE EQU 5
DEF MINIBOSS_R1_STEP EQU 2
DEF MINIBOSS_R2_MONS EQU 3
DEF MINIBOSS_R2_BASE EQU 11
DEF MINIBOSS_R2_STEP EQU 1
DEF MINIBOSS_R3_MONS EQU 4
DEF MINIBOSS_R3_BASE EQU 17
DEF MINIBOSS_R3_STEP EQU 1
DEF MINIBOSS_R4_MONS EQU 4
DEF MINIBOSS_R4_BASE EQU 23
DEF MINIBOSS_R4_STEP EQU 1
DEF MINIBOSS_R5_MONS EQU 5
DEF MINIBOSS_R5_BASE EQU 28
DEF MINIBOSS_R5_STEP EQU 1
DEF MINIBOSS_R6_MONS EQU 5
DEF MINIBOSS_R6_BASE EQU 34
DEF MINIBOSS_R6_STEP EQU 1
DEF MINIBOSS_R7_MONS EQU 6
DEF MINIBOSS_R7_BASE EQU 41
DEF MINIBOSS_R7_STEP EQU 1
DEF MINIBOSS_R8_MONS EQU 6
DEF MINIBOSS_R8_BASE EQU 47
DEF MINIBOSS_R8_STEP EQU 1
DEF MINIBOSS_R9_MONS EQU 6
DEF MINIBOSS_R9_BASE EQU 53
DEF MINIBOSS_R9_STEP EQU 1

; --- Wild-area stage-event trainers (optional battle) ------------------------
; Jessie & James, Psychic, Burglar, Joy, Jenny... One spec per round (1-9).
; Slot 0 is BASE, each slot adds STEP. Beating one pays money and trainer EXP but
; never advances wBattleCount (core.asm TrainerBattleVictory). How often one
; appears is STAGE_EVENT_CHANCE (out of 256).
;
; MONS is that round's LARGEST route team (party roster Phase 3, 2026-10-07):
; the class-count sum of the round's trainer_difficulty_settings block in
; data/balance/trainer_levels.asm, 2/3/4/4/5/5/6/6/6. It was 2/2/3/3/4/4/5/5/6.
; test_party_roster_curves.py fails if the two drift apart.
; Read by banded_round_spec / stage_event_banded_records in data/trainers/party_specs.asm.
DEF STAGE_EVENT_R1_MONS EQU 2
DEF STAGE_EVENT_R1_BASE EQU 5
DEF STAGE_EVENT_R1_STEP EQU 1
DEF STAGE_EVENT_R2_MONS EQU 3
DEF STAGE_EVENT_R2_BASE EQU 12
DEF STAGE_EVENT_R2_STEP EQU 1
DEF STAGE_EVENT_R3_MONS EQU 4
DEF STAGE_EVENT_R3_BASE EQU 16
DEF STAGE_EVENT_R3_STEP EQU 1
DEF STAGE_EVENT_R4_MONS EQU 4
DEF STAGE_EVENT_R4_BASE EQU 23
DEF STAGE_EVENT_R4_STEP EQU 1
DEF STAGE_EVENT_R5_MONS EQU 5
DEF STAGE_EVENT_R5_BASE EQU 28
DEF STAGE_EVENT_R5_STEP EQU 1
DEF STAGE_EVENT_R6_MONS EQU 5
DEF STAGE_EVENT_R6_BASE EQU 34
DEF STAGE_EVENT_R6_STEP EQU 1
DEF STAGE_EVENT_R7_MONS EQU 6
DEF STAGE_EVENT_R7_BASE EQU 39
DEF STAGE_EVENT_R7_STEP EQU 1
DEF STAGE_EVENT_R8_MONS EQU 6
DEF STAGE_EVENT_R8_BASE EQU 47
DEF STAGE_EVENT_R8_STEP EQU 1
DEF STAGE_EVENT_R9_MONS EQU 6
DEF STAGE_EVENT_R9_BASE EQU 48
DEF STAGE_EVENT_R9_STEP EQU 1

; --- Prize money -------------------------------------------------------------
; Money won = base x level of the enemy's last mon (BCD), plus Amulet Coin
; +10/15/20%. Read by data/trainers/pic_pointers_money.asm.
DEF MONEY_BASE_TRAINER EQU 80 ; was 75 until 2026-10-06 (+7%; route and gym trainers)
DEF MONEY_BASE_LEADER EQU 215 ; was 200 until 2026-10-06 (+7.5%)
DEF MONEY_BASE_LEADER_GIOVANNI EQU 160 ; GIOVANNI's own gym-leader row differs from the other leaders (was 150 until 2026-10-06)
DEF MONEY_BASE_E4 EQU 200
DEF MONEY_BASE_RIVAL1 EQU 100
DEF MONEY_BASE_RIVAL2 EQU 150
DEF MONEY_BASE_CHAMPION EQU 300 ; RIVAL3, FINAL_AI
DEF MONEY_BASE_OAK EQU 300
DEF MONEY_BASE_MINIBOSS_RIVAL EQU 100
DEF MONEY_BASE_MINIBOSS_GIOVANNI EQU 200
DEF MONEY_BASE_MINIBOSS_KARATE EQU 150

; --- Economy -------------------------------------------------------------
; BCD, $3000 = Y3000. Read by engine/movie/oak_speech/init_player_data.asm.
DEF START_MONEY EQU $3000

; --- Wild areas ---------------------------------------------------------
; Encounter chance per step = rate/256. Read by data/wild/maps/Procedural*.asm.
DEF WILD_AREA_ENCOUNTER_RATE EQU 10
; Per-round battle budget, saturating at 255: BASE + wBattleCount/DIVISOR.
; The divisor is half a round, so the budget grows by 2 per round whatever
; ROUND_BATTLES is (constants/round_constants.asm).
; Read by the cave/forest/cemetery/facility generators.
DEF WILD_BUDGET_BASE EQU 10
DEF WILD_BUDGET_DIVISOR EQU ROUND_BATTLES / 2
; wBattleCount credit on exiting a wild area: it stands in for the stage
; block (ROUTE_BATTLES) a wild area replaces, so the next battle is the
; round's first gym trainer. Read by procedural_stage_hooks.asm.
DEF WILD_AREA_EXIT_BATTLES EQU ROUTE_BATTLES
; Rarity class of wild-area mons (PCRollMonClass, via RollSpreadClass): base
; widths out of 256 are pokeball 205 / great 38 / ultra 10 / master 3. The
; bonus is round * STEP (+ BOSS_BUMP for the boss); it shrinks the pokeball band
; and the freed width is split evenly over great, ultra and master. A boss is
; 103/256 = 40% pokeball in round 1 and 39/256 = 15% from round 9 on.
DEF WILD_CLASS_ROUND_STEP EQU 8
DEF WILD_BOSS_RARITY_BUMP EQU 102

; Wild encounter base level per round (0-8); the caller adds 0-2. Emitted in
; two banks, so it is a macro rather than one table: PCWildLevelTable
; (data/balance/wild_levels.asm, every procedural stage's grass encounters) and
; PFacFakeWildLevelTable (the facility's four fake-ball Voltorb/Electrode
; encounters, procedural_facility_gen.asm). They used to be two typed-out
; copies that could drift apart.
MACRO wild_area_levels
	db 7, 10, 14, 22, 27, 34, 40, 47, 55 ; each -1 on 2026-10-06 (wild mons sat ~0.5 over the team average)
ENDM

; Chance out of 256 that an offered wild area carries a stage-event trainer.
; 256 = every offered wild area carries one. StageEventRoll (wild_area_selection.asm)
; skips its `cp` entirely at that value rather than comparing against an
; 8-bit-unrepresentable 256, so the knob still works for any value below it.
DEF STAGE_EVENT_CHANCE EQU 256

; --- Roster party sizes ---------------------------------------------------
; A normal (not final) route or gym trainer whose table size is at least
; ROSTER_VARY_MIN_SIZE and below ROSTER_FULL_SIZE fields one mon fewer, half the
; time (GetRandRosterLoop.maybeShrink, func_enc_gen.asm). The final trainer of
; each block always fields the full size; gym leaders are specs and never vary.
; MIN_SIZE 3 means a 2-mon team never drops to 1.
DEF ROSTER_VARY_MIN_SIZE EQU 3
DEF ROSTER_FULL_SIZE EQU 6

; --- Reward levels --------------------------------------------------------
; GetRewardMonLevel (rogue_reward_menu.asm) = min + range/2 of the current
; round's gym-trainer block (data/balance/trainer_levels.asm), clamped to
; [FLOOR, CAP]. The range/2 itself is code (srl a), not a knob. Drives stage
; balls, the salesman, daycares and the bridge gift. The floor only binds in
; round 1 (Curve F's gym block gives 6 there; round 2 already gives 9+): 8 puts
; the first route's gift a couple of levels over the L5 starter (playtest
; 2026-10-03: L6 was too low). The starter itself stays a flat 5 (.flatFive).
DEF REWARD_LEVEL_FLOOR EQU 8
DEF REWARD_LEVEL_CAP EQU 50

; --- HM/TM prices -------------------------------------------------------------
; One price per move grade (MoveRankByID, data/moves/move_ranks.asm). Each HM
; and TM carries its tier in data/items/tm_prices.asm; GetMachinePrice
; (engine/items/tm_prices.asm) reads the price here. BCD THOUSANDS, one byte:
; $20 = Y20,000, so the ceiling is Y99,000. (The old table stored the price
; itself as a BCD thousands digit, which capped it at Y9,000.)
; 2026-10-06: cut at least 15% from 2/4/6/10/15/20 thousand, rounded down to
; the next whole thousand the byte can hold (F 2 -> 1 is the only step that
; size, since 2 -> 1.7 isn't representable).
; 2026-10-09 (player feedback #10): D-S another -15%, rounded down the same way
; (3/5/8/12/17 -> 2/4/6/10/14 thousand); F stays Y1,000.
	const_def
	const TM_PRICE_TIER_F ; 0
	const TM_PRICE_TIER_D ; 1
	const TM_PRICE_TIER_C ; 2
	const TM_PRICE_TIER_B ; 3
	const TM_PRICE_TIER_A ; 4
	const TM_PRICE_TIER_S ; 5
DEF NUM_TM_PRICE_TIERS EQU const_value
DEF TM_PRICE_F_BCD EQU $01
DEF TM_PRICE_D_BCD EQU $02
DEF TM_PRICE_C_BCD EQU $04
DEF TM_PRICE_B_BCD EQU $06
DEF TM_PRICE_A_BCD EQU $10
DEF TM_PRICE_S_BCD EQU $14

; --- Lobby clerk (stat/TM) odds ----------------------------------------------
; Random_StatTM_Mart_Selection (engine/items/random_item_selection_mart.asm).
; Each slot is a stat item when a roll is below CLERK_STAT_SHARE, else a TM;
; then a second roll picks the class: a roll <= *_POKEBALL_ODDS is pokeball
; class, <= *_GREATBALL_ODDS great, <= *_ULTRABALL_ODDS ultra, else master.
; Cumulative thresholds out of 256 (a threshold t covers rolls 0..t).
DEF CLERK_STAT_SHARE EQU 128 ; 50% stat items, 50% TMs
; TMs: 30% / 35% / 25% / 10% (master = the S-grade TMs and Surf)
DEF CLERK_TM_POKEBALL_ODDS  EQU 76
DEF CLERK_TM_GREATBALL_ODDS EQU 76 + 90
DEF CLERK_TM_ULTRABALL_ODDS EQU 76 + 90 + 64
; Stat: vitamins 35% / HP Up, PP Up 25% / evolution stones 37% / Rare Candy 3%
DEF CLERK_STAT_POKEBALL_ODDS  EQU 88
DEF CLERK_STAT_GREATBALL_ODDS EQU 88 + 64
DEF CLERK_STAT_ULTRABALL_ODDS EQU 88 + 64 + 95

; --- Lobby sink prices ------------------------------------------------------
; BCD thousands bytes like the TM prices: $20 = Y20,000. Read by
; scripts/IndigoPlateauLobby.asm.
DEF SALESMAN_PRICE_POKEBALL_BCD EQU $05
DEF SALESMAN_PRICE_GREATBALL_BCD EQU $12
DEF SALESMAN_PRICE_ULTRABALL_BCD EQU $20
; Lobby Move Tutor fees, ordinary integers encoded by TutorMovePrices (bcd3).
; Independent of reusable TM prices; OFFLIST tutor moves use the F-tier fee.
; 2026-10-09 (player feedback #11): -10% from 1000/2000/3000/5000/10000/15000.
DEF MOVE_TUTOR_PRICE_F EQU 900
DEF MOVE_TUTOR_PRICE_D EQU 1800
DEF MOVE_TUTOR_PRICE_C EQU 2700
DEF MOVE_TUTOR_PRICE_B EQU 4500
DEF MOVE_TUTOR_PRICE_A EQU 9000
DEF MOVE_TUTOR_PRICE_S EQU 13500
; The two high bytes of a 3-byte BCD money value, from a BCD-thousands byte:
; $TU -> $0T, $U0 (Y TU,000), as (high << 8) | middle for `ld de`/`ld bc`.
DEF SALESMAN_PRICE_POKEBALL_WORD  EQU ((SALESMAN_PRICE_POKEBALL_BCD >> 4) << 8) | ((SALESMAN_PRICE_POKEBALL_BCD & $0F) << 4)
DEF SALESMAN_PRICE_GREATBALL_WORD EQU ((SALESMAN_PRICE_GREATBALL_BCD >> 4) << 8) | ((SALESMAN_PRICE_GREATBALL_BCD & $0F) << 4)
DEF SALESMAN_PRICE_ULTRABALL_WORD EQU ((SALESMAN_PRICE_ULTRABALL_BCD >> 4) << 8) | ((SALESMAN_PRICE_ULTRABALL_BCD & $0F) << 4)
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
DEF LOBBY_PSYCHIC_CHANCE EQU 154  ; ~60% (154/256 = 60.2%)
DEF LOBBY_SALESMAN_CHANCE EQU 85  ; ~1/3
DEF LOBBY_TRADER_CHANCE EQU 85    ; ~1/3
DEF LOBBY_TUTOR_CHANCE EQU 85     ; ~1/3
