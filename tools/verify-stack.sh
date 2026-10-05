#!/usr/bin/env bash
# Review-stack dependency verification: every branch must be pushed, match its remote, and be a descendant of
# the previous one. Prints the manifest rows used by docs/REVIEW_STACK.md. Exit 1 on any break.
set -u
cd "$(dirname "$0")/.."
STACK=(claude/roblox-dev-instructions-co8a58 claude/review-m6-decoys claude/review-m7-bounties claude/review-m8-blackouts claude/review-m9-convoys claude/review-m10-polish claude/review-m11-studio-qa)
git fetch -q origin "${STACK[@]}" 2>/dev/null || true
status=0
prev=""
printf '%-40s %-9s %-9s %-40s %s\n' BRANCH LOCAL REMOTE PARENT STATE
for b in "${STACK[@]}"; do
  local_sha=$(git rev-parse --short "$b" 2>/dev/null || echo missing)
  remote_sha=$(git rev-parse --short "origin/$b" 2>/dev/null || echo missing)
  state="ok"
  if [ "$local_sha" = "missing" ] || [ "$remote_sha" = "missing" ]; then state="NOT PUSHED"; status=1
  elif [ "$local_sha" != "$remote_sha" ]; then state="LOCAL != REMOTE"; status=1
  elif [ -n "$prev" ] && ! git merge-base --is-ancestor "$prev" "$b"; then state="NOT ON TOP OF $prev"; status=1
  fi
  printf '%-40s %-9s %-9s %-40s %s\n' "$b" "$local_sha" "$remote_sha" "${prev:-—}" "$state"
  prev="$b"
done
exit $status
