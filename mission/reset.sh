#!/usr/bin/env bash
# Reset the smoke scenario to its initial state and (optionally) re-file.
#
# Usage:
#   mission/reset.sh              # interactive: reset repo + archive board cards
#   mission/reset.sh --yes        # unattended
#   mission/reset.sh --file       # reset, then file the missions (cards parked)
#   mission/reset.sh --file --launch   # reset, file, launch task 1
#
# Baseline is the git tag `mission-baseline` on the commit holding ONLY the
# scenario input (mission/ docs, no task code). The tag survives force-pushes,
# so the initial state is always addressable.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOARD=${BOARD:-smoke-test}
TAG=mission-baseline
YES=0 FILE=0 LAUNCH=0
for a in "$@"; do
  case $a in
    --yes) YES=1 ;;
    --file) FILE=1 ;;
    --launch) LAUNCH=1; FILE=1 ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

[ -f "$REPO/mission/input-spec.md" ] || { echo "refusing: no mission/input-spec.md — wrong repo?"; exit 1; }
git -C "$REPO" rev-parse -q --verify "$TAG" >/dev/null || { echo "refusing: tag $TAG missing — set it first: git tag $TAG <sha>"; exit 1; }

[ "$YES" = 1 ] || { read -rp "Reset $REPO to $TAG and archive ALL live cards on '$BOARD'? [y/N] " a; [ "$a" = y ] || exit 1; }

git -C "$REPO" reset --hard "$TAG"
git -C "$REPO" clean -fdx -e .idea -e .classpath -e .project -e .settings
git -C "$REPO" push --force origin main
echo "repo reset to $TAG"

# archive every non-archived card on the board
ids=$(hermes kanban --board "$BOARD" list --json | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    print(t['id'])")
if [ -n "$ids" ]; then
  # shellcheck disable=SC2086
  hermes kanban --board "$BOARD" archive $ids
fi
echo "board '$BOARD' cleared (archived live cards)"

[ "$FILE" = 1 ] && "$REPO/mission/file-mission.sh" file
[ "$LAUNCH" = 1 ] && "$REPO/mission/file-mission.sh" launch
exit 0