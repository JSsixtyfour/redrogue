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
jr z, .done                 ; if 0, you have found a suitable pokemon
jp hl                       ; if 1, you have selected an already existing team member and need to redo
ld a, d                     ; place pokemon in a
Call EnemyMonEvolve

.done
RET

; Roll ~10% chance of one reward slot becoming a trade offer.
; If triggered: picks a random party mon, looks up its class, bumps one tier,
; rolls an offered species at that tier, picks a slot (1-3), and pre-fills
; wRoguePokemonN for that slot.  Always sets wRogueTradeSlot (0=no trade).
; Call AFTER clearing wRoguePokemon1-3 to 0.
RogueRewardTradeRoll::
    xor a
    ld [wroguenpctradegive], a      ; 0 = no trade (cleared first; set on success)
    ; ~10.2% chance (26/255)
    call Random
    cp 26
    ret nc              ; no trade
    ; require at least 2 party members (can't trade away last mon)
    ld a, [wPartyCount]
    cp 2
    ret c               ; fewer than 2 members, skip
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