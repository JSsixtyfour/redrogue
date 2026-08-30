# Follower Checkpoint C: contained graphics reservation

Apply to Red Rogue `master` at accepted baseline `4ef06335`.

This slice reserves walking image base 2 only on `SILPH_CO_B1F` and `SILPH_CO_DORM`. Authored walking sprites on those maps begin at base 3. It also ports Yellow's unused-picture guard so disabled Dorm decoration slots are skipped safely.

The follower remains unpublished and unticked. No follower graphics are loaded and no follower should appear. All other maps retain the baseline allocation path.

## Files

- `engine/overworld/map_sprites.asm`
- `tools/pyboy_smoke/test_follower_sprite_budget.py`
- `checkpoint_c.patch`

## Verification

- Focused suite: 4 passing tests and the existing intentional lobby expected failure.
- Forced Red, Blue, and Debug builds pass.
- MD5 Red: `B0E6BE7D79AFFFFF5BEF5007F57E5FBB`
- MD5 Blue: `DFCFBB196DF57D338A42027A6B79F5F8`
- MD5 Debug: `5F45F8464933A18D13E5721B243CB246`

## Runtime checklist

- Enter Silph Co B1F and confirm Red and the scientist animate normally.
- Exercise the B1F scripted Palm movement.
- Warp between B1F and the Dorm in both directions.
- In the Dorm, check an empty/default room and several decoration combinations.
- Open and close NPC text, the Dorm PC, and decoration text to exercise sprite graphics reload.
- Confirm no follower appears.
- Visit one unrelated indoor control map and confirm its NPC graphics remain unchanged.

