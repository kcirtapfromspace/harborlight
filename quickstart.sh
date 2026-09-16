#!/usr/bin/env bash
# Harborlight quickstart driver. Runs the four acts in one throwaway
# environment so the audit chain accumulates across acts.
#
#   ./quickstart.sh            interactive: native approvals (Touch ID / polkit)
#   ./quickstart.sh --ci       headless: the loud, synthetic auto-approve backend
#   ./quickstart.sh --act 3    run a single act
#
# Every "secret" involved is a dummy value. Do NOT substitute real secrets.

set -euo pipefail

cd "$(dirname "$0")"

ACT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) export OPAQUE_QUICKSTART_CI=1; shift ;;
    --act) ACT="${2:?usage: --act N}"; shift 2 ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

source acts/_lib.sh
source acts/act1_the_leak.sh
source acts/act2_the_policy.sh
source acts/act3_the_approval.sh
source acts/act4_the_receipt.sh

harborlight_env

case "$ACT" in
  "") act1_main; act2_main; act3_main; act4_main ;;
  1) act1_main ;;
  2) act2_main ;;
  3) act3_main ;;
  4) act4_main ;;
  *) echo "unknown act: $ACT (expected 1-4)" >&2; exit 2 ;;
esac

say "Done"
echo 'Fifteen minutes, one leak, one policy, one approval, one receipt.'
echo 'Next: docs/evaluation-guide.md — "Falsify it in fifteen minutes".'
