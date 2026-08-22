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
DEF AI_SCORE_BASE     EQU 10  ; widened to 20 in Phase 2b, alongside rescaled deltas
DEF AI_SCORE_MIN      EQU 1
DEF AI_SCORE_MAX      EQU 79
DEF AI_SCORE_DISABLED EQU $50 ; 80: reserved sentinel for a disabled move

; --- wBuffer layout during one AI cycle (30 bytes, EXACT fit) ---
; Documented here because overrunning it silently corrupts the move scores.
;   +0  .. +3   move scores
;   +4  .. +19  enemy move cache, 4 moves x {effect, power, type, accuracy}
;   +20 .. +25  party scores (6 slots), switching engine
;   +26 .. +29  pre-min-find score backup
DEF AI_BUF_SCORES     EQU 0
DEF AI_BUF_MOVECACHE  EQU 4
DEF AI_MOVECACHE_SIZE EQU 4 ; bytes cached per move: effect, power, type, accuracy
DEF AI_BUF_PARTY      EQU 20
DEF AI_BUF_SCOREBACKUP EQU 26

; wAIMoveClassMask (the classified moveset of the active enemy mon) is NOT
; allocated yet. It is per-send-out state needed only by the Phase 5 plan
; system, and the battle-scoped WRAM branch has just one spare byte left, so
; its home is decided in Phase 5 rather than guessed now.
