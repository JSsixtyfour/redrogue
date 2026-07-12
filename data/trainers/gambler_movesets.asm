; Gambler's Paradise Pokemon Pool + Movesets (Stride 5: species + 4 moves)
;
; Pool = every entry's byte 0 (reusable "knows an OHKO/trap move" list).
; Every move below is verified against this repo's data:
;   - level-up:  data/pokemon/evos_moves.asm  (line cited as e:NNNN)
;   - TM/HM:     data/pokemon/base_stats/<mon>.asm tmhm list (cited as TM)
;   - tutor:     the "Tutoring Learnset" block in evos_moves.asm (cited as tut)
; HORN_DRILL is TM07 and FISSURE is TM27, so both OHKOs are widely TM-learnable.
; CLAMP/WRAP/BIND/FIRE_SPIN/GUILLOTINE are level-up (or tutor) only.
;
; Design rules (from Step 2 audit):
;   - No mon carries BOTH Fissure and Horn Drill (redundant). One OHKO max;
;     a trap may pair with an OHKO (different mechanic = variety, on-theme).
;   - Slow OHKO users carry a paralysis move (BODY_SLAM/THUNDER_WAVE/GLARE)
;     so the AI can flip the Gen 1 "slower = auto-miss" rule before firing.
;   - Fast OHKO users (Dugtrio/Tauros/Rapidash) skip setup, carry a nuke.
;   - Every setup move is backed by a real attack (no naked Swords Dance).
;   - Level timing is IGNORED: movesets are overwritten after WriteMonMoves,
;     so learnset membership at ANY level is the only fairness standard.
;
; No SECTION here: this file is INCLUDEd inside main.asm's "rogue" ROMX section
; so it shares a bank with func_enc_gen.asm, letting GetRandRosterLoop read the
; table via a plain [hl] (no bank switch).

GamblerMonMovesets:
	; --- Fissure OHKO, Ground (slow ones carry a paralysis setup) ---
	db DUGTRIO,   FISSURE,      EARTHQUAKE,   ROCK_SLIDE,   SLASH          ; spd120 fast: FISSURE TM, EQ TM, ROCK_SLIDE TM, SLASH e:2357
	db RHYDON,    FISSURE,      BODY_SLAM,    EARTHQUAKE,   ROCK_SLIDE     ; spd40 slow: FISSURE TM, BODY_SLAM TM(para), EQ e:231, ROCK_SLIDE e:230
	db MAROWAK,   FISSURE,      BODY_SLAM,    EARTHQUAKE,   FIRE_BLAST     ; spd45 slow: all TM
	db GOLEM,     FISSURE,      BODY_SLAM,    EARTHQUAKE,   METRONOME      ; spd45 slow: all TM; METRONOME = gambler chaos

	; --- Horn Drill OHKO, Normal/Poison ---
	db TAUROS,    HORN_DRILL,   BODY_SLAM,    EARTHQUAKE,   FIRE_BLAST     ; spd110 fast: all TM
	db NIDOKING,  HORN_DRILL,   EARTHQUAKE,   THUNDERBOLT,  BODY_SLAM      ; spd85: all TM

	; --- Trap + OHKO combos (max variety, the "signature" gamblers) ---
	db DRAGONITE, HORN_DRILL,   WRAP,         THUNDER_WAVE, BLIZZARD       ; HORN_DRILL TM, WRAP lv1, T-WAVE lv1(para), BLIZZARD TM
	db DRAGONAIR, HORN_DRILL,   WRAP,         THUNDER_WAVE, THUNDERBOLT    ; HORN_DRILL TM, WRAP lv1, T-WAVE lv1(para), TBOLT TM
	db RAPIDASH,  HORN_DRILL,   FIRE_SPIN,    FIRE_BLAST,   BODY_SLAM      ; spd105 fast: HORN_DRILL TM, FIRE_SPIN e:3032, FIRE_BLAST e:3034, BODY_SLAM TM
	db ARBOK,     WRAP,         FISSURE,      GLARE,        EARTHQUAKE     ; WRAP lv1, FISSURE TM, GLARE e:1139(para), EQ TM
	db LICKITUNG, WRAP,         FISSURE,      BODY_SLAM,    THUNDERBOLT    ; spd30 slow: WRAP lv1, FISSURE TM, BODY_SLAM e:463(para), TBOLT TM
	db ONIX,      FISSURE,      BIND,         BODY_SLAM,    EARTHQUAKE     ; FISSURE TM, BIND e:921, BODY_SLAM TM(para), EQ TM
	db PINSIR,    GUILLOTINE,   BIND,         SLASH,        SEISMIC_TOSS   ; GUILLOTINE e:846, BIND e:847, SLASH e:845, SEISMIC_TOSS e:842
	db OMASTAR,   CLAMP,        HORN_DRILL,   HYDRO_PUMP,   SPIKE_CANNON   ; CLAMP e:2005, HORN_DRILL TM, HYDRO_PUMP e:2006, SPIKE_CANNON e:2002

	; --- Trap + nuke (no OHKO; trap-locks then hits hard) ---
	db KINGLER,   GUILLOTINE,   CRABHAMMER,   BODY_SLAM,    BUBBLEBEAM     ; GUILLOTINE e:2639, CRABHAMMER e:2637, BODY_SLAM TM(para), BUBBLEBEAM e:2634
	db CLOYSTER,  CLAMP,        BLIZZARD,     ICE_BEAM,     SPIKE_CANNON   ; CLAMP lv1, BLIZZARD TM, ICE_BEAM TM, SPIKE_CANNON e:2658
	db TENTACRUEL,WRAP,         HYDRO_PUMP,   BUBBLEBEAM,   CONSTRICT      ; WRAP e:2920, HYDRO_PUMP e:2921, BUBBLEBEAM e:2915, CONSTRICT e:2916(spd drop)
	db MOLTRES,   FIRE_SPIN,    FIRE_BLAST,   SKY_ATTACK,   AGILITY        ; FIRE_SPIN e:1594, FIRE_BLAST e:1592, SKY_ATTACK e:1593, AGILITY e:1590
	db NINETALES, FIRE_SPIN,    FIRE_BLAST,   FLAMETHROWER, CONFUSE_RAY    ; FIRE_SPIN e:1718, FIRE_BLAST TM, FLAMETHROWER e:1716, CONFUSE_RAY e:1714
	db ARCANINE,  FIRE_SPIN,    FIRE_BLAST,   BODY_SLAM,    TAKE_DOWN      ; FIRE_SPIN tut e:666, FIRE_BLAST TM, BODY_SLAM TM, TAKE_DOWN e:661
	db FLAREON,   FIRE_SPIN,    FIRE_BLAST,   BODY_SLAM,    QUICK_ATTACK   ; FIRE_SPIN e:2095, FIRE_BLAST e:2096, BODY_SLAM TM, QUICK_ATTACK e:2089

	; --- Trap + status (annoyance gambler) ---
	db TANGELA,   BIND,         SLEEP_POWDER, MEGA_DRAIN,   STUN_SPORE     ; BIND e:869, SLEEP_POWDER e:865, MEGA_DRAIN e:866, STUN_SPORE e:864

	db 0 ; end sentinel

; 22 entries, stride 5 = 110 bytes + 1 sentinel.
; Runtime pick: ld c, GAMBLER_POOL_SIZE / call Rangerandom -> a in [0,21];
; entry base = GamblerMonMovesets + a*5 (species at +0, moves at +1..+4).
DEF GAMBLER_POOL_SIZE EQU 22
