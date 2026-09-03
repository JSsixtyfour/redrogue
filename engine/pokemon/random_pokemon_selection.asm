; This code is meant to handle any time a pokemon is selected at random, be it starters or for regular prizes
; The code outputs a pokemon ID into a
; masterball class check will be here, will require separate events to occur before active
; auto class by putting a number in c
; ---------------------------------------------------------------------------
; Random_Pokemon_Selection_Far / Random_Pokemon_Selection_Any_Far
;
; The farcall-safe faces of the two rollers. Use these from ANY other bank.
;
; INPUT:  e = rarity class (0 = roll from the odds ladder, 1=pokeball ..
;             4=masterball); wCurEnemyLevel set by the caller
; OUTPUT: d = species
;
; Bankswitch (home/bankswitch.asm) does `ld bc, .Return` before `jp hl` on the
; way in and `pop bc` on the way out, so a/b/c/h/l are all destroyed on BOTH
; sides of a farcall - only d, e and flags cross intact. Every cross-bank caller
; used to pass the class in c and farcall the plain entry point, which meant the
; class never arrived and every one of those rolls silently fell through to the
; odds ladder: procedural boss rarity bumps and the lobby salesman odds had no
; effect at all. Same-bank callers may still use c and the plain entry points.
; ---------------------------------------------------------------------------
Random_Pokemon_Selection_Far::
	ld c, e
	jp Random_Pokemon_Selection

Random_Pokemon_Selection_Any_Far::
	ld c, e
	jp Random_Pokemon_Selection_Any

Random_Pokemon_Selection::
; ELEMENT PRISM encounter bias: set this selection's type-mismatch re-roll
; budget (custom_functions/element_prism.asm). Preserves every register - c
; holds the class argument the very next instructions test.
; Random_Pokemon_Selection_Any deliberately does NOT get this: it backs
; procedural-cave wild encounters, which are not the reward/starter rolls the
; prism is meant to bias.
call RoguePrismSetRerollBudget
; A non-zero c names a rarity class directly (1=pokeball .. 4=masterball).
; Class ids are 1-based and tier ids 0-based, hence the dec.
ld a, c
and a
jr z, .rollClass
cp NUM_SELECTABLE_CLASSES + 1
jr nc, .rollClass             ; out of range - roll the class instead
dec a
ld b, a
jp RogueSelectFromTier

.rollClass
ldh a, [hRandomAdd]
ld b, a

.determineClassSlot
; Apply witch challenge/prize rarity modifiers to the class roll. Two
; INDEPENDENT effects, both able to apply on the same roll (2026-09-02: they
; used to be mutually exclusive by code structure - if prize a was active,
; challenge 4 was skipped even when both were live at once. Fixed to match the
; additive-stacking shape every other rarity source here already uses - see
; the mini-boss/RARE SCOPE stack below).
;
; CHALLENGE_REDUCED_RARITY (4): zone-scoped, only while BIT_WITCH_ACCEPTED.
ld a, [wRogueFlagsBitfield]
bit BIT_WITCH_ACCEPTED, a
jr z, .noChallengeMod
ld a, [wWitchChallenge]
cp CHALLENGE_REDUCED_RARITY
jr nz, .noChallengeMod
; Push roll toward pokeball (SUBTRACT from b → smaller b = more likely pokeball)
ld a, b
sub 64         ; smaller b = more likely pokeball class (worse)
jr nc, .challengeModDone
xor a          ; clamp at 0
.challengeModDone
ld b, a
.noChallengeMod
; PRIZE_RARITY_POKEMON (a): PERMANENT (2026-09-02) - does NOT gate on
; BIT_WITCH_ACCEPTED. Once earned, applies to every roll for the rest of the
; run, stacking with mini-boss/RARE SCOPE exactly like they stack with each
; other below.
ld a, [wWitchPrizesEarned]
and 1 << (PRIZE_RARITY_POKEMON - 1)
jr z, .noRarityMod
; Push roll toward ultraball/masterball (ADD to b → larger b = more likely ultraball)
ld a, b
add 51         ; +51 shifts distribution toward ultraball/masterball. Against this file's
               ; pokeball_odds=127 threshold that still leaves ~30% pokeball chance, NOT
               ; the ~0.4% an earlier version of this comment claimed - that figure was for
               ; item_pokeball_odds=51 (engine/items/random_item_selection.asm), a
               ; different, much lower threshold. See KEY_ITEM_EFFECTS_PLAN_PC.md §3c,
               ; found while calibrating RARE SCOPE/RARE LENS against these two odds tables.
jr nc, .rarityBonusDone
ld a, $FF      ; clamp at 255
.rarityBonusDone
ld b, a
.noRarityMod
; Mini-boss framework: stacks an ADDITIONAL rarity bonus on top of whatever the
; witch logic above contributed (both can be active at once - see
; MINIBOSS_FRAMEWORK.md "rarity stacks additively").
ld a, [wRogueFlagsBitfield]
bit BIT_MINIBOSS_ACTIVE, a
jr z, .noMiniBossMod
ld a, b
add MINIBOSS_POKEMON_RARITY_BONUS
jr nc, .miniBossModDone
ld a, $FF
.miniBossModDone
ld b, a
.noMiniBossMod
; RARE SCOPE: additional bonus stacked on top of any witch/mini-boss bonus
; above (same additive-stacking shape - see KEY_ITEM_EFFECTS_PLAN_PC.md for
; why the bonus is a fraction of pokeball_odds rather than a flat number).
; GetKeyItemPower clobbers bc, so b (the roll accumulator) is saved across
; it. This file and key_item_pocket.asm are both in SECTION "rogue", so a
; plain call reaches it, no farcall needed.
push bc
ld a, RARE_SCOPE
ld [wCurItem], a
call GetKeyItemPower           ; a = 0 (not active) or 1-3 (displayed tier)
pop bc
and a
jr z, .noRareScope
dec a
ld hl, .RareScopeBonusTable
ld e, a
ld d, 0
add hl, de
ld a, [hl]
add b
jr nc, .rareScopeDone
ld a, $FF
.rareScopeDone
ld b, a
.noRareScope
ld a, pokeball_odds
cp b
jr nc, .tierPokeball
ld a, greatball_odds
cp b
jr nc, .tierGreatball
ld b, RARITY_TIER_ULTRABALL     ; ultraball is the fall-through, by design
jp RogueSelectFromTier
.tierPokeball
ld b, RARITY_TIER_POKEBALL
jp RogueSelectFromTier
.tierGreatball
ld b, RARITY_TIER_GREATBALL
jp RogueSelectFromTier

.RareScopeBonusTable:
	db 31, 63, 95

; ---------------------------------------------------------------------------
; RogueSelectFromTier
; INPUT:  b = tier id; wCurEnemyLevel already set by the caller
; OUTPUT: d = species, post-evolution; also left in wCurPartySpecies
;
; Rolls which active species group supplies this tier, rolls a base form from
; that group, then applies the two rejection tests before evolving.
;
; The retry loop is BOUNDED. The code this replaces pushed its own address as a
; fake return target and jumped back to it forever, so a player who already
; owned every base form in a tier would hang the game rather than get a
; duplicate. Falling back to the last roll is strictly better than not returning.
; ---------------------------------------------------------------------------
RogueSelectFromTier::
	ld c, 32                      ; retry budget
.attempt
	push bc                       ; b = tier, c = budget
	call RogueRollGroupForTier    ; a = group; b preserved
	jr c, .noPool
	call RogueGetTierEntry        ; hl = list, b = base count, c = total
	jr z, .noPool
	ld a, b
	call RogueRollSpeciesInList   ; d = species
	call AllSpeciesCheck          ; c = 1 if already in the party or a box
	ld a, c
	and a
	jr nz, .reject
	; ELEMENT PRISM encounter bias: discard an off-type species and re-roll.
	; Deliberately before the evolve step, exactly as the old code ordered it.
	call RoguePrismShouldRerollSpecies ; NZ = off-type and budget remains; preserves d
	jr nz, .reject
	pop bc
	jr .evolve
.reject
	pop bc                        ; b = tier, c = budget
	dec c
	jr nz, .attempt
	jr .evolve                    ; budget spent - accept the last roll
.noPool
	pop bc
	; No active group offers anything at this tier. Fall back to the Kanto
	; pokeball list so a caller always gets a real species rather than a stale d.
	ld a, SPECIES_GROUP_KANTO
	ld b, RARITY_TIER_POKEBALL
	call RogueGetTierEntry
	ld a, b
	call RogueRollSpeciesInList
.evolve
	ld a, d
	ld [wCurPartySpecies], a      ; EvolveMonByLevel reads d, writes back here
	call EvolveMonByLevel
	ld a, [wCurPartySpecies]
	ld d, a                       ; d = possibly-evolved species
	ret

; Like Random_Pokemon_Selection but skips AllSpeciesCheck entirely - the
; rolled species may already be in the player's party or box.  Used for
; procedural-cave wild encounters (player CAN fight mons they own; only the
; boss needs the uniqueness guarantee).
; c = class (0=random, 1=pokeball, 2=greatball, 3=ultraball, 4=masterball)
; wCurEnemyLevel must be set by the caller (EvolveMonByLevel reads it).
; → d = species
Random_Pokemon_Selection_Any::
	ld a, c
	and a
	jr z, .rollClass
	cp NUM_SELECTABLE_CLASSES + 1
	jr nc, .rollClass             ; out of range - roll the class instead
	dec a                         ; class 1-4 -> tier 0-3
	ld b, a
	jr .pick
.rollClass
	ldh a, [hRandomAdd]
	ld b, a
	ld a, pokeball_odds
	cp b
	jr nc, .tierPokeball
	ld a, greatball_odds
	cp b
	jr nc, .tierGreatball
	ld b, RARITY_TIER_ULTRABALL   ; ultraball is the fall-through, by design
	jr .pick
.tierPokeball
	ld b, RARITY_TIER_POKEBALL
	jr .pick
.tierGreatball
	ld b, RARITY_TIER_GREATBALL
.pick
	call RogueRollGroupForTier    ; a = group; b (tier) preserved
	jr c, .fallback
	call RogueGetTierEntry        ; hl = list, b = base count, c = total
	jr z, .fallback
	ld a, b
	call RogueRollSpeciesInList   ; d = species
	jr .evolve
.fallback
	; No active group offers anything at this tier. Fall back to the Kanto
	; pokeball list so a caller always gets a real species rather than a stale d.
	ld a, SPECIES_GROUP_KANTO
	ld b, RARITY_TIER_POKEBALL
	call RogueGetTierEntry
	ld a, b
	call RogueRollSpeciesInList
.evolve
	ld a, d
	ld [wCurPartySpecies], a
	call EvolveMonByLevel
	ld a, [wCurPartySpecies]
	ld d, a
	ret

; Roll ~10% chance of one reward slot becoming a trade offer.
; If triggered: picks a random party mon, looks up its class, bumps one tier,
; rolls an offered species at that tier, picks a slot (1-3), and pre-fills
; wRoguePokemonN for that slot.  Always sets wRogueTradeSlot (0=no trade).
; Call AFTER clearing wRoguePokemon1-3 to 0.
RogueRewardTradeRoll::
    xor a
    ld [wroguenpctradegive], a      ; 0 = no trade (cleared first; set on success)
    ; ~10.2% chance (26/255); bypassed entirely when BIT_DEBUG2_MODE is set
    ld a, [wStatusFlags6]
    bit BIT_DEBUG2_MODE, a
    jr nz, .skipTradeRoll   ; debug: always attempt a trade
    call Random
    cp 26
    ret nc              ; no trade
.skipTradeRoll
    ; require at least 3 party members (so trading one away never leaves
    ; the player down to a single mon)
    ld a, [wPartyCount]
    cp 3
    ret c               ; fewer than 3 members, skip
    ; e = partyCount, d = retry counter (8 attempts; rejection sampling needs more headroom)
    ld e, a
    ld d, 8
.tryPickMember
    ld c, e
    call Rangerandom    ; a = 0..partyCount-1
    ld c, a                         ; c = party index for species lookup
    ld b, 0
    ld hl, wPartySpecies
    add hl, bc
    ld a, [hl]
    ld [wroguenpctradegive], a      ; species player gives up (non-zero = trade active)
    ; classify the species (still in a) into a rarity class 1-4.
    ; d = retry counter and e = partyCount are both live here, and
    ; RogueClassifySpecies uses de as its scan cursors, so save them.
    push de
    call RogueClassifySpeciesLegacy ; c = class 1-4, carry set if not in any pool
    pop de                          ; pop does not touch flags, so carry survives
    ld b, c
    jr nc, .gotClass
    ld b, 1                         ; unknown species - treat as pokeball class
.gotClass
    ; masterball always excluded (no higher tier to offer)
    ld a, b
    cp 4
    jr z, .retry
    ; rejection sampling: pick threshold 1-3; accept if class >= threshold
    ; class-3 (ultraball): always accepted; class-2: 2/3; class-1 (pokeball): 1/3
    push bc             ; save b=class across Rangerandom
    ld c, 3
    call Rangerandom    ; a = 0..2
    pop bc              ; restore b=class
    cp b                ; C set if roll < class
    jr c, .doTrade      ; accept
.retry
    dec d
    jr nz, .tryPickMember
    ret                 ; all retries exhausted, no trade
.doTrade
    ; b = class (1-3), offer one tier higher; trade always pre-fills slot 1
    ld hl, wRogueFlagsBitfield
    set BIT_ROGUE_TRADE_ACTIVE, [hl]
    xor a
    ld [wroguenpctradedialogue], a  ; use TRADE_DIALOGSET_CASUAL (0) for text lookup
    push bc
    farcall GetRewardMonLevel       ; wCurEnemyLevel must be set before species pick for evolution check
    pop bc
    inc b
    ld c, b
    call Random_Pokemon_Selection   ; offered species -> d
    ld a, d
    ld [wRoguePokemon1], a
    ld [wroguenpctradeget], a
    ld [wNamedObjectIndex], a
    call GetMonName                 ; offered mon's name → wNameBuffer
    ld hl, wNameBuffer
    ld de, wroguenpctradename
    ld bc, NAME_LENGTH
    jp CopyData                     ; wroguenpctradename = offered mon's name; tail call

rogue_pokemon_randomized_batch::
   ; clear trade-active bit so stale wram never shows a phantom trade offer
   ld hl, wRogueFlagsBitfield
   res BIT_ROGUE_TRADE_ACTIVE, [hl]
   ; reset TRADE_FOR_RANDOM flag so trade offer is always available on stage entry
   ld c, TRADE_FOR_RANDOM
   ld b, FLAG_RESET
   ld hl, wCompletedInGameTradeFlags
   predef FlagActionPredef
   ld hl, wRoguePokemon1
   xor a
   ld [hli], a          ; clear out prior pokemon
   ld [hli], a          ; clear out prior pokemon
   ld [hl], a           ; clear out prior pokemon

   call RogueRewardTradeRoll   ; may pre-fill wRoguePokemon1; wroguenpctradeget=0 if no trade

   ; slot 1 (skip if pre-filled by trade roll)
   ld a, [wRoguePokemon1]
   and a
   jr nz, .roguepokemon2
   .rollpokemon1
   farcall GetRewardMonLevel  ; wCurEnemyLevel must be set before species pick for evolution check
   call Random
   call Random_Pokemon_Selection
   ld hl, wRoguePokemon1
   ld [hl], d

   .roguepokemon2
   ; slot 2 (skip if pre-filled by trade roll)
   ld a, [wRoguePokemon2]
   and a
   jr nz, .roguepokemon3
   .rollpokemon2
   farcall GetRewardMonLevel
   call Random
   call Random_Pokemon_Selection
   ld a, [wRoguePokemon1]
   cp d
   jr z, .rollpokemon2
   ld hl, wRoguePokemon2
   ld [hl], d

   .roguepokemon3
   ; slot 3 (skip if pre-filled by trade roll)
   ld a, [wRoguePokemon3]
   and a
   jr nz, .doneBatch
   .rollpokemon3
   farcall GetRewardMonLevel
   call Random
   call Random_Pokemon_Selection
   ld a, [wRoguePokemon1]
   cp d
   jr z, .rollpokemon3
   ld a, [wRoguePokemon2]
   cp d
   jr z, .rollpokemon3
   ld hl, wRoguePokemon3
   ld [hl], d

   .doneBatch
RET

; a check to see if pokemon is already in players box or party
; returns a 0 if no and a 1 if yes

; UPDATE, need a way to check if evolution
AllSpeciesCheck::
    ld b, 0
    ld c, 0
    ld hl, wPartySpecies
    push hl
    
    .loop
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .box
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop
    
    .box ;
    pop hl
    ld hl, wBoxSpecies
    push hl
    
    .loop2
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .begin_checking
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop2
    
    .begin_checking
    pop hl
    ld hl, wAllSpecies
    
    .checkloop
    ld a, [hli]         ; load pokemon
    cp d                ; compare to selected random pokemon
    jr z, .rejection    ; if the same pokemon flag for rejection
    cp $ff              
    jr nz, .checkloop   ; if not end of list, loop
    
    ld c, $0               ; set c to 0 as the pokemon isn't on players team
    jp  .end
    
    .rejection
    ld c, $1            ; set c to 1 as the pokemon is already on players team
    
    .end
    RET

; Choose Blue's starter from the two slots the player did NOT take.
; in:  e = player's chosen slot (1..3)   [passed via 'e' because farcall/Bankswitch
;         clobbers a/bc/hl but preserves d/e]
; out: wRivalStarter              = Blue's chosen species
;      wRivalStarterBallSpriteIndex = ROGUE_STARTER_POKEBALL_1/2/3 (1-based object const) of that slot
; Priority: higher rarity class > type advantage over the player's starter > random.
RivalPickStarter::
	; player ball index p = e - 1
	ld a, e
	dec a
	push af                       ; save p
	; defender types = the player's starter's types (into wBattleMonType/+1)
	call .speciesFromIndex        ; a(=p) -> a = player's species
	ld [wCurSpecies], a
	call GetMonHeader
	ld a, [wMonHType1]
	ld [wBattleMonType], a
	ld a, [wMonHType2]
	ld [wBattleMonType + 1], a
	pop af                        ; a = p
	; candidate ball indices: candA in d, candB in e
	ld d, 0
	or a
	jr nz, .candA
	ld d, 1                       ; p==0 -> candA=1
.candA
	ld e, 2
	cp 2
	jr nz, .candB
	ld e, 1                       ; p==2 -> candB=1
.candB
	; tierA (from candA)
	ld a, d
	call .speciesFromIndex        ; a = speciesA
	ld b, a
	call .classOfSpecies          ; b = tierA
	push bc                       ; save tierA
	; tierB (from candB)
	ld a, e
	call .speciesFromIndex        ; a = speciesB
	ld b, a
	call .classOfSpecies          ; b = tierB
	pop af                        ; a = tierA (high byte of saved bc)
	cp b
	jr z, .tie
	jr c, .chooseB                ; tierA < tierB
.chooseA                          ; tierA > tierB
	ld a, d
	jr .commit
.chooseB
	ld a, e
	jr .commit
.tie
	; equal rarity: prefer the candidate whose STAB is super-effective vs the player
	push de                       ; save candA(d)/candB(e)
	ld a, d
	call .speciesFromIndex
	ld b, a
	call .candidateHasAdvantage   ; a = 1 if candA super-effective vs player
	ld c, a                       ; c = advA
	pop de
	push de
	ld a, e
	call .speciesFromIndex
	ld b, a
	push bc                       ; save advA (in c)
	call .candidateHasAdvantage   ; a = advB
	pop bc                        ; c = advA
	ld b, a                       ; b = advB
	ld a, c
	and a
	jr z, .aNotAdv
	; advA set
	ld a, b
	and a
	jr nz, .tieRandom             ; both advantaged -> random
	pop de
	ld a, d                       ; only A advantaged
	jr .commit
.aNotAdv
	ld a, b
	and a
	jr z, .tieRandom              ; neither advantaged -> random
	pop de
	ld a, e                       ; only B advantaged
	jr .commit
.tieRandom
	pop de                        ; d=candA, e=candB
	call Random
	and 1
	jr z, .commitD
	ld a, e
	jr .commit
.commitD
	ld a, d
.commit
	; a = chosen 0-based ball index (0..2)
	push af
	call .speciesFromIndex        ; a = chosen species
	ld [wRivalStarter], a         ; stable WRAM - see the union note in wram.asm
	pop af
	inc a                         ; -> ROGUE_STARTER_POKEBALL_1/2/3 (object const, 1-based)
	ld [wRivalStarterBallSpriteIndex], a
	ret

; a = ball index (0..2) -> a = wRoguePokemon(index+1). Preserves bc/de.
.speciesFromIndex
	push de
	ld hl, wRoguePokemon1
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	pop de
	ret

; b = species -> b = rarity class (1..4). Preserves de.
.classOfSpecies
	push de                       ; RogueClassifySpecies uses de as its scan cursors
	ld a, b
	call RogueClassifySpeciesLegacy ; c = class 1-4, carry set if not in any pool
	pop de                        ; pop does not touch flags, so carry survives
	ld b, c
	ret nc
	ld b, 1                       ; unknown species - treat as pokeball class
	ret

; b = candidate species; defender (player) types already in wBattleMonType/+1.
; -> a = 1 if a candidate STAB type is super-effective vs the player, else 0.
.candidateHasAdvantage
	ld a, b
	ld [wCurSpecies], a
	call GetMonHeader             ; wMonHType1/2 = candidate's types
	ld a, [wMonHType1]
	ld [wEnemyMoveType], a
	callfar AIGetTypeEffectiveness
	ld a, [wTypeEffectiveness]
	cp SUPER_EFFECTIVE
	jr z, .adv
	ld a, [wMonHType2]
	ld [wEnemyMoveType], a
	callfar AIGetTypeEffectiveness
	ld a, [wTypeEffectiveness]
	cp SUPER_EFFECTIVE
	jr z, .adv
	xor a
	ret
.adv
	ld a, 1
	ret
