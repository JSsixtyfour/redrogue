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
; allowed to KNOW, independently of how well it reasons. Every tier sets it for
; now; Phase 7 clears it on T0/T1 so early trainers reason only from moves the
; player has actually revealed.
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
;   +20 .. +25  party scores (6 slots), switching engine
;   +26 .. +29  pre-min-find score backup
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
DEF AI_BUF_PARTY      EQU 20
DEF AI_BUF_SCOREBACKUP EQU 26

; wAIMoveClassMask (the classified moveset of the active enemy mon) is NOT
; allocated yet. It is per-send-out state needed only by the Phase 5 plan
; system, and the battle-scoped WRAM branch has just one spare byte left, so
; its home is decided in Phase 5 rather than guessed now.
