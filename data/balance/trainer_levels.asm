; Route and gym trainer level tiers. INCLUDEd in place by
; custom_functions/func_enc_gen.asm: it must stay in that section. GetRandRoster
; reads it with a plain [hl], and GetRewardMonLevel reads it cross-bank through
; BANK(trainer_difficulty_settings). Part of the balance system, see
; constants/balance_constants.asm.

; one 11-byte block per round (round = wBattleCount / ROUND_BATTLES, capped at 8).
; Curve D (BALANCE_PHASE5_PLAN.md D, 2026-09-28): leader aces 15 23 30 36 42 47
; 52 57. Route trainers start just under the previous leader's ace (A-1, range
; 4, final +2); gym trainers sit at A-7..A-4 with the final at A-5..A-2.
;
; each 11-byte block:
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final (5th) route trainer of the round
;      (wBattleCount mod 10 == 5), making it "somewhat stronger"
;   7-10: class counts for that final route trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings:
;round 1 (-> Gym 1, leader ace 15; final trainer 4-6)
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
;round 2 (-> Gym 2, leader ace 23; final trainer 16-19)
db 0x4  ; level range
db 0xE  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 30; final trainer 24-27)
db 0x4  ; level range
db 0x16 ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 36; final trainer 31-34)
db 0x4  ; level range
db 0x1D ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 42; final trainer 37-40)
db 0x4  ; level range
db 0x23 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 47; final trainer 43-46)
db 0x4  ; level range
db 0x29 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 52; final trainer 48-51)
db 0x4  ; level range
db 0x2E ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 57; final trainer 53-56)
db 0x4  ; level range
db 0x33 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road, no gym leader; also covers Elite Four overflow)
db 0x4  ; level range
db 0x38 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon

; gym trainers (wBattleCount mod 10 == 6-9): same 11-byte layout as
; trainer_difficulty_settings, but with higher levels that approach the
; round's gym leader tier. The 4th gym trainer (mod 10 == 9), fought right
; before the leader, gets the level bonus + rarer class distribution.
;   0: level range
;   1: minimum level
;   2-5: normal class counts (pokeball, greatball, ultraball, masterball)
;   6: level bonus for the final (4th) gym trainer of the round
;   7-10: class counts for that final gym trainer - same total as 2-5,
;      but shifted toward rarer classes
trainer_difficulty_settings_gym:
;round 1 (-> Gym 1, leader ace 15; final trainer 10-13)
db 0x4  ; level range
db 0x8  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, leader ace 23; final trainer 18-21)
db 0x4  ; level range
db 0x10 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, leader ace 30; final trainer 25-28)
db 0x4  ; level range
db 0x17 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, leader ace 36; final trainer 31-34)
db 0x4  ; level range
db 0x1D ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, leader ace 42; final trainer 37-40)
db 0x4  ; level range
db 0x23 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, leader ace 47; final trainer 42-45)
db 0x4  ; level range
db 0x28 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, leader ace 52; final trainer 47-50)
db 0x4  ; level range
db 0x2D ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, leader ace 57; final trainer 52-55)
db 0x4  ; level range
db 0x32 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road, no gym leader; also covers Elite Four overflow)
db 0x4  ; level range
db 0x3A ; minimum level
db 0x0  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x5  ; final trainer: masterball class pokemon
