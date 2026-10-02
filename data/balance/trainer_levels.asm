; Route and gym trainer level tiers. INCLUDEd in place by
; custom_functions/func_enc_gen.asm: it must stay in that section. GetRandRoster
; reads it with a plain [hl], and GetRewardMonLevel reads it cross-bank through
; BANK(trainer_difficulty_settings). Part of the balance system, see
; constants/balance_constants.asm.

; one 11-byte block per round (round = wBattleCount / ROUND_BATTLES, capped at 8).
; Curve F (2026-10-02, BALANCE_LEVEL_SPIKE.md). Leader aces 11 18 25 31 37 44 51 57.
; Solved with tools/balance/model.py against the ROLLED starter (a random
; species, ~2/3 medium-fast), not a medium-slow one, with EXP Share at 62.5%.
; Targets, enemy top level - starter level: route trainers -1.5, the final
; route trainer +1, gym trainers -1.5, the final gym trainer 0 (round 1: -1),
; the leader +1.5 (round 1), +2.5 (round 2), +3 after. The leader is the
; hardest trainer of every round; only the lone wild-area boss sits higher.
; Round 1's route is the original L2-4 and must not get harder. The player's
; level tracks enemy level almost 1:1, so tune by the gap, not by absolutes.
;
; each 11-byte block:
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final route trainer of the round
;      (wBattleCount mod ROUND_BATTLES == FINAL_ROUTE_STEP), making it "somewhat stronger"
;   7-10: class counts for that final route trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings:
;round 1 (-> Gym 1, leader ace 11; final trainer 4-6)
db 0x3  ; level range
db 0x2  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, leader ace 18; final trainer 11-14)
db 0x4  ; level range
db 0x7  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 25; final trainer 17-20)
db 0x4  ; level range
db 0xC  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 31; final trainer 23-26)
db 0x4  ; level range
db 0x13 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 37; final trainer 29-32)
db 0x4  ; level range
db 0x18 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 44; final trainer 36-39)
db 0x4  ; level range
db 0x1F ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 51; final trainer 42-45)
db 0x4  ; level range
db 0x25 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 57; final trainer 49-52)
db 0x4  ; level range
db 0x2C ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road / Elite Four; final trainer 55-58)
db 0x4  ; level range
db 0x32 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon

; gym trainers (wBattleCount mod ROUND_BATTLES == FIRST_GYM_STEP..
; FINAL_GYM_TRAINER_STEP): same 11-byte layout as trainer_difficulty_settings,
; but with higher levels that approach the round's gym leader tier. The final
; gym trainer (mod ROUND_BATTLES == FINAL_GYM_TRAINER_STEP), fought right
; before the leader, gets the level bonus + rarer class distribution.
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final gym trainer of the round
;   7-10: class counts for that final gym trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings_gym:
;round 1 (-> Gym 1, leader ace 11; final trainer 6-9)
db 0x4  ; level range
db 0x4  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, leader ace 18; final trainer 12-15)
db 0x4  ; level range
db 0xA  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 25; final trainer 19-22)
db 0x4  ; level range
db 0x10 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 31; final trainer 25-28)
db 0x4  ; level range
db 0x16 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 37; final trainer 31-34)
db 0x4  ; level range
db 0x1C ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 44; final trainer 37-40)
db 0x4  ; level range
db 0x22 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 51; final trainer 44-47)
db 0x4  ; level range
db 0x29 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 57; final trainer 50-53)
db 0x4  ; level range
db 0x2F ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road / Elite Four; final trainer 56-59)
db 0x4  ; level range
db 0x35 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x5  ; final trainer: masterball class pokemon
