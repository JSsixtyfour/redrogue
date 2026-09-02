; Trainer AI overhaul constants (AI_OVERHAUL_PLAN.md).
;
; The AI is selected by a battle-count-derived SKILL TIER rather than by
; trainer class. Each tier owns a 16-bit word:
;
;   bits 0-11  scoring layers, dispatched in bit order through AIScoringPointers
;   bits 12-15 behaviour flags, never dispatched, queried with AIHasFlag
;
; Layers always run in bit order, so the bit numbering below IS the execution
; order. Cheap eliminations run first; the most decisive adjustments run last.

; --- Scoring layers (dispatched) ---
DEF AI_REDUNDANT  EQU 1 << 0 ; kill moves that would do literally nothing
DEF AI_BASIC      EQU 1 << 1 ; vanilla layer 1: status move onto a statused target
DEF AI_TYPES      EQU 1 << 2 ; vanilla layer 3: type effectiveness
DEF AI_SETUP      EQU 1 << 3 ; vanilla layer 2: prefer stat-up/setup moves
DEF AI_SMART      EQU 1 << 4 ; per-move-effect heuristics
DEF AI_DAMAGE     EQU 1 << 5 ; damage/KO simulator scoring
DEF AI_THREAT     EQU 1 << 6 ; "can the player KO me next turn" awareness
DEF AI_PLAN       EQU 1 << 7 ; adaptive multi-turn strategy plans
DEF AI_RISKY      EQU 1 << 8 ; big bonus for a predicted KO
; bits 9-11 reserved for future layers

; Number of dispatched layer slots. The dispatch loop stops here, which is what
; keeps the flag bits below from ever being called as routines.
DEF NUM_AI_LAYERS EQU 9

; --- Behaviour flags (queried, NEVER dispatched) ---
; AI_OMNISCIENT is the information-model axis: it controls what the AI is
; allowed to KNOW, independently of how well it reasons. Phase 7 (2026-08-26)
; cleared it on T0/T1 - see AITierLayers - so early trainers reason about the
; player's MOVESET only from what has actually been revealed this battle.
; Type/status/HP/stat stages are unaffected: they stay readable at every tier,
; always (see ai_accessors.asm and ai_fairplay.asm).
DEF AI_OMNISCIENT EQU 1 << 12
; bits 13-15 reserved for future flags

; --- Skill tiers ---
DEF AI_TIER_NOVICE    EQU 0
DEF AI_TIER_COMPETENT EQU 1
DEF AI_TIER_SKILLED   EQU 2
DEF AI_TIER_EXPERT    EQU 3
DEF AI_MAX_TIER       EQU AI_TIER_EXPERT
DEF NUM_AI_TIERS      EQU AI_MAX_TIER + 1

; Highest round index AITierByRound is defined for. round = wBattleCount / 10,
; clamped here (the Rogue scheme runs rounds 0-8; see func_enc_gen.asm).
DEF AI_MAX_ROUND EQU 8

; Rows in AITierByRound and entries in AITierCeiling: one per LEVELS difficulty
; setting (constants/ram_constants.asm). Derived from the enum rather than
; written as 5, so adding a difficulty becomes a compile error here instead of a
; silent off-the-end table read.
DEF NUM_AI_DIFFICULTY_ROWS EQU DIFFICULTY_VERY_HARD + 1

; --- Score array bounds ---
; Scores live in wBuffer+0..3. Lower is better. Saturating helpers clamp to this
; range so no stack of adjustments can wrap a byte into (or past) the
; disabled-move sentinel.
DEF AI_SCORE_BASE     EQU 20  ; widened from 10 in Phase 2b (was ExtremeYellow's idea,
                              ; matches pokecrystal's baseline exactly)
DEF AI_SCORE_MIN      EQU 1
DEF AI_SCORE_MAX      EQU 79
DEF AI_SCORE_DISABLED EQU $50 ; 80: reserved sentinel for a disabled move

; --- Scoring vocabulary (Phase 2b) ---
; Why the baseline widened from 10 to 20: with base 10 there are only 9 points
; of headroom between the baseline and AI_SCORE_MIN, so a move attracting
; several encouragements at once (super-effective, STAB, predicted KO, and a
; plan bonus) floors out at 1 and becomes indistinguishable from every other
; floored move. Base 20 doubles that headroom without touching the disabled
; sentinel at 80, so graded scoring stays meaningful once AI_SMART (and later
; the damage layer) start stacking adjustments on the same move.
;
; Use these names rather than bare numbers, so a future rescale is one edit.
; Magnitudes match pokecrystal's, which is where the base-20 scale comes from.
DEF AI_NUDGE       EQU 1  ; a mild preference
DEF AI_STRONG      EQU 2  ; a clear preference
DEF AI_VERY_STRONG EQU 3  ; a decisive preference
DEF AI_HEAVY       EQU 10 ; pokecrystal's AIDiscourageMove: a big penalty, but
                          ; deliberately NOT a ban - a move at base+10 still
                          ; beats one at base+20, and can still be chosen if
                          ; every alternative is worse.

; Phase 3: a move the damage simulator says KILLS this turn. Larger than
; AI_VERY_STRONG on purpose - "take the guaranteed kill" is rank 1 of the plan's
; priority cascade and must outrank every ordinary preference stacked against
; it, including AI_TYPES' nudges and AI_SMART's per-effect opinions. It is still
; below AI_HEAVY, so a move AI_REDUNDANT proved cannot work never wins on the
; strength of a KO it would not actually land.
DEF AI_KILL        EQU 5

; Enough to saturate a score to AI_SCORE_MAX from the baseline in one step,
; for the "this move does literally nothing" case. Deliberately expressed as a
; computation, not a literal, so it stays correct if the baseline moves again.
; (Phase 2a used a hardcoded 69, which happened to remain correct across the
; 10 -> 20 widening only by luck.)
DEF AI_SATURATE    EQU AI_SCORE_MAX - AI_SCORE_BASE + 1

; --- wBuffer layout during one AI cycle (30 bytes, EXACT fit) ---
; Documented here because overrunning it silently corrupts the move scores.
;   +0  .. +3   move scores
;   +4  .. +9   saved wPlayerMove* block (Phase 3 Step 2, see below)
;   +10         scratch slot index for the player-move scan
;   +11         nonzero if the enemy outspeeds the player (AI_THREAT, cached)
;   +12 .. +13  enemy HP total the player's moves are tested against
;   +14 .. +15  best expected damage this AI_DAMAGE pass
;   +16         slot that damage belongs to
;   +17         slot currently being scored
;   +18 .. +19  AISelectSendOut best-candidate record (Phase 4)
;   +20 .. +27  per-slot move class masks (Phase 5), two bytes each
;   +28         magnitude AILayerPlan is applying this turn (+29 free)
DEF AI_BUF_SCORES     EQU 0

; +4..+9 was reserved for a per-move cache of {effect, power, type, accuracy}.
; That cache was CANCELLED in Phase 2b: its entire justification was avoiding
; cross-bank ReadMove farcalls, which evaporated once every scoring layer was
; pinned to bank $0E alongside the Moves table. The region is reused by
; AIPlayerWouldKO (Phase 3 Step 2), which has to borrow the live wPlayerMove*
; block to ask the damage simulator "what would this player move do to me",
; and stashes the real contents here for the duration of the scan.
DEF AI_BUF_MOVESAVE   EQU 4  ; 6 bytes: a whole MOVE_LENGTH move record
DEF AI_BUF_SCANSLOT   EQU 10 ; 1 byte: which of the player's 4 slots we are on
DEF AI_BUF_THREATFAST EQU 11 ; 1 byte: nonzero if the enemy outspeeds the player
                             ; on RAW SPEED, cached once per AI_THREAT pass. Note
                             ; this is not the same question as "do I act first" -
                             ; Quick Attack and Counter override it per move; see
                             ; AIEnemyActsFirstWith in ai_predicates.asm.
DEF AI_BUF_EFFHP      EQU 12 ; 2 bytes: the enemy HP total the player's moves are
                             ; tested against. Normally the live current HP, but
                             ; AIHealWouldStillDie substitutes the POST-heal total,
                             ; so "would healing actually save me" reuses the same
                             ; scan instead of needing a max-damage value.
; Phase 3 Step 3: AI_DAMAGE's best-expected-damage tracking. Coarse damage
; tiers (kills / half / quarter) cannot separate two moves that land in the same
; band - Thunderbolt and Thunder both "take at least a quarter" - so the layer
; also tracks which move has the highest EXPECTED damage and gives it an extra
; nudge. That comparative pass is what actually implements "prefer the better
; move"; the tiers only say how threatening a move is in absolute terms.
DEF AI_BUF_BESTDMG    EQU 14 ; 2 bytes: best expected damage seen this pass
DEF AI_BUF_BESTSLOT   EQU 16 ; 1 byte: which move slot that was ($ff = none yet)
DEF AI_BUF_CURSLOT    EQU 17 ; 1 byte: the slot being scored right now, stashed
                             ; because the AIEstimateDamage farcall destroys
                             ; every register that could otherwise carry it
; Phase 4: AISelectSendOut's running best-candidate record. Lives in the +14..19
; span rather than the +20..25 party-score array, because the two are used at
; DIFFERENT moments - the array is AIScoreParty's output during a switch
; decision, this is the send-out scan's own scratch - and overlapping them would
; make one silently depend on the other's timing.
DEF AI_BUF_BESTPARTYSCORE EQU 18 ; 1 byte: best type multiplier seen ($ff = none)
DEF AI_BUF_BESTPARTYSLOT  EQU 19 ; 1 byte: slot it belongs to ($ff = none yet)
; Phase 5: the four per-slot MOVE CLASS masks, two bytes each, little-endian.
; This region was reserved through Phase 4 as AI_BUF_PARTY (six party scores)
; plus AI_BUF_SCOREBACKUP (a four-byte pre-min-find score backup) and NEITHER
; was ever written: Phase 4 folded party scoring into AISelectSendOut, which
; needs only the two-byte running best record at +18..19, and nothing has yet
; needed to ask "were all four moves discouraged". Both DEFs are removed rather
; than left as dead reservations, so the free space is visible to whoever needs
; it next. If a score backup is wanted later, +28..29 is what is left - two
; bytes, not four - and it is currently the plan layer's directive scratch, so
; that is a real conflict to resolve rather than a spare corner.
DEF AI_BUF_PLANCLASS  EQU 20 ; 8 bytes: slot N's class mask at +20 + N*2
; AI_SETUP's usefulness gate (2026-09-01). Set once per AI_SETUP pass, BEFORE
; its move loop starts, to 1 if this mon owns a physical damaging move and 0 if
; it does not. It has to live here rather than in a register because the loop
; already needs hl (score pointer), de (movelist cursor) and b (counter), and
; every iteration calls ReadMove, which would destroy anything left in a or c.
; +29 was the last free wBuffer byte; wBuffer is now an exact 30-byte fit with
; nothing spare. Anything wanting scratch after this needs a real allocation.
DEF AI_BUF_PHYSICAL   EQU 29

DEF AI_BUF_PLANMAG    EQU 28 ; 1 byte: the magnitude AILayerPlan is currently
                             ; applying, held here rather than in a register
                             ; because the apply loop already needs hl (score
                             ; pointer), de (mask cursor) and bc (the 16-bit
                             ; directive mask itself), leaving only a as
                             ; scratch. +29 is AI_BUF_PHYSICAL, above.

; wAIMoveClassMask was never allocated, and Phase 5 deliberately did NOT
; allocate it. Classification is recomputed at the top of every AILayerPlan
; pass from wEnemyMonMoves rather than cached across turns, which costs four
; ReadMove calls once per turn - the same order as one AI_DAMAGE pass - and in
; exchange the masks cannot go stale against a Transform, a Mimic, a Disable,
; or a mid-battle switch. Nothing about the plan system needs WRAM that
; survives a turn except wAIPlan/wAIPlanStep, which Phase 1 already allocated.

; --- Move classes (Phase 5) ---
; A 16-bit mask describing what a move is FOR, so plans can say "the speed-boost
; move" without naming Agility, and so a mon with a different moveset still
; qualifies for the same plan.
;
; Classes are keyed on the move's EFFECT byte, not on its move id. That is a
; deliberate departure from the plan document's `dbw move, classbit` shape and
; it is strictly better here: the effect byte is what the engine itself
; dispatches on, so a class can never disagree with what the move actually does,
; and the table is ~30 entries instead of ~100. The one class that is not
; effect-derived is AICLASS_DAMAGE, which is simply "power != 0" and is applied
; by the classifier directly.
;
; A CLASS IS A MOVE'S PRIMARY PURPOSE, NOT ITS SIDE EFFECTS. Body Slam is
; AICLASS_DAMAGE, not AICLASS_PARALYZE, even though it paralyses 30% of the
; time. That distinction is what keeps a plan directive sharp: a paralysis plan
; that says "use the paralyse move" must mean Thunder Wave, not a physical
; attack that sometimes happens to paralyse. Secondary-effect value is already
; scored, per rider and by real proc rate, by AI_SMART (Phase 3 Step 3).
;
; Sixteen bits is the budget, so three classes from the plan document's list
; were cut rather than widening every mask to three bytes:
;   HIGH_CRIT   - AI_RISKY already nudges HighCriticalMoves when the AI is
;                 losing, which is the only board state a crit-fishing PLAN
;                 would ever fire on.
;   STRONG_STAB - not a static property of a move at all: it depends on the
;                 USER's types. What plans actually want from it is
;                 AICLASS_DAMAGE.
;   FINISHER    - would have held HYPER_BEAM_EFFECT alone, and both things a
;                 finisher plan would do are already done: AI_DAMAGE applies
;                 AI_KILL when Hyper Beam kills, and AISmart_HyperBeam owns the
;                 recharge trade-off. The bit went to AICLASS_BOOST_DEF instead,
;                 which nothing else covers and which Substitute-behind-Barrier
;                 lines genuinely need.
DEF AICLASS_SLEEP     EQU 1 << 0
DEF AICLASS_PARALYZE  EQU 1 << 1
DEF AICLASS_POISON    EQU 1 << 2
DEF AICLASS_CONFUSE   EQU 1 << 3
DEF AICLASS_TRAP      EQU 1 << 4
DEF AICLASS_RECOVERY  EQU 1 << 5
DEF AICLASS_BOOST_SPD EQU 1 << 6
DEF AICLASS_BOOST_ATK EQU 1 << 7
DEF AICLASS_BOOST_SPC EQU 1 << 8
DEF AICLASS_BOOST_DEF EQU 1 << 9
DEF AICLASS_SCREEN    EQU 1 << 10
DEF AICLASS_SUB       EQU 1 << 11
DEF AICLASS_EXPLODE   EQU 1 << 12
DEF AICLASS_OHKO      EQU 1 << 13
DEF AICLASS_DRAIN     EQU 1 << 14
DEF AICLASS_DAMAGE    EQU 1 << 15 ; the one dynamic class: any move that deals
                                  ; damage at all. Nonzero base power, plus the
                                  ; fixed-damage effects, which carry 0 power.

; Composites, for plan masks and directives.
DEF AICLASS_BOOST_ANY  EQU AICLASS_BOOST_SPD | AICLASS_BOOST_ATK | AICLASS_BOOST_SPC | AICLASS_BOOST_DEF
DEF AICLASS_STATUS_ANY EQU AICLASS_SLEEP | AICLASS_PARALYZE | AICLASS_POISON | AICLASS_CONFUSE

; --- Strategy plans (Phase 5) ---
; wAIPlan holds a plan ID; 0 means "not selected yet", which is what the
; battle-start zeroing of wMiscBattleData gives us for free, and what
; AISelectSendOut writes back on every send-out so a fresh mon re-selects.
; A plan's index into AIPlanTable is its ID minus one.
DEF AI_PLAN_NONE          EQU 0
DEF AI_PLAN_BRUISER       EQU 1  ; the guaranteed fallback: qualifies for every mon
DEF AI_PLAN_AGILITY_WRAP  EQU 2  ; outspeed first, then soft-lock with a trap move
DEF AI_PLAN_WRAP_LOCK     EQU 3  ; already faster: trap without spending a turn on Agility
DEF AI_PLAN_SLEEP_LEAD    EQU 4  ; land the highest-value status in the game
DEF AI_PLAN_AMNESIA_REST  EQU 5  ; boost Special, sustained by healing
DEF AI_PLAN_AMNESIA       EQU 6  ; boost Special alone
DEF AI_PLAN_TOXIC_STALL   EQU 7  ; poison, then outlast on Recover
DEF AI_PLAN_CHANSEY_STALL EQU 8  ; paralyze, then outlast on Recover
DEF AI_PLAN_PARA_SWEEP    EQU 9  ; paralyze a faster player, then attack
DEF AI_PLAN_SUB_STALL_REC EQU 10 ; sub, then chip with a rider, healing behind it
DEF AI_PLAN_SUB_STALL_PSN EQU 11 ; sub, then chip with poison
DEF AI_PLAN_SUB_SETUP     EQU 12 ; sub, then boost safely behind it
DEF AI_PLAN_BOMB_TRADE    EQU 13 ; preserve the Explosion user for a worthwhile trade
DEF AI_PLAN_OHKO_FISH     EQU 14 ; a losing-position gamble on a one-hit KO move
DEF AI_PLAN_SWORDS_DANCE  EQU 15 ; boost Attack alone
DEF NUM_AI_PLANS          EQU 15

; Table-order tiebreak: AIPlanSelect keeps the EARLIER entry on an exact
; fitness tie, so a plan whose required mask is a SUPERSET of a relative's is
; always listed first - a mon that qualifies for both takes the richer plan.
; AGILITY_WRAP (TRAP|BOOST_SPD) before WRAP_LOCK (TRAP) follows this already;
; AMNESIA_REST (BOOST_SPC|RECOVERY) before AMNESIA (BOOST_SPC), and both
; SUB_STALL variants (SUB|RECOVERY, SUB|POISON) before bare SUB_SETUP (SUB),
; follow the same rule below.

; Plan directive magnitudes MUST stay below AI_KILL. This is an invariant, not a
; style preference: rank 1 of the plan's priority cascade is "take a guaranteed
; KO", and AI_DAMAGE has already applied AI_KILL to any lethal move by the time
; AI_PLAN (bit 7) runs. A plan that could out-encourage a kill would make a
; setup mon walk past a won game to keep boosting.
DEF AI_PLAN_MAX_MAGNITUDE EQU AI_KILL - 1

; Incumbency bonus. Added to the fitness of the plan that is ALREADY active, so
; a challenger has to be meaningfully better - not merely better by one point on
; a board that jitters turn to turn - before the AI abandons a half-executed
; plan. This is the same lesson Phase 4's anti-ping-pong guard encodes for
; switching, applied to plans, and it is why this design needs no explicit
; abort-condition list or aborted-plan exclusion set: a plan that has become
; impossible returns a fitness of 0 from its own fitness routine and loses to
; the fallback regardless of incumbency.
DEF AI_PLAN_INCUMBENCY EQU 8
