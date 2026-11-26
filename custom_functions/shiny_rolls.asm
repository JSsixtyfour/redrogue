; custom_functions/shiny_rolls.asm
;
; Whether a newly made mon is shiny. Everything that decides it is here; the flag
; itself is BIT_SHINY of the catch-rate byte (func_shiny.asm) and display reads it
; from the struct.
;
; What you are shown is what you get:
;   - a reward offer (wSpawnDVSlot 1-3) uses the roll stored with its DVs
;     (sRogueOfferShiny), so its INFO screen, the party mon and the box mon agree;
;   - a wild mon is rolled as its battle starts (GetEnemyCatchRateByte) and keeps
;     that result if it is caught or joins afterwards;
;   - anything else is rolled as it is created, in the party or in the box.
;
; Included in "Bridge Extended Effects": GetEnemyCatchRateByte plain-calls
; NewMonShiny. Everything with a :: is farcall-safe (results in e).

; ---------------------------------------------------------------------------
; AddPartyMonShiny - for _AddPartyMon, which makes trainer mons too.
; OUT: e = 1 << BIT_SHINY or 0. Preserves wCurPartySpecies. Clobbers the rest.
; A trainer's mon only ever rolls. A wild mon caught into the party keeps the
; flag it was fought with.
AddPartyMonShiny::
	ld a, [wMonDataLocation]
	and $f
	jr nz, RollShiny
	ldh a, [hIsInBattle]
	dec a
	jr nz, NewMonShiny
	ld a, [wEnemyMonCatchRate]
	and 1 << BIT_SHINY
	ld e, a
	ret

; ---------------------------------------------------------------------------
; NewMonShiny - honours a decision already made (wSpawnShiny), then a reward
; offer's stored roll, then rolls. Same outputs as above.
NewMonShiny:
	ld a, [wSpawnShiny]
	bit BIT_SPAWN_SHINY_DECIDED, a
	jr z, .notDecided
	and 1 << BIT_SHINY
	ld e, a
	ret
.notDecided
	ld a, [wSpawnDVSlot]
	and a
	jr z, RollShiny
	ld e, a
	; fall through

; IN: e = offer slot 1-3. OUT: e as above.
OfferShiny:
	farcall GetRogueOfferDVs ; e = the offer's stored shiny roll
	ld b, e
	jr ShinyFromRoll

RollShiny:
	call Random
	ld b, a
	; fall through

; IN: b = a byte roll. OUT: e = 1 << BIT_SHINY if it beats the odds, else 0.
; The base rate is 1/256; an active SHINY CHARM raises the threshold. Compared
; now, not when the byte was rolled, so equipping the charm changes what INFO
; shows and what taking the offer gives together (as the DV BOOSTER does).
ShinyFromRoll:
	ld a, [wCurPartySpecies]       ; wCurItem is the same byte
	push af
	push bc
	ld a, SHINY_CHARM
	ld [wCurItem], a
	farcall GetKeyItemPowerInE     ; e = 0 (not active) or 1-3 (displayed tier)
	pop bc
	pop af
	ld [wCurPartySpecies], a
	ld hl, ShinyThresholdTable
	ld d, 0
	add hl, de
	ld a, b
	cp [hl]
	ld e, 0
	ret nc
	ld e, 1 << BIT_SHINY
	ret

ShinyThresholdTable:
; Index 0 is the base rate with no charm active; GetKeyItemPower's 1-4
; (1 + stored tier 0-3) select entries 1-4. Doubles each tier; 16/256 = 6.3%.
	table_width 1
	db 1, 2, 4, 8, 16
	assert_table_length 5

; ---------------------------------------------------------------------------
; For GetEnemyCatchRateByte's wild branch. IN: e = the byte built so far (form
; bits). OUT: e with the shiny bit added. This runs for a wild battle, and for a
; mon going straight to the box (LoadEnemyMonData outside battle).
; A capture rebuilds the enemy under TRANSFORMED, so that its DVs stay; the shiny
; flag it was fought with stays the same way.
WildMonAddShiny:
	ld a, [wEnemyBattleStatus3]
	bit TRANSFORMED, a
	jr nz, .keep
	push de
	call NewMonShiny
	ld a, e
	pop de
	jr .add
.keep
	ld a, [wEnemyMonCatchRate]
	and 1 << BIT_SHINY
.add
	or e
	ld e, a
	ret

; ---------------------------------------------------------------------------
; A wild mon that joins after its battle is the one just fought: the gift made
; next takes its shiny flag. wEnemyMon is still what the battle left there.
; Clobbers a.
JoiningMonKeepShiny::
	ld a, [wEnemyMonCatchRate]
	and 1 << BIT_SHINY
	or 1 << BIT_SPAWN_SHINY_DECIDED
	ld [wSpawnShiny], a
	ret

; The four wild-area bosses' join offers: the level they always used, plus the
; above. OUT: wCurEnemyLevel.
PCGetBossGiftLevel::
	farcall PCGetBossLevel
	jr JoiningMonKeepShiny

; ---------------------------------------------------------------------------
; The INFO screen (reward_offer_info.asm).

; OUT: e = nonzero (z clear) if the offer on the INFO screen is shiny. z when it
; isn't, or when no offer preview is up ($80 | id is the Pokedex Forms page).
RewardInfoShiny:
	ld a, [wRewardInfoSlot]
	ld e, a
	and a
	jr z, .done
	bit 7, a
	ld e, 0
	jr nz, .done
	ld e, a
	call OfferShiny
.done
	ld a, e
	and a
	ret

; From SetPal_Pokedex, with the species palette already in wPalPacket + 3: the
; previewed offer's form palette, then its shiny one. Clobbers everything.
RewardInfoPalette::
	farcall RewardInfoFormPalette  ; e = palette, 0 = keep the species one
	ld a, e
	and a
	jr z, .noFormPalette
	ld [wPalPacket + 3], a
.noFormPalette
	call RewardInfoShiny
	ret z
	ld a, [wPalPacket + 3]
	ld e, a
	farcall ShinyPaletteConvertInE
	ld a, e
	ld [wPalPacket + 3], a
	ret

; Page 2 of the INFO screen: the DVs, and the battle HUD's shiny mark before the
; name. Clobbers everything.
PrintRewardOfferDetails::
	farcall PrintRewardOfferDVs
	call RewardInfoShiny
	ret z
	hlcoord 8, 2
	ld [hl], '<HUD_SHINY>'
	ret

; ---------------------------------------------------------------------------
; A gift that copies an existing mon, delivered to the box because the party is
; full. GivePokemon has just front-inserted a fresh mon at wBoxMon1; these make
; it the exact copy. A box mon keeps the party struct's first
; BOXMON_STRUCT_LENGTH bytes and its level; the stats are worked out again when
; it is withdrawn.

; Bill's DUPLICATE. IN: de = the party mon copied.
BoxCopyOfPartyMon::
	ld hl, MON_LEVEL
	add hl, de
	ld a, [hl]
	push af
	ld h, d
	ld l, e
	ld de, wBoxMon1
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	pop af
	ld [wBoxMon1BoxLevel], a
	ret

; The Facility PokeManiac's prize, from the copy set aside in wEnemyMon6: healed,
; cured, the player's, and never a fusion, as FacManiacPrize makes the party one.
; A mon above the player's level cap stays the fresh one GivePokemon made, and so
; does one that went to the party.
FacManiacBoxPrize::
	ld a, [wAddedToParty]
	and a
	ret nz
	ld a, [wEnemyMon6Level]
	cp MAX_LEVEL + 1
	ret nc
	ld de, wEnemyMon6
	call BoxCopyOfPartyMon
	ld hl, wEnemyMon6MaxHP
	ld a, [hli]
	ld [wBoxMon1HP], a
	ld a, [hl]
	ld [wBoxMon1HP + 1], a
	xor a
	ld [wBoxMon1Status], a
	ld hl, wBoxMon1CatchRate
	res BIT_FUSION, [hl]
	ld hl, wPlayerID
	ld a, [hli]
	ld [wBoxMon1OTID], a
	ld a, [hl]
	ld [wBoxMon1OTID + 1], a
	ret
