; Route and gym trainer level tiers. INCLUDEd in place by
; custom_functions/func_enc_gen.asm: it must stay in that section. GetRandRoster
; reads it with a plain [hl], and GetRewardMonLevel reads it cross-bank through
; BANK(trainer_difficulty_settings). Part of the balance system, see
; constants/balance_constants.asm.

; one 11-byte block per round (round = wBattleCount / ROUND_BATTLES, capped at 8).
; Curve F (2026-10-02, BALANCE_LEVEL_SPIKE.md), then Curve G (10-10) and Plan K
; (2026-11-08). Leader aces 13 20 27 30 36 43 47 54.
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
;round 1 (-> Gym 1, leader ace 13; final trainer 6-8)
db 0x3  ; level range
db 0x4  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, leader ace 20; final trainer 13-16)
db 0x4  ; level range
db 0x9  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 27; final trainer 19-23)
db 0x5  ; level range
db 0xE  ; minimum level
db 0x3  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 30; final trainer 23-26)
db 0x4  ; level range
db 0x13 ; minimum level
db 0x2  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 36; final trainer 28-31)
db 0x4  ; level range
db 0x17 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 43; final trainer 35-38)
db 0x4  ; level range
db 0x1E ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 47; final trainer 38-41)
db 0x4  ; level range
db 0x21 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 54; final trainer 45-48)
db 0x4  ; level range
db 0x28 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road / Elite Four; final trainer 53-56)
db 0x4  ; level range
db 0x30 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x5  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon

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
;round 1 (-> Gym 1, leader ace 13; final trainer 8-11)
db 0x4  ; level range
db 0x6  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, leader ace 20; final trainer 14-17)
db 0x4  ; level range
db 0xC  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 27; final trainer 21-25)
db 0x5  ; level range
db 0x12 ; minimum level
db 0x2  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 30; final trainer 24-28)
db 0x5  ; level range
db 0x15 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 36; final trainer 30-33)
db 0x4  ; level range
db 0x1B ; minimum level
db 0x0  ; pokeball class pokemon
db 0x4  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 43; final trainer 36-39)
db 0x4  ; level range
db 0x21 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 47; final trainer 40-43)
db 0x4  ; level range
db 0x25 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x4  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 54; final trainer 47-50)
db 0x4  ; level range
db 0x2C ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road / Elite Four; final trainer 54-57)
db 0x4  ; level range
db 0x33 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x4  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
