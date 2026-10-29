; The shape of a Rogue round on wBattleCount. Every reader derives its numbers
; from these, so changing how many battles a stage or gym holds is an edit
; here plus the maps, not a hunt for literals. See BALANCE_PHASE5_PLAN.md §6
; (Red Rogue Files) for the reader list.
;
; wBattleCount is 1 after Oak's Lab. Within a round, step = count mod
; ROUND_BATTLES before the win: steps 1..ROUTE_BATTLES are the stage (the last
; one is the boss / final route trainer), the next GYM_TRAINER_BATTLES steps
; are the gym trainers, and step 0 is the leader. round = count / ROUND_BATTLES.
; A wild area stands in for a whole stage block (WILD_AREA_EXIT_BATTLES).
;
; Included before ram_constants.asm, which derives its own gates from these.

DEF ROUTE_BATTLES        EQU 4 ; stage trainers per round, boss included (was 5 until 2026-09-29)
DEF GYM_TRAINER_BATTLES  EQU 3 ; gym trainers before the leader (was 4 until 2026-09-29)
DEF ROUND_BATTLES        EQU ROUTE_BATTLES + GYM_TRAINER_BATTLES + 1 ; + the leader

DEF FINAL_ROUTE_STEP       EQU ROUTE_BATTLES                       ; level bonus, credits
DEF FIRST_GYM_STEP         EQU ROUTE_BATTLES + 1
DEF FINAL_GYM_TRAINER_STEP EQU ROUTE_BATTLES + GYM_TRAINER_BATTLES ; level bonus

DEF NUM_ROGUE_ROUNDS     EQU 8 ; gyms before Victory Road

; Back-to-back gyms (player feedback #2, 2026-10-09). The badge that brings the
; count to one of these skips the next round's route: the leader's exits lead
; to the Reward Room (the route's reward, and its ROUTE_BATTLES credit), then
; the lobby's single door to the gym the player did not take. Never three gyms
; in a row. Moving a pair is a one-line change here plus the curve.
DEF PAIR_BADGES_A        EQU 3 ; gym 3 -> gym 4: round 4's route skipped
DEF PAIR_BADGES_B        EQU 6 ; gym 6 -> gym 7: round 7's route skipped
	ASSERT 0 < PAIR_BADGES_A && PAIR_BADGES_A + 1 < PAIR_BADGES_B && PAIR_BADGES_B < NUM_ROGUE_ROUNDS - 1
DEF VICTORY_ROAD_BATTLES EQU 4 ; was 5 until 2026-09-29
DEF NUM_E4_BATTLES       EQU 4

; Round-indexed tables have NUM_ROGUE_ROUNDS + 1 rows (the last is Victory
; Road / Elite Four); readers clamp the count to this before dividing.
DEF LAST_ROUND_BATTLECOUNT EQU (NUM_ROGUE_ROUNDS + 1) * ROUND_BATTLES - 1
DEF LAST_ROUND EQU LAST_ROUND_BATTLECOUNT / ROUND_BATTLES ; the last row's index
; The Elite Four are fought at counts E4_FIRST_BATTLECOUNT .. +NUM_E4_BATTLES-1;
; CHAMPION_BATTLECOUNT is the count once all four are beaten.
DEF E4_FIRST_BATTLECOUNT EQU NUM_ROGUE_ROUNDS * ROUND_BATTLES + 1 + VICTORY_ROAD_BATTLES
DEF CHAMPION_BATTLECOUNT EQU E4_FIRST_BATTLECOUNT + NUM_E4_BATTLES

	ASSERT CHAMPION_BATTLECOUNT < 256, "wBattleCount is one byte"

; Endless mode: run progress advances this much per completed circuit
; (GetRunProgress, home/run_progress.asm). A multiple of ROUND_BATTLES, so the
; step within a round reads the same from progress as from the raw count.
DEF ENDLESS_CIRCUIT_SPAN EQU LAST_ROUND_BATTLECOUNT + 1
	ASSERT ENDLESS_CIRCUIT_SPAN % ROUND_BATTLES == 0
; The first round past the authored tables (rows 0-8, LAST_ROUND_BATTLECOUNT):
; Endless circuit 1's first route is progress 1 + ENDLESS_CIRCUIT_SPAN.
DEF ENDLESS_FIRST_ROUND EQU ENDLESS_CIRCUIT_SPAN / ROUND_BATTLES
	ASSERT ENDLESS_FIRST_ROUND == LAST_ROUND_BATTLECOUNT / ROUND_BATTLES + 1
; Rounds ENDLESS_FIRST_ROUND .. 255 / ROUND_BATTLES: one level-bonus row each.
DEF NUM_ENDLESS_LEVEL_ROWS EQU 255 / ROUND_BATTLES + 1 - ENDLESS_FIRST_ROUND
; Uber step (EndlessUberStep, ENDLESS_MODE_CHECKPOINT_E.md section 3): after a
; Master roll at depth >= 1, Uber's width out of 256 is BASE + STEP x (Endless
; rounds so far). STEP 4 is the user's pick (Q1): ~0.5% of bosses in Endless
; round 9, ~4% by 16, ~14% once progress saturates.
DEF ENDLESS_UBER_BASE EQU 1
DEF ENDLESS_UBER_STEP EQU 4
	ASSERT ENDLESS_UBER_BASE >= 1 && ENDLESS_UBER_BASE <= 255
	ASSERT LAST_ROUND_BATTLECOUNT < 256, "wBattleCount is one byte"
