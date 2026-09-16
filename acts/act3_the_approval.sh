#!/usr/bin/env bash
# Act 3 — The approval. The daemon gates the work; the analyst runs sandboxed
# with its token injected by reference.

act3_main() {
  say "Act 3 — The approval"

  need_opaque
  harborlight_env
  ensure_initialized
  start_daemon

  run opaque ping
  # client_type says "agent" even for you. Classification is audit-only: an
  # agent drives the same signed CLI a human does, so it cannot be a security
  # boundary.
  run opaque whoami

  # First use requires an approval: Touch ID on macOS, polkit on Linux. In CI
  # mode the insecure backend approves it and says so in the audit record.
  run opaque execute test.noop
  run opaque leases
  # The second call rides the 300 second lease. No prompt.
  run opaque execute test.noop

  # The analyst again — inside the sandbox this time. The profile maps
  # HARBORLIGHT_SOURCE_TOKEN from a daemon-side reference. Your shell does not
  # carry it and the CLI never sees it. Success proves the injection: without
  # the token the analyst exits non-zero.
  if [[ "$(uname)" != "Darwin" ]]; then
    echo 'Linux note: this run disables the OS sandbox layer (sandbox = false).'
    echo 'Opaque 0.4.0 applies Landlock and seccomp to the sandbox wrapper itself,'
    echo 'which then cannot finish its own setup; reported upstream. Broker'
    echo 'custody, policy, approval, injection and audit below are unchanged.'
    echo
  fi
  # shellcheck disable=SC2016  # banner prints literally; expansion is the bug class we avoid
  echo '$ ANALYST_PYTHON="$(xcrun --find python3)"   # a concrete interpreter; the /usr/bin shim cannot run sandboxed'
  ANALYST_PYTHON="$(resolve_analyst_python)"
  echo
  # shellcheck disable=SC2016  # banner prints literally; expansion is the bug class we avoid
  echo '$ opaque exec --profile analyst -- "$ANALYST_PYTHON" agent/analyst.py report'
  opaque exec --profile analyst -- "$ANALYST_PYTHON" "$HARBORLIGHT_REPO/agent/analyst.py" report
  echo

  echo 'The CLI is classified as an agent, so the sandbox returned byte counts,'
  echo 'not content. The report ran, and the token that made it run was injected'
  echo 'by the daemon, by reference. Nothing in this shell could print it.'
  echo

  # Act 1's careless argv, revisited. An earlier Opaque persisted the full
  # command line in this record; 0.4.0 records only the argument count.
  # Audit metadata remains sensitive even when it contains no secret values.
  run sqlite3 "$HOME/.opaque/audit.db" \
    "select kind, detail from audit_events where kind='sandbox.created' order by rowid desc limit 1;"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=acts/_lib.sh
  source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"
  act3_main
fi
