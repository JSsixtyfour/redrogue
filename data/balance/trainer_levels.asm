; Route and gym trainer level tiers. INCLUDEd in place by
; custom_functions/func_enc_gen.asm: it must stay in that section. GetRandRoster
; reads it with a plain [hl], and GetRewardMonLevel reads it cross-bank through
; BANK(trainer_difficulty_settings). Part of the balance system, see
; constants/balance_constants.asm.

; one 7-byte block per round (round = wBattleCount / 10, capped at 8).
; each round's trainers ramp up to just under that round's gym leader tier:
; gym tiers are 8-10, 18-21, 21-24, 29, 37-43, 37-43, 40-47, 42-50
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
;round 1 (-> Gym 1, 8-10)
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
;round 2 (-> Gym 2, 18-21)
db 0x4  ; level range
db 0xC  ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 3 (-> Gym 3, 21-24)
db 0x4  ; level range
db 0x11 ; minimum level
db 0x2  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x1  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, 29)
db 0x5  ; level range
db 0x16 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, 37-43)
db 0x6  ; level range
db 0x1C ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x3  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, 37-43)
db 0x6  ; level range
db 0x21 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, 40-47)
db 0x6  ; level range
db 0x26 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x2  ; final route trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, 42-50)
db 0x7  ; level range
db 0x2A ; minimum level
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
db 0x8  ; level range
db 0x2E ; minimum level
db 0x0  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x4  ; final route trainer level bonus
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
;round 1 (-> Gym 1, 8-10)
db 0x3  ; level range
db 0x5  ; minimum level
db 0x1  ; pokeball class pokemon
db 0x1  ; greatball class pokemon
db 0x0  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x0  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 2 (-> Gym 2, 18-21)
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
;round 3 (-> Gym 3, 21-24)
db 0x4  ; level range
db 0x15 ; minimum level
db 0x1  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 4 (-> Gym 4, 29)
db 0x5  ; level range
db 0x1A ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x0  ; masterball class pokemon
db 0x2  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x0  ; final trainer: masterball class pokemon
;round 5 (-> Gym 5, 37-43)
db 0x6  ; level range
db 0x22 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x3  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x2  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 6 (-> Gym 6, 37-43)
db 0x6  ; level range
db 0x26 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x1  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x1  ; final trainer: masterball class pokemon
;round 7 (-> Gym 7, 40-47)
db 0x6  ; level range
db 0x2A ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x2  ; ultraball class pokemon
db 0x2  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x3  ; final trainer: ultraball class pokemon
db 0x2  ; final trainer: masterball class pokemon
;round 8 (-> Gym 8, 42-50)
db 0x7  ; level range
db 0x2E ; minimum level
db 0x0  ; pokeball class pokemon
db 0x2  ; greatball class pokemon
db 0x1  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x3  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x1  ; final trainer: greatball class pokemon
db 0x2  ; final trainer: ultraball class pokemon
db 0x3  ; final trainer: masterball class pokemon
;round 9 (-> Victory Road, no gym leader; also covers Elite Four overflow)
db 0x8  ; level range
db 0x36 ; minimum level
db 0x0  ; pokeball class pokemon
db 0x0  ; greatball class pokemon
db 0x3  ; ultraball class pokemon
db 0x3  ; masterball class pokemon
db 0x4  ; final gym trainer level bonus
db 0x0  ; final trainer: pokeball class pokemon
db 0x0  ; final trainer: greatball class pokemon
db 0x1  ; final trainer: ultraball class pokemon
db 0x5  ; final trainer: masterball class pokemon
