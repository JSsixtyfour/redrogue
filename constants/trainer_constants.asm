; Trainer class ids are stored in wCurOpponent as OPP_ID_OFFSET + class, so this
; offset caps how many classes exist: the id must fit a byte, giving
; (255 - OPP_ID_OFFSET) classes.
;
; Lowered 200 -> 160 on 2026-09-10 (gym-leader expansion, Phase 0a). At 200
; there were only 5 ids left above the 50 classes in use, and the expansion adds
; 11 (the 8 Johto leaders plus Janine, Will and Karen). 160 gives 95.
;
; Why this is safe, audited site by site 2026-09-09 and re-verified 2026-09-10:
; every read of wCurOpponent is either a zero test (`and a` for "no battle
; queued", engine/battle/core.asm InitBattle and home/overworld.asm x2), a
; straight passthrough into wCurPartySpecies/wEnemyMonSpecies2 (InitOpponent),
; or a SYMBOLIC equality (`cp OPP_RIVAL1` in core.asm, `cp OPP_RIVAL3` /
; `cp OPP_LANCE` in audio/play_battle_music.asm). There is no numeric range
; check anywhere, and the only arithmetic site - `sub OPP_ID_OFFSET` in
; InitBattleCommon - is offset-relative and adjusts itself.
;
; The offset was originally chosen to keep trainer ids clear of the 151 species
; ids, but that separation is long gone: species indexes now reach $FD (253) and
; already overlapped the old OPP range 201-250. wIsTrainerBattle is what
; actually discriminates wild from trainer, and always has been in this tree.
;
; Two dead classes ($0D UNUSED_JUGGLER, $1B CHIEF) have zero references in
; data/maps/objects/ and scripts/ and could be repurposed in place if the id
; space is ever tight again. Deleting them outright would renumber every class
; after them and require reordering five parallel tables by hand, so they are
; deliberately left alone - the offset change makes it unnecessary.
DEF OPP_ID_OFFSET EQU 160

MACRO trainer_const
	const \1
	DEF OPP_\1 EQU OPP_ID_OFFSET + \1
ENDM

; trainer class ids
; indexes for:
; - TrainerNames (see data/trainers/names.asm)
; - TrainerNamePointers (see data/trainers/name_pointers.asm)
; - TrainerDataPointers (see data/trainers/parties.asm)
; - TrainerPicAndMoneyPointers (see data/trainers/pic_pointers_money.asm)
; - TrainerAIPointers (see data/trainers/ai_pointers.asm)
; - TrainerClassMoveChoiceModifications (see data/trainers/move_choices.asm)
	const_def
	trainer_const NOBODY         ; $00
	trainer_const YOUNGSTER      ; $01
	trainer_const BUG_CATCHER    ; $02
	trainer_const LASS           ; $03
	trainer_const SAILOR         ; $04
	trainer_const JR_TRAINER_M   ; $05
	trainer_const JR_TRAINER_F   ; $06
	trainer_const POKEMANIAC     ; $07
	trainer_const SUPER_NERD     ; $08
	trainer_const HIKER          ; $09
	trainer_const BIKER          ; $0A
	trainer_const BURGLAR        ; $0B
	trainer_const ENGINEER       ; $0C
	trainer_const UNUSED_JUGGLER ; $0D
	trainer_const FISHER         ; $0E
	trainer_const SWIMMER        ; $0F
	trainer_const CUE_BALL       ; $10
	trainer_const GAMBLER        ; $11
	trainer_const BEAUTY         ; $12
	trainer_const PSYCHIC_TR     ; $13
	trainer_const ROCKER         ; $14
	trainer_const JUGGLER        ; $15
	trainer_const TAMER          ; $16
	trainer_const BIRD_KEEPER    ; $17
	trainer_const BLACKBELT      ; $18
	trainer_const RIVAL1         ; $19
	trainer_const PROF_OAK       ; $1A
	trainer_const CHIEF          ; $1B
	trainer_const SCIENTIST      ; $1C
	trainer_const GIOVANNI       ; $1D
	trainer_const ROCKET         ; $1E
	trainer_const COOLTRAINER_M  ; $1F
	trainer_const COOLTRAINER_F  ; $20
	trainer_const BRUNO          ; $21
	trainer_const BROCK          ; $22
	trainer_const MISTY          ; $23
	trainer_const LT_SURGE       ; $24
	trainer_const ERIKA          ; $25
	trainer_const KOGA           ; $26
	trainer_const BLAINE         ; $27
	trainer_const SABRINA        ; $28
	trainer_const GENTLEMAN      ; $29
	trainer_const RIVAL2         ; $2A
	trainer_const RIVAL3         ; $2B
	trainer_const LORELEI        ; $2C
	trainer_const CHANNELER      ; $2D
	trainer_const AGATHA         ; $2E
	trainer_const LANCE          ; $2F
	; Mini-boss framework classes. Reuse the rival/Giovanni name/pic/AI/money/
	; move-choice rows (they should look and battle like the real character),
	; but have their OWN TrainerDataPointers entry so mini-boss teams stay
	; isolated from the vanilla rival/Giovanni battles used elsewhere.
	trainer_const RIVAL_MINIBOSS    ; $30 — OPP_RIVAL_MINIBOSS = 208 (OPP_ID_OFFSET 160 + $30)
	trainer_const GIOVANNI_MINIBOSS ; $31 — OPP_GIOVANNI_MINIBOSS = 209
	; Paired Yellow trainer, defined for future encounters only.
	trainer_const JESSIE_JAMES     ; $32 - OPP_JESSIE_JAMES = 210
; Gym-leader expansion: the 8 Johto leaders, Janine, and the two Johto
; Elite Four members. Added 2026-09-10 (Phase 1).
	trainer_const FALKNER        ; $33
	trainer_const BUGSY          ; $34
	trainer_const WHITNEY        ; $35
	trainer_const MORTY          ; $36
	trainer_const CHUCK          ; $37
	trainer_const JASMINE        ; $38
	trainer_const PRYCE          ; $39
	trainer_const CLAIR          ; $3A
	trainer_const JANINE         ; $3B
	trainer_const WILL           ; $3C
	trainer_const KAREN          ; $3D
DEF NUM_TRAINERS EQU const_value - 1

; Trainer-card face/badge blocks (gfx/trainer_card/badges.png, blitted by
; DrawTrainerInfo, drawn by DrawBadges). One block per gym leader that can ever
; appear on the card: the Kanto eight, the Johto eight, and Janine.
;
; This is a SEPARATE index space from the trainer class ids above, and is not
; derivable from them - the Kanto eight must stay in wObtainedBadges BIT order
; (BIT_BOULDERBADGE..BIT_EARTHBADGE) because DrawBadges walks that bitfield
; LSB-first and indexes the sheet with the same counter, whereas their class ids
; are BROCK $22, MISTY $23, LT_SURGE $24, ERIKA $25, KOGA $26, BLAINE $27,
; SABRINA $28, GIOVANNI $1D - neither contiguous nor in badge order. Phase 4
; adds the class -> block lookup; the sheet's block map is documented in
; tools/make_placeholder_badges.py.
;
; Elite Four members get no block: WILL and KAREN never appear on the card, and
; KOGA's E4 appearance reuses his gym-leader block.
DEF NUM_CARD_LEADERS EQU 17
DEF CARD_TILES_PER_LEADER EQU 8 ; 4 face + 4 badge, badge second (DrawBadges `add 4`)

; The sheet holds one more block than there are leaders: the leader blocks, then
; CARD_BLOCK_UNKNOWN. Keep this and NUM_CARD_LEADERS distinct - the scan over
; CardLeaderClasses is bounded by the LEADER count, so folding the "?" into it
; would make the resolver able to return it as if it were somebody's portrait.
DEF NUM_CARD_BLOCKS EQU NUM_CARD_LEADERS + 1

; The block drawn in a slot whose leader the player is not entitled to know:
; every unearned slot except the one the next-gym reveal may fill.
;
; This was GIOVANNI's block until 2026-09-11, which worked for free because he
; was vanilla's hidden eighth leader and his FACE half IS the "?" glyph. The
; next-gym-leader reveal needs those two meanings separated: with the reveal on,
; a queued Giovanni would draw the same "?" as an unknown slot. So the glyph now
; has a block of its own, sourced from gfx/trainer_card/unknown_face.png rather
; than copied from block 7, so that dropping a real Giovanni portrait into block
; 7 cannot silently overwrite it.
;
; BOTH halves of the block are the glyph. The badge half is reachable:
; RogueCardBlockForSlot lands here when a recorded class is missing from
; CardLeaderClasses, and that slot IS earned, so DrawBadges draws the badge half.
DEF CARD_BLOCK_UNKNOWN EQU NUM_CARD_LEADERS
