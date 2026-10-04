# Blackout Bay reconciliation

Updated 2026-10-04 UTC. Canonical remote: https://github.com/zackhaq21-ai/BLACKOUT-BAY.
Connected GitHub login verified as zackhaq21-ai; pull/push access available.

## Starting point

Claude's default branch, claude/roblox-dev-instructions-co8a58, was fetched and rechecked
at commit 8f363691301b829c91e8a1f348fe1e44e19e0b02. It contained only CLAUDE.md.
The GitHub branches API showed that one branch; the open-PR API returned no PRs.
No native game source, place, existing sync configuration or tests were present to
merge against. Unpushed work in another environment cannot be inspected here.

The integration branch is codex/aurora-prototype-reconciliation. CLAUDE.md is unchanged.
Existing prototype source was compared and imported additively; no Claude file was
overwritten. The earlier standalone folder is now a preserved baseline, not a separate
feature-development target. Future work belongs in this repository.

## Imported playable section

Native 1-5 player Aurora Exchange heist: scalable sequential objectives, alternative
entrances/quiet or forced vault, curator choices, patrol capture, free recovery/retry,
core recovery after disconnect, three exits, five-seat car and cosmetic preview.
Player-facing title is now Blackout Bay. Internal Glasshouse identifiers remain to
avoid unnecessary structural changes to tested logic. Builds output BlackoutBay.rbxlx.

The larger confirmed world remains in docs/ROADMAP.md. Economy/district modules under
experimental are executable tested models, not active police, bounty, raid, convoy or
weekly-car gameplay. No new independent features were added during reconciliation.

## Verification

- Eight native scripts compile; 29 gameplay +26 economy +19 district tests pass.
- Generated XML parses and embedded UTF-8 source matches.
- Native engine scenarios passed across crew sizes1-5 on the baseline; current logic
  passes full solo (including curator/canal), four-player and five-player scenarios.
- Current two-player rerun completed quiet/driving/recovery and reached the disconnect
  scenario, then Studio exited without a final response; the orphan helper was stopped.
  Earlier2/3-player full disconnect scenarios passed. Do not claim a complete clean
  final-source matrix. Exact evidence/build distinctions: docs/VERIFICATION.md.
- Native automation uses real server/client sessions but positions test characters and
  freezes guards. Human navigation, visual/device QA, latency and production services
  are not certified. No screenshots were captured.
- The Blackout Bay import changes only branding/output filenames relative to the tested
  gameplay source. Compilation, XML and74 model checks were rerun in this repository.

## Boundaries and next step

No Roblox publishing, account experience upload, products, purchases or Velzico changes.
No active Studio document was overwritten. Git-excluded local tool binaries remain
optional; a fresh clone can open dist/BlackoutBay.rbxlx without them.

Review this import with Claude before extending the next shared-world milestone.
Use Studio for observed human play and remaining device/physics checks.
Do not merge over concurrent work; fetch/recompare the remote branch before any merge.
The old Library v0 artifacts still refer to the earlier standalone build and are not
the authoritative Blackout Bay repository delivery.
