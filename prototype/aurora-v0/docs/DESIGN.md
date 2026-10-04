# Blackout Bay: Aurora Exchange

Working original title, not a trademark clearance. Setting: a fictional coastal island
with an after-hours light museum holding the Aurora core. The island is the starting
district of the approved larger shared world, not a replacement for that vision.

## Current native slice

**Loop:** gather 1–5 → pick approach → manage patrols and crew heat → unlock/force vault
→ secure core → leave gallery → drive/walk to an available extraction → results/retry.
Target first-session run length: 5–8 minutes, to be measured in playtests.

| Crew | Signal objectives | Patrol drones | Role guidance |
|---|---:|---:|---|
| Solo | 2 | 2 | All tools |
| 2 | 2 | 2 | Coordinate / signal |
| 3 | 3 | 3 | Add courier |
| 4 | 3 | 3 | Add lookout |
| 5 | 4 | 4 | Add pathfinder |

Roles convey responsibility rather than gate abilities. All consoles are sequential.
No objective needs simultaneous players. A forced-vault route remains available if
the crew prefers a faster, louder plan.

The daily UTC seed fixes the watched entrance, active vault wing, and patrol start.
Shuffle changes those parameters on retry. Entrances take the crew to distinct gallery
positions. This is variation inside one authored location, not three separate maps.

| Choice or mistake | Immediate consequence | Later consequence |
|---|---|---|
| Watched entrance | +12 heat | Less room for later detection |
| Cut light grid | Skyline windows dim; patrol range shortens | Quiet vault access |
| Capture curator | One signal, +25 heat | Canal remains closed |
| Release curator | -15 heat | Canal available |
| Force vault | +65 heat | Distinct result tier; tram may close |
| Drone exposure | Heat; eventual capture | Bonus loss, free recovery costs time |
| Carrier disconnect/capture | Core at gallery recovery point | Partner can retrieve it |
| Extract before everyone regroups | Nearby crew escapes | Others get only participation XP |

The current recovery room is a temporary heist mechanic. It is not the approved future
police/prison system, and museum drones are not the future ten-police fallback.

## Visual direction

Coastal dusk, warm concrete, blue-green water, ink-blue architecture, mint signal
technology, amber vehicles, coral security. Broad low-poly silhouettes and restrained
neon accents. Native parts keep the file self-contained. The current car and suit colors
are functional prototype assets, not the final production skin collection.

Art expansion should preserve consistent silhouettes and readable team markers. Paid
car, equipment, shield/laser and hideout skins must not change hitboxes, handling, sight
range, collision, sound advantage, or visibility. A darker skin cannot become a stealth
upgrade. No outside assets or exact copied maps/branding are authorized by this file.

## Retention and monetization

Free retry, earned cosmetic XP milestones, daily repeatable layout, distinct results:
Ghost Crew / Narrow Escape / Smash & Dash / Last Light. No paid energy, paid retry,
paid required tool, randomized paid crate, or loss/rebuy of paid ownership.

Robux catalog candidates are permanent character outfits and base decoration, later
car/gun/shield/laser/hideout appearances. Catalog UI is preview-only. IDs and activation
flags are zero/false. One-time passes are the preferred ownership mechanism.

The $30–50k/month aspiration is not a forecast. First establish whether this is fun.
Run 10 observed first-session tests spanning solo, pairs and five-player groups. Record:

- Time to first correct interaction; can players explain the next objective?
- Completion, capture, rage-quit and second-run rates by crew size.
- Which entrance/vault/exit paths are used; whether one choice dominates.
- Meaningful partner mistakes versus opaque or frustrating punishment.
- Whether anyone needs help to recover, retry, use controller/touch, or understand ownership.

Proposed private-test gates (not claimed results): most players act within 60 seconds,
at least half voluntarily choose a second run, no solo softlock, no duplicate reward,
and no missing-core failure after disconnect. Tune difficulty from observations.

Server Output currently records GLASSHOUSE_RUN_START and GLASSHOUSE_RUN_END with
seed, group size, outcome, elapsed time, heat and captures. No external telemetry is sent.
Production analytics, retention cohorts and economy reporting are later work.
