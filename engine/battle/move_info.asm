PrintMenuItem:
	xor a
	ldh [hAutoBGTransferEnabled], a
	hlcoord 0, 4
	ld b, 7
	ld c, 9
	call TextBoxBorder
	ld a, [wPlayerDisabledMove]
	and a
	jr z, .notDisabled
	swap a
	and $f
	ld b, a
	ldh a, [hCurrentMenuItem]
	cp b
	jr nz, .notDisabled
	hlcoord 1, 7
	ld de, DisabledText
	call PlaceString
	jp .moveDisabled
.notDisabled
	ld hl, hCurrentMenuItem
	dec [hl]
	xor a
	ldh [hWhoseTurn], a
	ld hl, wBattleMonMoves
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld b, $0 ; which item in the menu is the cursor pointing to? (0-3)
	add hl, bc ; point to the item (move) in memory
	ld a, [hl]
	ld [wPlayerSelectedMove], a ; update wPlayerSelectedMove even if the move
	                            ; isn't actually selected (just pointed to by the cursor)
	ld a, [wPlayerMonNumber]
	ldh [hWhichPokemon], a
	ld a, BATTLE_MON_DATA
	ld [wMonDataLocation], a
	; GetCurrentMove is in Battle Core, which is a different ROM bank.
	; Besides using wNameBuffer, it writes the move ID through
	; wNamedObjectIndex, which aliases wMaxPP. Calculate both PP values only
	; after this farcall has finished clobbering shared scratch.
	farcall GetCurrentMove
	callfar GetMaxPP
	ld hl, hCurrentMenuItem
	ld c, [hl]
	inc [hl]
	ld b, $0
	ld hl, wBattleMonPP
	add hl, bc
	ld a, [hl]
	and PP_MASK
	ld [wBattleMenuCurrentPP], a
; print the move information box
	hlcoord 1, 5
	ld de, TypeText
	call PlaceString
	hlcoord 1, 9
	ld de, PPText
	call PlaceString
	hlcoord 4, 9
	ld de, wBattleMenuCurrentPP
	lb bc, 1, 2
	call PrintNumber
	hlcoord 6, 9
	ld [hl], '/'
	hlcoord 7, 9
	ld de, wMaxPP
	lb bc, 1, 2
	call PrintNumber
	; Type and type effectiveness share the first row.  Keep the
	; effectiveness readout separate from the damage path: the preview is
	; intentionally type-only and does not include RogueElementBoyDamageBoost.
	farcall PreviewTypeMatchup
	ld a, e
	ld d, a
	ld a, [wPlayerMovePower]
	and a
	jp z, .noPower
	; Power 1 marks a move whose damage ignores power (fixed damage, OHKO,
	; Super Fang, Counter). Typing never changes it, immunity included, and it
	; never crits, so PWR, effectiveness and CRIT all show "-". Display only.
	cp 1
	ld de, NoPowerText
	jr z, .printEffectiveness
	ld a, d
	cp NO_EFFECT
	jr z, .effectiveness0
	cp NOT_VERY_EFFECTIVE
	jr z, .effectivenessQuarter
	cp NOT_VERY_EFFECTIVE * 2
	jr z, .effectivenessHalf
	cp EFFECTIVE * 2
	jr z, .effectivenessNeutral
	cp SUPER_EFFECTIVE * 2
	jr z, .effectivenessDouble
	cp SUPER_EFFECTIVE * 4
	jr z, .effectivenessQuad
	ld de, EffectivenessNeutralText
	jr .printEffectiveness
.effectiveness0
	ld de, Effectiveness0Text
	jr .printEffectiveness
.effectivenessQuarter
	ld de, EffectivenessQuarterText
	jr .printEffectiveness
.effectivenessHalf
	ld de, EffectivenessHalfText
	jr .printEffectiveness
.effectivenessNeutral
	ld de, EffectivenessNeutralText
	jr .printEffectiveness
.effectivenessDouble
	ld de, EffectivenessDoubleText
	jr .printEffectiveness
.effectivenessQuad
	ld de, EffectivenessQuadText
.printEffectiveness
	hlcoord 6, 5
	call PlaceString
	hlcoord 2, 6
	predef PrintMoveType

.power
	hlcoord 1, 7
	ld de, PowerText
	call PlaceString
	ld a, [wPlayerMovePower]
	ld de, NoPowerText
	hlcoord 6, 7
	cp 1
	jr nz, .printPower
	call PlaceString
	jr .accuracy
.printPower
	ld de, wPlayerMovePower
	lb bc, 1, 3
	call PrintNumber

.accuracy
	hlcoord 1, 8
	ld de, AccuracyText
	call PlaceString
	; Move accuracy is stored as a percent-scaled byte (100% = 255).
	; Add 255 before dividing to round acc * 100 / 256.
	ld a, [wPlayerMoveAccuracy]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 8
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'

.crit
	hlcoord 1, 10
	ld de, CritText
	call PlaceString
	ld a, [wPlayerMovePower]
	cp 1 ; power-1 moves never crit (see above)
	jr nz, .critRate
	hlcoord 6, 10
	ld de, NoPowerText
	call PlaceString
	jp .effectRow
.critRate
	farcall CalcCritRate
	jr c, .guaranteedCrit
	; A zero-power move returns Z from CalcCritRate and is handled by
	; .noPower, so a non-guaranteed result here has a real threshold in e.
	ld a, e
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 10
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	jp .effectRow

.guaranteedCrit
	ld a, 100
	ld [wStringBuffer], a
	hlcoord 6, 10
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	jp .effectRow

.noPower
	hlcoord 6, 5
	ld de, NoPowerText
	call PlaceString
	hlcoord 2, 6
	predef PrintMoveType
	; Status moves have no damage/effectiveness/crit rate to preview.
	; Sleep Clause: a sleep move that would be blocked shows SLEEP BAN in the
	; PWR row (always "---" for it). A warning only: it stays selectable,
	; because the clause is re-checked when the move runs.
	ld a, [wPlayerMoveEffect]
	cp SLEEP_EFFECT
	jr nz, .showNoPower
	ld d, SLEEP_CLAUSE_ENEMY_SIDE
	farcall SleepClauseIsActive
	jr nc, .showNoPower
	hlcoord 1, 7
	ld de, SleepBanText
	call PlaceString
	jr .noPowerAccuracy
.showNoPower
	hlcoord 1, 7
	ld de, PowerText
	call PlaceString
	hlcoord 6, 7
	ld de, NoPowerText
	call PlaceString
.noPowerAccuracy
	hlcoord 1, 8
	ld de, AccuracyText
	call PlaceString
	; Accuracy remains meaningful for status moves, so it is still shown.
	ld a, [wPlayerMoveAccuracy]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 8
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	hlcoord 1, 10
	ld de, CritText
	call PlaceString
	hlcoord 6, 10
	ld de, NoPowerText
	call PlaceString
.effectRow
	call PrintMoveEffectRow
.moveDisabled
	ld a, $1
	ldh [hAutoBGTransferEnabled], a
	jp Delay3

; The bottom row of the move info box: what the move does besides its damage.
; A move with a chance to do it shows that chance, rolled through the same
; Bridge threshold hooks the battle uses (hWhoseTurn is 0 here, set above), so
; a gift that raises the chance raises the number. The chance is per hit and
; does not know whether the target is already statused or immune.
DEF MOVE_EFFECT_ADJUST_NONE   EQU 0
DEF MOVE_EFFECT_ADJUST_STATUS EQU 1
DEF MOVE_EFFECT_ADJUST_FLINCH EQU 2

PrintMoveEffectRow:
	ld a, [wPlayerMoveEffect]
	and a
	jr nz, .hasEffect
	; No extra effect: a lone dash, in the value column like PWR/CRIT's.
	hlcoord 6, 11
	ld de, NoPowerText
	jp PlaceString

.hasEffect
	ld c, a
	; Moves whose effect id does not tell the whole story.
	; Dig shares CHARGE_EFFECT with SolarBeam but dodges like Fly.
	ld a, [wPlayerMoveNum]
	ld de, DodgeOneTurnText
	cp DIG
	jr z, .placeOverride
	; Rest shares HEAL_EFFECT with Recover but always heals to full.
	ld de, RestText
	cp REST
	jr z, .placeOverride
	; Toxic shares POISON_EFFECT but badly poisons (BridgeInflictPoisonStatus);
	; with the Deadly Venom gift every player poison does.
	ld de, BadPoisonText
	cp TOXIC
	jr z, .placeOverride
	ld a, c
	cp POISON_EFFECT
	jr nz, .notPoisonEffect
	ld e, BRIDGE_EFFECT_TOXIC_POISON
	call .hasGlobalEffect
	ld de, BadPoisonText
	jr c, .placeOverride
	jp .statRuns
.notPoisonEffect
	; Ordinary recoil is 1/4 of the damage dealt (Struggle's 1/2 never shows in
	; the menu); the Dulled Senses gift removes it (RecoilEffect_).
	cp RECOIL_EFFECT
	jr nz, .notRecoil
	ld e, BRIDGE_EFFECT_NO_RECOIL
	call .hasGlobalEffect
	ld de, NoRecoilText
	jr c, .placeOverride
	ld de, RecoilQuarterText
.placeOverride
	hlcoord 1, 11
	jp PlaceString

; In: e = BRIDGE_EFFECT_*. Out: carry if the player holds it; bc kept.
.hasGlobalEffect
	push bc
	farcall BridgeHasGlobalEffect
	pop bc
	ret

.notRecoil
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .fixedDamage
	; Recover/Softboiled heal 1/2 of max HP and drains heal 1/2 of the damage
	; dealt, both scaled by the same healing gifts the moves run through
	; (heal.asm, drain_hp.asm), which take the amount in de.
	cp HEAL_EFFECT
	jr z, .heal
	cp DRAIN_HP_EFFECT
	jr nz, .statRuns
	call PlaceMoveEffectLabel
	ld de, 50
	farcall BridgeScaleDrainHealingAmount
	jr .printHealPercent
.heal
	call PlaceMoveEffectLabel
	ld de, 50
	farcall BridgeScalePlayerHealingMoveAmount
.printHealPercent
	ld a, e
	jp .printPercent

.fixedDamage
	; Same choices as core.asm's .specialDamage for the player.
	call PlaceMoveEffectLabel
	ld a, [wPlayerMoveNum]
	ld b, SONICBOOM_DAMAGE
	cp SONICBOOM
	jr z, .printFixedDamage
	ld b, DRAGON_RAGE_DAMAGE
	cp DRAGON_RAGE
	jr z, .printFixedDamage
	cp PSYWAVE
	ld a, [wBattleMonLevel]
	ld b, a
	jr z, .psywave
.printFixedDamage ; Seismic Toss, Night Shade: the user's level
	ld a, b
	ld [wStringBuffer], a
	hlcoord 5, 11
	ld de, wStringBuffer
	lb bc, LEFT_ALIGN | 1, 3
	jp PrintNumber

.psywave
	; Up to level 170: random in [1, level * 3/2). Above (Endless,
	; PsywaveLargeDamage): r + r/2 for r in [0, level]. Show the range.
	ld l, a
	ld h, 0
	srl a
	ld e, a
	ld d, 0
	add hl, de
	ld a, b
	cp PSYWAVE_BYTE_MAX_LEVEL + 1
	jr nc, .psywaveMax
	dec hl
.psywaveMax
	ld a, h
	ld [wStringBuffer], a
	ld a, l
	ld [wStringBuffer + 1], a
	hlcoord 5, 11
	ld [hl], '1'
	inc hl
	ld [hl], '-'
	inc hl
	ld de, wStringBuffer
	lb bc, LEFT_ALIGN | 2, 3
	jp PrintNumber

.statRuns
	; Stat stage effects come in runs of six (ATK DEF SPD SPC ACC EVA) and are
	; built from a stat name and a sign/stage instead of 30 stored labels.
	ld hl, MoveEffectStatRuns
.statRun
	ld a, [hli]
	cp $ff
	jr z, .notStat
	ld b, a
	ld a, c
	sub b
	cp 6 ; ATK DEF SPD SPC ACC EVA
	jr c, .stat
	inc hl
	inc hl
	jr .statRun

.stat
	push hl
	ld c, a
	ld b, 0
	ld hl, MoveEffectStatNames
	add hl, bc
	add hl, bc
	add hl, bc
	decoord 1, 11
	ld bc, 3
	call CopyData
	pop hl
	ld a, [hli] ; '+' or '-'
	ld [de], a
	inc de
	ld a, [hl] ; stage digit, or 0 for a side-effect chance
	and a
	jr z, .statChance
	ld [de], a
	ret

.statChance
	lb de, MOVE_EFFECT_ADJUST_NONE, 33 percent + 1
	jr .printChance

.notStat
	ld hl, MoveEffectChances
.chanceLoop
	ld a, [hli]
	cp $ff
	jr z, PlaceMoveEffectLabel
	cp c
	jr z, .chanceFound
	inc hl
	inc hl
	jr .chanceLoop

.chanceFound
	ld a, [hli]
	ld e, a
	ld d, [hl]
	push de
	call PlaceMoveEffectLabel
	pop de
.printChance
	; d = which Bridge hook adjusts the threshold in e
	ld a, d
	cp MOVE_EFFECT_ADJUST_STATUS
	jr nz, .notStatusAdjust
	farcall BridgeAdjustStatusChanceThreshold
	jr .adjusted
.notStatusAdjust
	cp MOVE_EFFECT_ADJUST_FLINCH
	jr nz, .adjusted
	farcall BridgeAdjustFlinchThreshold
.adjusted
	; The roll succeeds when Random < e, so the chance is e / 256. Rounded to
	; nearest (not up, like ACC/CRIT) so 10% reads 10 rather than 11.
	ld c, e
	ld b, 0
	ld hl, 128
	ld a, 100
	call AddNTimes
	ld a, h
.printPercent
	ld [wStringBuffer], a
	hlcoord 6, 11
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	ret

; In: c = move effect. Places its label at the effect row; nothing if unlisted.
PlaceMoveEffectLabel:
	ld hl, MoveEffectLabels
.entry
	ld b, 0
.ids
	ld a, [hli]
	cp $ff
	ret z
	; Every effect id is below the first text glyph (' ' = $7F), so the first
	; byte at or above it starts this entry's label.
	cp ' '
	jr nc, .text
	cp c
	jr nz, .ids
	inc b
	jr .ids
.text
	dec hl
	dec b
	jr z, .found
.skip
	ld a, [hli]
	cp '@'
	jr nz, .skip
	jr .entry
.found
	ld d, h
	ld e, l
	hlcoord 1, 11
	jp PlaceString

ASSERT NUM_MOVE_EFFECTS < ' '

; first effect of a six-stat run, sign, stage digit (0 = a 33% side effect)
MoveEffectStatRuns:
	db ATTACK_UP1_EFFECT, "+1"
	db ATTACK_DOWN1_EFFECT, "-1"
	db ATTACK_UP2_EFFECT, "+2"
	db ATTACK_DOWN2_EFFECT, "-2"
	db ATTACK_DOWN_SIDE_EFFECT, "-", 0 ; only ATK..SPC exist; $48-$4B are unused
	db -1

MoveEffectStatNames:
	db "ATKDEFSPDSPCACCEVA"

; effect, threshold (Random below it succeeds), Bridge adjust hook.
; Thresholds copied from effects.asm (PoisonEffect, FreezeBurnParalyzeEffect,
; FlinchSideEffect, ConfusionSideEffect); Twineedle rolls POISON_SIDE_EFFECT1.
MoveEffectChances:
	db POISON_SIDE_EFFECT1,   20 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db POISON_SIDE_EFFECT2,   40 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db TWINEEDLE_EFFECT,      20 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db BURN_SIDE_EFFECT1,     10 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db FREEZE_SIDE_EFFECT1,   10 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db PARALYZE_SIDE_EFFECT1, 10 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db BURN_SIDE_EFFECT2,     30 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db FREEZE_SIDE_EFFECT2,   30 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db PARALYZE_SIDE_EFFECT2, 30 percent + 1, MOVE_EFFECT_ADJUST_STATUS
	db FLINCH_SIDE_EFFECT1,   10 percent + 1, MOVE_EFFECT_ADJUST_FLINCH
	db FLINCH_SIDE_EFFECT2,   30 percent + 1, MOVE_EFFECT_ADJUST_FLINCH
	db CONFUSION_SIDE_EFFECT, 10 percent,     MOVE_EFFECT_ADJUST_NONE
	db -1

; one or more effect ids, then the label (at most 9 tiles; 5 if it has a chance)
MoveEffectLabels:
	db POISON_SIDE_EFFECT1, POISON_SIDE_EFFECT2, "PSN@"
	db BURN_SIDE_EFFECT1, BURN_SIDE_EFFECT2, "BRN@"
	db FREEZE_SIDE_EFFECT1, FREEZE_SIDE_EFFECT2, "FRZ@"
	db PARALYZE_SIDE_EFFECT1, PARALYZE_SIDE_EFFECT2, "PARA@"
	db FLINCH_SIDE_EFFECT1, FLINCH_SIDE_EFFECT2, "FLNC@"
	db CONFUSION_SIDE_EFFECT, "CONF@"
	db TWINEEDLE_EFFECT, "2H PSN@" ; its chance prints from column 7: "2H PSN20%"
	db DRAIN_HP_EFFECT, "DRAIN@"
	db DREAM_EATER_EFFECT, "SLP DRAIN@"
	db EXPLODE_EFFECT, "SELF-KO@"
	db MIRROR_MOVE_EFFECT, "MIRROR@"
	db PAY_DAY_EFFECT, "PAY DAY@"
	db SWIFT_EFFECT, "SURE HIT@"
	db CONVERSION_EFFECT, "CONVERT@"
	db HAZE_EFFECT, "CLR STATS@"
	db BIDE_EFFECT, "STORE DMG@"
	db THRASH_PETAL_DANCE_EFFECT, "RAMPAGE@"
	db SWITCH_AND_TELEPORT_EFFECT, "ESCAPE@"
	db TWO_TO_FIVE_ATTACKS_EFFECT, "2-5 HITS@"
	db ATTACK_TWICE_EFFECT, "2 HITS@"
	db SLEEP_EFFECT, "SLEEP@"
	db OHKO_EFFECT, "OHKO@"
	db CHARGE_EFFECT, "2 TURNS@"
	db FLY_EFFECT, "DODGE 1T@"
	db SUPER_FANG_EFFECT, "HALF HP@"
	db SPECIAL_DAMAGE_EFFECT, "DMG@"
	db TRAPPING_EFFECT, "TRAP@"
	db JUMP_KICK_EFFECT, "MISS HURT@"
	db MIST_EFFECT, "STATGUARD@"
	db FOCUS_ENERGY_EFFECT, "CRIT UP@"
	db CONFUSION_EFFECT, "CONFUSE@"
	db HEAL_EFFECT, "HEAL@"
	db TRANSFORM_EFFECT, SUPER_TRANSFORM_EFFECT, "TRANSFORM@"
	db LIGHT_SCREEN_EFFECT, "SPC 1/2@"
	db REFLECT_EFFECT, "ATK 1/2@"
	db POISON_EFFECT, "POISON@"
	db PARALYZE_EFFECT, "PARALYZE@"
	db SUBSTITUTE_EFFECT, "SUB 1/4HP@"
	db HYPER_BEAM_EFFECT, "RECHARGE@"
	db RAGE_EFFECT, "RAGE@"
	db MIMIC_EFFECT, "MIMIC@"
	db METRONOME_EFFECT, "RANDOM@"
	db LEECH_SEED_EFFECT, "LEECH@"
	db SPLASH_EFFECT, "USELESS@"
	db DISABLE_EFFECT, "DISABLE@"
	db -1

RestText:
	db "HEAL 100%@"

DodgeOneTurnText:
	db "DODGE 1T@"

BadPoisonText:
	db "BAD PSN@"

RecoilQuarterText:
	db "RECOIL1/4@"

NoRecoilText:
	db "NO RECOIL@"

DisabledText:
	db "disabled!@"

SleepBanText:
	db "SLEEP BAN@"

TypeText:
	db "TYPE@"

PowerText:
	db "PWR@"

AccuracyText:
	db "ACC@"

PPText:
	db "PP@"

CritText:
	db "CRIT@"

NoPowerText:
	db "-@"

Effectiveness0Text:
	db "x0@"

EffectivenessQuarterText:
	db "x1/4@"

EffectivenessHalfText:
	db "x1/2@"

EffectivenessNeutralText:
	db "x1@"

EffectivenessDoubleText:
	db "x2@"

EffectivenessQuadText:
	db "x4@"
