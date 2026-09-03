; custom_functions/witch_setup.asm
;
; The Lobby Witch's per-visit roll, relocated out of scripts/IndigoPlateauLobby.asm
; on 2026-09-02. That script lives in the "Maps 2" section (bank $06), which was
; down to 79 free bytes in the debug build - not enough to absorb the new
; challenge/prize text-table entries this feature adds, let alone the finale
; gating. The roll itself has no "Maps 2" dependencies at all (Rangerandom is
; HOME, ShowObject/HideObject go through predef), so it moved cleanly into the
; "rogue" section (bank $2F) alongside the witch's battle effects.
;
; Its one cross-bank call, HasMasterballClassMon in legendary_boss_helpers.asm,
; became a plain `call` in the process - that routine was already in bank $2F,
; so the farcall it needed from bank $06 is no longer necessary.
;
; PCWitchSetup is exported (::) because its only caller, IndigoPlateauLobby_Script,
; assembles into a different object file (maps.asm) and reaches it by farcall.

; Rolls whether the witch appears this lobby visit (~1/3 chance). If she
; appears, rolls her challenge and prize independently. BIT_WITCH_ACCEPTED
; stays clear until the player actually accepts in PCWitchText. Effects of
; the challenge/prize are not applied here - just the roll and bookkeeping.
; Rolls whether a lobby NPC appears this lobby visit (~1/3 chance) and shows
; or hides its toggleable object accordingly. Shared by every lobby resident
; that should get an independent appear-or-not roll - currently only the
; witch uses it; trader/salesman/clerks still always appear.
; Input:  a = toggle index of the NPC's toggleable object
; Output: Z set (and a = 0) if the NPC appears this visit, NZ (a = 1) if hidden
RollLobbyNPCAppearance:
    ld [wToggleableObjectIndex], a
    ld c, 3
    call Rangerandom         ; a = 0..2
    and a
    jr nz, .hide              ; nonzero = stays hidden this visit (2/3 chance)
    predef ShowObject
    xor a
    ret
.hide
    predef HideObject
    ld a, 1
    ret

; Rolls whether the witch appears, and if so, her challenge and prize as two
; independent factors (no fixed challenge->prize pairing - either can be any
; tier). Effects of the challenge/prize are applied elsewhere (Phase 2 hooks),
; not here - this is just the roll and bookkeeping.
PCWitchSetup::
    ld hl, wRogueFlagsBitfield
    res BIT_WITCH_ACCEPTED, [hl]

    ; --- Finale gating ---
    ; Once all 8 badges are in, the run is on rails and the witch needs two
    ; special cases:
    ;   Victory Road next (not yet cleared) -> she still appears, but the roll
    ;                                          must behave like a ROUTE, not a gym
    ;   Elite Four next   (already cleared) -> no witch at all for the rest of
    ;                                          the run
    ; A "finale route mode" register would have to survive Rangerandom, so the
    ; gates further down just re-derive `wObtainedBadges == $FF` instead. It is
    ; four bytes each time and needs no state.
    ld a, [wObtainedBadges]
    cp $FF
    jr nz, .showWitch
    CheckEvent EVENT_VICTORY_ROAD_CLEARED
    jp nz, .hideWitch         ; jp, not jr: .hideWitch is at the far end of the routine
.showWitch
    ; TESTING: appearance roll disabled, witch is always active
;   ld a, TOGGLE_PC_WITCH
;   call RollLobbyNPCAppearance
;   jr nz, .hideWitch
    ld a, TOGGLE_PC_WITCH
    ld [wToggleableObjectIndex], a
    predef ShowObject
    ; Debug 2: force the Legendary Boss challenge, skipping the roll and the
    ; map/badge/masterball gates. Re-applied every lobby entry so the normal
    ; reroll never clobbers it. wWitchPrize=0 is the underflow-safe sentinel
    ; that PCWitchText special-cases for CHALLENGE_LEGENDARY_BOSS.
    ld a, [wStatusFlags6]
    bit BIT_DEBUG2_MODE, a
    jr z, .rollChallenge
    ; ...but NEVER during the finale. Challenge 11 pays out through four gym
    ; leaders' receive-TM routines, and no gym is fought from Victory Road on,
    ; so a forced Challenge 11 in the pre-Victory-Road lobby can never be
    ; completed. This early return skipped every gate, including the eligible-
    ; map check, which is exactly why the witch offered Challenge 11 by name in
    ; that lobby. Note this block is NOT wrapped in IF DEF(_DEBUG) - it fires on
    ; any build once BIT_DEBUG2_MODE is set.
    ld a, [wObtainedBadges]
    cp $FF
    jr z, .rollChallenge
    ld a, CHALLENGE_LEGENDARY_BOSS
    ld [wWitchChallenge], a
    xor a
    ld [wWitchPrize], a
    ret
.rollChallenge
    ld c, NUM_WITCH_CHALLENGES
    call Rangerandom          ; a = 0..NUM_WITCH_CHALLENGES-1
    inc a
    ; Gate Gambler's Paradise to later rounds: its themed teams are fully
    ; evolved with high-level movesets, so reroll if the run is still early.
    cp CHALLENGE_GAMBLERS_PARADISE
    jr nz, .notEarlyGamblerGate
    ld b, a                   ; stash challenge id across both checks below
    ld a, [wBattleCount]
    cp GAMBLERS_PARADISE_MIN_BATTLES
    jr c, .rollChallenge      ; wBattleCount < threshold - reroll
    ; Never during the finale: accepting it calls PatchLobbyExitToGameCorner,
    ; which overwrites wRogueMap AND both lobby door warps with GAME_CORNER.
    ; In the pre-Victory-Road lobby that strands the run short of Victory Road.
    ld a, [wObtainedBadges]
    cp $FF
    jr z, .rollChallenge
    ld a, b                   ; restore the rolled challenge id
.notEarlyGamblerGate
    ; Gate Challenge 11 (Legendary Boss): only offer if next gym is eligible,
    ; badges >= 4, and party has masterball mon. Then set fixed reward.
    cp CHALLENGE_LEGENDARY_BOSS
    jr nz, .notLegendaryGate
    ; Check 1: wRogueMap ∈ {CELADON_GYM, SAFFRON_GYM, CINNABAR_GYM, VIRIDIAN_GYM}
    ld a, [wRogueMap]
    cp CELADON_GYM
    jr z, .legendaryMapOk
    cp SAFFRON_GYM
    jr z, .legendaryMapOk
    cp CINNABAR_GYM
    jr z, .legendaryMapOk
    cp VIRIDIAN_GYM
    jr z, .legendaryMapOk
    jp .rollChallenge      ; Map not eligible - reroll
.legendaryMapOk
    ; Check 2: badge count >= 4 using popcount
    ld a, [wObtainedBadges]
    ld b, 0             ; b = badge count
    ld d, a             ; d = badges copy for popcount
    ld e, 8             ; e = loop counter (8 badges)
.legendaryBadgeCnt
    bit 0, d
    jr z, .legendaryBadgeCntSkip
    inc b
.legendaryBadgeCntSkip
    srl d
    dec e
    jr nz, .legendaryBadgeCnt
    ld a, b
    cp 4
    jp c, .rollChallenge  ; < 4 badges - reroll
    ; Check 3: party has masterball mon
    call HasMasterballClassMon    ; same bank ($2F) now that this routine moved here
    jp nc, .rollChallenge  ; no masterball mon - reroll
    ; All checks passed! Set fixed reward marker (0 = no random roll).
    ld a, CHALLENGE_LEGENDARY_BOSS
    ld [wWitchChallenge], a
    xor a
    ld [wWitchPrize], a
    ret
.notLegendaryGate
    ; CHALLENGE_NO_REWARD_POKEMON and CHALLENGE_NO_RANDOM_ITEM both suppress
    ; the reward menu, which never runs before a gym (gyms are fixed vanilla
    ; maps, not a randomized stage) - reroll so a gym visit never offers a
    ; challenge with no real downside
    ;
    ; The finale is route-mode regardless of BIT_ROGUE_GYM_NEXT: Victory Road is
    ; a real stage WITH a reward menu, so those challenges are meaningful there,
    ; and the flag can be left set from an earlier cycle (VictoryRoad1F_Script
    ; sets it on entry). Skip the gym rerolls entirely once badges are full.
    ld b, a                   ; stash challenge id; ld a,b below preserves flags
    ld a, [wObtainedBadges]
    cp $FF
    ld a, b                   ; restore it (does not disturb Z from the cp)
    jr z, .gotChallenge
    ld hl, wRogueFlagsBitfield
    bit BIT_ROGUE_GYM_NEXT, [hl]
    jr z, .gotChallenge
    cp CHALLENGE_NO_REWARD_POKEMON
    jr z, .rollChallenge
    cp CHALLENGE_NO_RANDOM_ITEM
    jr z, .rollChallenge
    cp CHALLENGE_GAMBLERS_PARADISE
    jr z, .rollChallenge   ; Game Corner replaces a route, not a gym
.gotChallenge
    ld [wWitchChallenge], a   ; a = 1-based challenge id
    ld c, NUM_WITCH_PRIZES
    call Rangerandom          ; a = 0..NUM_WITCH_PRIZES-1
    inc a
    ld [wWitchPrize], a       ; a = 1-based prize id - independent of the challenge roll
    ret
; Elite Four next: take the witch off the board for the rest of the run. The
; object must be explicitly hidden - the toggle state resets on every warp, and
; the .showWitch path above would otherwise leave her standing there with a
; zeroed challenge.
.hideWitch
    ld a, TOGGLE_PC_WITCH
    ld [wToggleableObjectIndex], a
    predef HideObject
    ; fall through
.noWitch
    xor a
    ld [wWitchChallenge], a
    ld [wWitchPrize], a
    ret
