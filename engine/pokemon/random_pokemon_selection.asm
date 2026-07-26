; This code is meant to handle any time a pokemon is selected at random, be it starters or for regular prizes
; The code outputs a pokemon ID into a
; masterball class check will be here, will require separate events to occur before active
; auto class by putting a number in c
Random_Pokemon_Selection::
; set class check
ld a, 0x1
cp c
jp z, pokeball_class_selection

ld a, 0x2
cp c
jp z, greatball_class_selection

ld a, 0x3
cp c
jp z, ultraball_class_selection

ld a, 0x4
cp c
jp z, masterball_class_selection

ldh a, [hRandomAdd]
ld b, a

.determineClassSlot
; Apply witch prize/challenge rarity modifier to the class roll.
; PRIZE_RARITY_POKEMON (a): wRewardClassBonus > 0 → subtract from b (lower b = better class).
; CHALLENGE_REDUCED_RARITY (4): wRewardClassBonus < 0 (stored as two's complement) → adds, pushing toward pokeball.
; Using addition only: if wRewardClassBonus is set as a signed byte, ld a,b / add [wRewardClassBonus] handles both.
ld a, [wRogueFlagsBitfield]
bit BIT_WITCH_ACCEPTED, a
jr z, .noRarityMod
ld a, [wWitchPrize]
cp PRIZE_RARITY_POKEMON
jr z, .rarityBonus
ld a, [wWitchChallenge]
cp CHALLENGE_REDUCED_RARITY
jr nz, .noRarityMod
; Challenge 4: push roll toward pokeball (SUBTRACT from b → smaller b = more likely pokeball)
ld a, b
sub 64         ; smaller b = more likely pokeball class (worse)
jr nc, .rarityMod
xor a          ; clamp at 0
.rarityMod
ld b, a
jr .noRarityMod
.rarityBonus
; Prize a: push roll toward ultraball/masterball (ADD to b → larger b = more likely ultraball)
ld a, b
add 51         ; +51 shifts distribution: pokeball only on roll=0 (~0.4%), mostly ultraball
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
ld a, pokeball_odds
cp b
jr nc, pokeball_class_selection
ld a, greatball_odds
cp b
jr nc, greatball_class_selection
jp ultraball_class_selection


pokeball_class_selection:
ld hl, pokeball_class_selection
push hl
ld hl, pokeball_class
push hl
ld a, pokeball_pokemon_line_amount
push af
jp pokemon_selection

greatball_class_selection:
ld hl, greatball_class_selection
push hl
ld hl, greatball_class
push hl
ld a, greatball_pokemon_line_amount
push af
jp pokemon_selection

ultraball_class_selection:
ld hl, ultraball_class_selection
push hl
ld hl, ultraball_class
push hl
ld a, ultraball_pokemon_line_amount
push af
jp pokemon_selection

masterball_class_selection:
ld hl, masterball_class_selection
push hl
ld hl, masterball_class
push hl
ld a, masterball_pokemon_line_amount
push af
jp pokemon_selection

pokemon_selection:
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
pop af                      ; restore line amount to multiply by amount in class
;dec a                       ; max index is line_amount-1; prevents out-of-bounds on random=255
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh   a, [hProduct+2]       ; load product into a
ldh [hDividend], a          ; place product in divident
ldh   a, [hProduct+3]
ldh [hDividend+1], a

ld a, $FF                   ; load 255
ld b, $2                    ; b determines how many bytes the number is, do not remove!
ldh [hDivisor], a           ; place 255 as divisor
call Divide
ldh   a, [hQuotient+3]      ; load in quotient, which will be the offset
ld c, a                     ; place in c
ld b, $0


pop hl                      ; restore base pointer
add hl, bc                  ; add product to get address of pokemon

                      
ld d, [hl]                  ; load selected pokemon
call AllSpeciesCheck        ; check if pokemon already in box or party
xor a                       ; clear out a
pop hl                      ; reload selection class
cp c
jr nz, .retry                ; if 1, you have selected an already existing team member and need to redo
; evolve based on wCurEnemyLevel (caller must set it before calling Random_Pokemon_Selection)
ld a, d
ld [wCurPartySpecies], a    ; EvolveMonByLevel reads d for lookup, writes evolved species here if applicable
call EvolveMonByLevel
ld a, [wCurPartySpecies]
ld d, a                     ; d = possibly-evolved species, matches existing caller convention
jr .done
.retry
jp hl

.done
RET

; Like Random_Pokemon_Selection but skips AllSpeciesCheck entirely - the
; rolled species may already be in the player's party or box.  Used for
; procedural-cave wild encounters (player CAN fight mons they own; only the
; boss needs the uniqueness guarantee).
; c = class (0=random, 1=pokeball, 2=greatball, 3=ultraball, 4=masterball)
; wCurEnemyLevel must be set by the caller (EvolveMonByLevel reads it).
; → d = species
Random_Pokemon_Selection_Any::
	ld a, 1
	cp c
	jp z, .any_pokeball
	ld a, 2
	cp c
	jp z, .any_greatball
	ld a, 3
	cp c
	jp z, .any_ultraball
	ld a, 4
	cp c
	jp z, .any_masterball
	; c == 0: random class from odds table
	ldh a, [hRandomAdd]
	ld b, a
	ld a, pokeball_odds
	cp b
	jr nc, .any_pokeball
	ld a, greatball_odds
	cp b
	jr nc, .any_greatball
	jp .any_ultraball
.any_pokeball
	ld hl, pokeball_class
	ld a, pokeball_pokemon_line_amount
	jr .any_pick
.any_greatball
	ld hl, greatball_class
	ld a, greatball_pokemon_line_amount
	jr .any_pick
.any_ultraball
	ld hl, ultraball_class
	ld a, ultraball_pokemon_line_amount
	jr .any_pick
.any_masterball
	ld hl, masterball_class
	ld a, masterball_pokemon_line_amount
.any_pick
	push hl       ; save class list base
	push af       ; save line_amount (Random overwrites a)
	call Random
	ldh [hMultiplicand+2], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand+1], a
	pop af        ; restore line_amount
	ldh [hMultiplier], a
	call Multiply
	ldh a, [hProduct+2]
	ldh [hDividend], a
	ldh a, [hProduct+3]
	ldh [hDividend+1], a
	ld a, $FF
	ld b, $2
	ldh [hDivisor], a
	call Divide
	ldh a, [hQuotient+3]
	ld c, a
	ld b, 0
	pop hl        ; restore class list base
	add hl, bc
	ld d, [hl]    ; d = selected species (no ownership check)
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
    ; find this species in pokemon_classes to get its tier
    ; b = species, c = 1-based scan position
    ld b, a
    ld hl, pokemon_classes
    ld c, 0
.findClass
    inc c
    ld a, [hli]
    cp b
    jr nz, .findClass
    ; determine class (1-4) into b
    ld a, pokeball_pokemon_number
    ld b, 1
    cp c
    jr nc, .gotClass
    ld a, greatball_pokemon_number
    inc b
    cp c
    jr nc, .gotClass
    inc b
    ld a, ultraball_pokemon_number
    cp c
    jr nc, .gotClass
    inc b               ; masterball
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