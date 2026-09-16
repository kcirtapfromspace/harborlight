#!/usr/bin/env bash
# Act 4 — The receipt. A real denial, a verified chain, and one tampered row.

act4_main() {
  say "Act 4 — The receipt"

  need_opaque
  harborlight_env
  ensure_initialized
  start_daemon

  # The denial act. The github-secrets preset has no gitlab rule, so the
  # broker refuses this before resolving any credential or touching the
  # network. No GitLab account, token, or project exists anywhere here.
  echo '$ opaque gitlab set-ci-variable --project tutorial/denied --key TUTORIAL_KEY --value-ref keychain:opaque/tutorial-value'
  if opaque gitlab set-ci-variable \
    --project tutorial/denied \
    --key TUTORIAL_KEY \
    --value-ref keychain:opaque/tutorial-value; then
    echo 'unexpected: the operation was allowed; inspect the active policy' >&2
    exit 1
  fi
  echo
  echo '(denied before provider execution, as the policy requires)'
  echo

  run opaque audit tail --kind policy.denied --limit 5
  run opaque audit tail --limit 10
  if [[ "$CI_MODE" == "1" ]]; then
    # The bypass is itself audited. The daemon announced the insecure backend
    # at startup, and the record names it.
    run opaque audit tail --operation daemon_startup --limit 2
  fi
  run opaque audit verify

  say "Falsify it"

  stop_daemon

  # Tamper with one recorded row, then verify again. The chain must break.
  run sqlite3 "$HOME/.opaque/audit.db" \
    "update audit_events set detail='tampered' where rowid=(select max(rowid) from audit_events);"

  echo '$ opaque audit verify'
  if opaque audit verify; then
    echo 'unexpected: tampering was not detected' >&2
    exit 1
  fi
  echo
  echo 'TAMPER DETECTED: opaque audit verify exited non-zero, as it must.'
  echo
  echo 'Verification checks local audit integrity under its custody'
  echo 'assumptions. Someone holding the audit HMAC key can forge records;'
  echo 'verification cannot establish that a compromised broker reported'
  echo 'truthfully. This environment is disposable — the cleanup trap removes'
  echo 'the tampered database with the rest of the throwaway HOME.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=acts/_lib.sh
  source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"
  act4_main
fi
