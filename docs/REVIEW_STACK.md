# Review stack manifest (frozen 2026-10-05)

Recover the exact review sequence with `tools/verify-stack.sh` (prints this table from git and exits non-zero on any break). Each branch is a fast-forward descendant of the one above it. **None is merged.** Merge, when approved, is fast-forward in this order. Never rewrite the history of any row.

| Order | Branch | HEAD | Parent (dependency) | Content | Automated status at freeze |
|---|---|---|---|---|---|
| 0 | `claude/roblox-dev-instructions-co8a58` | `0a609f8` | — (stable dev branch) | core heist, hideouts, raids, recovery | 0 type errors, 0 lint, logic tests passing, places build |
| 1 | `claude/review-m6-decoys` | `2a7c29a` | row 0 | fake bags, decoy cars | 0 / 0 / all passing / builds |
| 2 | `claude/review-m7-bounties` | `77b1a5f` | row 1 | bounties, 7-stud takedowns | 0 / 0 / 59 tests / builds |
| 3 | `claude/review-m8-blackouts` | `9e259d6` | row 2 | world-event framework, harbour blackout | 0 / 0 / 65 tests / builds |
| 4 | `claude/review-m9-convoys` | `2f0ab3b` | row 3 | armored convoy event | 0 / 0 / 74 tests / builds |
| 5 | `claude/review-m10-polish` | `c99420b` | row 4 | premium polish pass (feel, camera, vehicles, environment, VFX, audio, UI) | 0 / 0 / 90 tests / builds |
| 6 | `claude/review-m11-studio-qa` | `8ea2970` | row 5 | Studio QA pack only: sectioned master scenario, perf capture, torture test, config-derived texts, QA docs | 0 / 0 / 90 tests / builds |
| 7 | `claude/review-m12-studio-fixes` | see `git rev-parse --short claude/review-m12-studio-fixes` | row 6 | evidence-driven fixes and tuning from real Studio runs (harness arrival confirmation first) | 0 / 0 / 90 tests / builds |

The freeze was partially lifted on 2026-10-05 for evidence-driven work (row 7 onward): every change there cites a Studio observation, a real bug, an incomplete journey step or a measurement. Gameplay and polish development without evidence stays frozen at row 5. Row 6 contains no new gameplay or presentation systems; it changes test code, tooling, docs and five UI/prompt strings that now read their numbers from `Config`.

## Recovery
```
git fetch origin
git checkout claude/review-m11-studio-qa          # the full stack, newest first
tools/verify-stack.sh                             # confirms every branch matches its remote and its parent
tools/check.sh && tools/build.sh                  # automated gate: type check, lint, logic tests, both places
```
To review a single layer, check out its branch; its diff against its parent row is that feature alone.

## Merge procedure (only after approval and the Studio master run)
```
git checkout claude/roblox-dev-instructions-co8a58
git merge --ff-only claude/review-m6-decoys
git merge --ff-only claude/review-m7-bounties
git merge --ff-only claude/review-m8-blackouts
git merge --ff-only claude/review-m9-convoys
git merge --ff-only claude/review-m10-polish
git merge --ff-only claude/review-m11-studio-qa
git merge --ff-only claude/review-m12-studio-fixes
```
