; Party spec system (GYM_LEADER_EXPANSION_PLAN.md Phase 2).
;
; Replaces the two hand-rolled team paths - authored `db level, species, ...`
; lists and the procedural GetRandRoster - with one declarative record per
; (trainer class, wTrainerNo) that says how many mons, at what levels, drawn
; from which species pool, with movesets mixed from which sources.
;
; Nothing here decides anything at build time. These constants only describe
; the shape of the ROM tables; every roll happens at runtime in RogueBuildParty
; during battle init.

; --- Moveset sources -------------------------------------------------------
; What fills a slot's four move bytes. One source per slot; a slot gets its
; source either from its spec's mix quotas or from a slot override.
	const_def
	; Vanilla behaviour: the last 4 level-up moves at or below this level.
	; This is what AddPartyMon's `predef WriteMonMoves` already does, so this
	; source costs nothing at all - it is the absence of an override.
	const MSRC_LEARNSET        ; 0
	; Any 4 learnable at or below this level, uniformly chosen. Differs from
	; MSRC_LEARNSET in that vanilla's walk OVERWRITES earlier moves as it goes,
	; so a mon with 9 learnable moves can only ever show the last 4; this can
	; show any of them.
	const MSRC_LEARNSET_FULL   ; 1
	; Rank-weighted pick from the level-up pool only (base moves + learnset
	; entries at or below this level).
	const MSRC_RANDOM          ; 2
	; Rank-weighted pick from the UNION of the level-up pool and the species'
	; TM/HM pool, with at most `tm_cap` of the four taken from TM-only moves.
	; A move that is both level-learnable and a TM does not spend tm_cap.
	const MSRC_RANDOM_TM       ; 3
	; TM/HM pool ONLY, level-up moves excluded entirely.
	;
	; Gen 1 TMs have NO level requirement: any compatible species can learn any
	; TM at any level, so a TM-only slot at level 8 can legitimately roll
	; Blizzard or Hyper Beam. That is a difficulty lever, not a bug, and
	; `rank_row` is what holds it in check. Pair a low-level TM-only slot with a
	; low rank row unless the spike is intended.
	const MSRC_RANDOM_TM_ONLY  ; 4
	; A curated set from the generated corpus, filtered by tier mask and level
	; band. MUST fall back to MSRC_RANDOM on an empty filtered list rather than
	; read past the index - the corpus tier distribution is skewed enough that a
	; narrow mask on an uncommon species legitimately yields zero candidates.
	const MSRC_SET             ; 5
	; Four literal move ids, carried in the slot override itself.
	const MSRC_EXPLICIT        ; 6
	; Defined and dispatched, referenced by no shipping mix. Kept open
	; deliberately; behaves as MSRC_LEARNSET until given its own table.
	const MSRC_TUTOR           ; 7
DEF NUM_MSRC EQU const_value

; --- Move ranks ------------------------------------------------------------
; Rank codes as they appear in the generated MoveRankByID table (one byte per
; move id). Ascending order of power, matching the corpus's F..S grading.
	const_def
	const MOVE_RANK_F          ; 0
	const MOVE_RANK_D          ; 1
	const MOVE_RANK_C          ; 2
	const MOVE_RANK_B          ; 3
	const MOVE_RANK_A          ; 4
	const MOVE_RANK_S          ; 5
	; Excluded from every randomizer pool: NO_MOVE, SPLASH, STRUGGLE,
	; SUPER_TRANSFORM, TELEPORT, WHIRLWIND. A candidate whose rank is OFFLIST
	; is skipped rather than weighted, so it can never be selected.
	const MOVE_RANK_OFFLIST    ; 6
DEF NUM_MOVE_RANKS EQU const_value

; --- Per-move flag vocabulary ----------------------------------------------
; A 16-bit mask per move, supplied by the generated move-rank data. A mix row
; uses these as `require_flags` / `forbid_flags`, which is how gimmick
; CATEGORIES are controlled: `require` guarantees at least one move carrying
; that flag when a legal candidate exists (one sleep move on a late leader),
; `forbid` removes candidates outright (no Explosion on an early trainer).
;
; An INDIVIDUAL named move has no distinguishing flag, so pinning one specific
; move uses a slot override with BIT_POVR_MOVES instead. Categories via flags,
; individual moves via overrides.
DEF MOVEFLAG_SLEEP             EQU 1 << 0
DEF MOVEFLAG_SETUP             EQU 1 << 1
DEF MOVEFLAG_RECOVERY          EQU 1 << 2
DEF MOVEFLAG_EXPLOSION         EQU 1 << 3
DEF MOVEFLAG_HIGH_CRIT         EQU 1 << 4
DEF MOVEFLAG_PARALYSIS         EQU 1 << 5
DEF MOVEFLAG_OHKO              EQU 1 << 6
DEF MOVEFLAG_PARTIAL_TRAP      EQU 1 << 7
DEF MOVEFLAG_CONTEXT_SENSITIVE EQU 1 << 8
DEF MOVEFLAG_CUSTOM            EQU 1 << 9
DEF MOVEFLAG_BUGGED            EQU 1 << 10
DEF MOVEFLAG_FIXED_40          EQU 1 << 11
DEF MOVEFLAG_FIXED_20          EQU 1 << 12
DEF MOVEFLAG_LEVEL_DAMAGE      EQU 1 << 13
DEF MOVEFLAG_EXCLUDE_RANDOMIZER EQU 1 << 14

; --- Difficulty rows -------------------------------------------------------
; A mix row names one row of MoveRankWeightTable. The row gives a selection
; WEIGHT per move rank, so a row can be told to prefer junk or to prefer
; sweepers. Applies to every rank-weighted source (MSRC_RANDOM,
; MSRC_RANDOM_TM, MSRC_RANDOM_TM_ONLY) alike, which is what makes the
; combined learnset+TM pool fully rank-controlled.
	const_def
	const RANK_ROW_BAD         ; 0 - early route filler
	const RANK_ROW_EASY        ; 1
	const RANK_ROW_NORMAL      ; 2
	const RANK_ROW_HARD        ; 3
	const RANK_ROW_ELITE       ; 4 - Elite Four / Champion
DEF NUM_RANK_ROWS EQU const_value

; --- Curated set tiers -----------------------------------------------------
; Bit mask over the corpus's own grading, used as a mix row's `set_tier_mask`.
; A mask of 0 means "any tier".
DEF TIER_BAD    EQU 1 << 0
DEF TIER_EASY   EQU 1 << 1
DEF TIER_NORMAL EQU 1 << 2
DEF TIER_HARD   EQU 1 << 3
DEF TIER_ELITE  EQU 1 << 4

; --- Species pools ---------------------------------------------------------
; A pool entry is (species, form spec). TWO bytes, not one, and fixed width.
;
; Two bytes because a form is NOT a species: it is a base species plus a 2-bit
; index living in that mon's MON_CATCH_RATE bits 5-6 (see TRAINER_PARTY_FORMS.md
; and the `project_forms_are_not_species` note). Species ids already reach $FD,
; so there is no spare bit in the species byte to pack a form into. A separate
; per-pool form override list was rejected: it cannot express a pool that holds
; BOTH the base species and one of its forms as distinct draws, which is exactly
; what a type-themed leader pool wants (Ninetales is Fire, Alolan Ninetales is
; Ice - a pool may legitimately want either or both).
;
; Fixed width because a pool is indexed by a single random draw. A
; variable-length encoding would force a walk per selection and would break the
; three-run layout below.
DEF POOL_ENTRY_SIZE EQU 2

; form spec byte values
; Let RogueRollFormForSpecies decide, exactly as a procedural roster mon does.
; This is the default and is correctly gated by species-group unlocks.
DEF POOL_FORM_ROLL EQU $FF
; Force the ordinary base species; never a regional form.
DEF POOL_FORM_BASE EQU 0
; 1..NUM_FORM_SLOTS force that form index. UNGATED by species-group unlocks, on
; purpose and consistently with authored TRAINERPARTY_FORMS teams: a pinned form
; in a pool is authored content, and TRAINER_PARTY_FORMS.md's rule is "authored
; content shows exactly what you wrote regardless of the player's unlock state.
; If you want a trainer's forms to appear only late, gate the trainer, not the
; form." A form index with no matching record degrades to the base species
; silently, which is also that document's stated behaviour.

; A pool is stored as three CONTIGUOUS runs - Kanto entries, then Johto, then
; Time Warp - plus one count per run, mirroring the RARITY_TIER_ENTRY_SIZE shape
; in engine/pokemon/rarity.asm. At runtime the runs whose species group is not
; active are skipped, so a pool automatically shrinks to the player's unlock
; state with no scanning and no per-entry group byte.
;
; db kanto_count, johto_count, warp_count, dw list
DEF POOL_TABLE_ENTRY_SIZE EQU 5

; --- Party spec flags ------------------------------------------------------
	const_def
	; Build the last slot as the team's "ace": it is exempt from the quota
	; shuffle and always takes the strongest source the mix names.
	const BIT_PSPEC_ACE_LAST     ; 0
	; Reroll a species that already appears earlier in the party. Bounded
	; retries, then accepted, so a pool smaller than the team size cannot hang.
	const BIT_PSPEC_NO_DUPES     ; 1
	; Allow RARITY_TIER_UBER species from the pool. Off by default, so a pool
	; may list one (the plan gives Prof. Oak's pool Mew as an uber option)
	; without a route trainer ever being handed it.
	;
	; ⚠ NAMED FOR WHAT IT ACTUALLY GATES, which is narrower than "legendary".
	; In THIS tree RARITY_TIER_UBER is exactly {MEW, MEWTWO}: the legendary
	; birds are KantoUltraball (measured in engine/pokemon/rarity.asm, not
	; assumed), so ARTICUNO in a pool is NOT excluded by this flag. An earlier
	; draft called it ALLOW_LEGEND, which read as covering the birds and would
	; have quietly let them through wherever an author trusted the name. Use
	; BIT_POVR_RARITY on a slot, or leave them out of the pool, to control those.
	const BIT_PSPEC_ALLOW_UBER   ; 2

; --- Slot override flags ---------------------------------------------------
; A slot override is `db slot_index, ovr_flags` followed by the optional bytes
; the flags name, IN BIT ORDER, low bit first. The parser walks bits 0..n and
; consumes each present field's width from PartySpecOverrideFieldWidths, so
; adding a field means adding a bit here and a width there - nothing else.
;
; A slot override WINS over the mix and removes that slot from the quota
; shuffle, so the remaining quotas distribute across the slots that have none.
; That is what makes "force slots 2 and 5 TM-only, leave the rest to the mix"
; expressible without a second mechanism.
	const_def
	const BIT_POVR_SPECIES  ; 0 - +2: species, form spec
	const BIT_POVR_LEVEL    ; 1 - +1: absolute level, replacing base + slot*step
	const BIT_POVR_SOURCE   ; 2 - +1: MSRC_*
	const BIT_POVR_MOVES    ; 3 - +4: literal move ids; implies MSRC_EXPLICIT
	const BIT_POVR_TYPE     ; 4 - +1: required type for this slot's pool roll
	const BIT_POVR_RARITY   ; 5 - +1: required rarity tier for the pool roll
DEF NUM_POVR_FIELDS EQU const_value

DEF PARTY_SPEC_OVERRIDES_END EQU $FF ; terminates a spec's override list

; --- Generator scratch -----------------------------------------------------
; Level-up move candidates buffered per mon. MEASURED, not guessed: the longest
; level-up learnset in data/pokemon/evos_moves.asm is 11 entries (Vaporeon), and
; a mon also carries up to NUM_MOVES level-1 moves from its base-stats row, so
; the true worst case is 15. 16 gives one byte of margin and keeps the scratch
; inside the 30-byte union window (see wPartyGenScratch in ram/wram.asm).
;
; TM/HM candidates are deliberately NOT buffered - they are enumerated straight
; out of wMonHLearnset, the form-aware 7-byte bitfield GetMonHeader already
; loaded, which is what keeps this buffer at 16 bytes instead of 71.
DEF PARTY_GEN_MAX_CANDIDATES EQU 16

; Bounded retry count for BIT_PSPEC_NO_DUPES and for filtered pool rolls. A
; pool that cannot satisfy the filter must degrade, never spin.
DEF PARTY_GEN_MAX_RETRIES EQU 8

; Draws the rejection sampler gets per move slot before it settles for the last
; eligible candidate regardless of weight. 40 is generous: every row of
; MoveRankWeightTable contains at least one weight of 64, so a candidate pool
; that includes any move of that row's favoured rank is accepted within a couple
; of draws. The budget only binds when the whole pool sits in a low-weight rank,
; and taking a low-ranked move there is the right answer anyway.
DEF PARTY_GEN_MAX_DRAWS EQU 40

; Round bands the difficulty grid is cut into: the plan's rounds 1-2, 3-5 and
; 6-8. Three, not eight, because the mix table is a coarse ladder on purpose -
; AITierByRound already scales per round, and a per-round mix row would be nine
; rows of near-duplicates to maintain.
DEF NUM_ROUND_BANDS EQU 3

; Quota columns in a MovesetMixTable row: one per rollable source. MSRC_EXPLICIT
; and MSRC_TUTOR are deliberately excluded - explicit moves come from a slot
; override, never from a quota - so this is NOT NUM_MSRC.
DEF NUM_MSRC_QUOTAS EQU MSRC_SET + 1
