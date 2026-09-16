#!/usr/bin/env bash
# Act 1 — The leak. No Opaque yet. This is how agents run today.
#
# Every "secret" below is a dummy value. Do NOT replace with a real secret.

act1_main() {
  say "Act 1 — The leak"

  # The way agents get credentials today: exported into their environment.
  # Dummy value used as a "secret". This act intentionally shows it leaking.
  # Do NOT replace with a real secret.
  echo '$ export HARBORLIGHT_SOURCE_TOKEN="demo_value_123456"'
  export HARBORLIGHT_SOURCE_TOKEN="demo_value_123456"
  echo

  run python3 "$HARBORLIGHT_REPO/agent/analyst.py" report

  # The agent is careless, not malicious: it dumps its environment "for
  # debugging". Every inherited secret is now in its transcript.
  echo '$ python3 agent/analyst.py debug-env | grep HARBORLIGHT'
  python3 "$HARBORLIGHT_REPO/agent/analyst.py" debug-env | grep HARBORLIGHT
  echo

  # Argv outlives the command. Any process on the machine can read it while
  # the command runs, and shells keep it in history.
  echo '$ sh -c "sleep 3; : password=dummy_value_123456" &'
  echo '$ ps -p <that pid> -o args='
  sh -c 'sleep 3; : password=dummy_value_123456' &
  local helper_pid=$!
  ps -p "$helper_pid" -o args=
  wait "$helper_pid" || true
  echo

  unset HARBORLIGHT_SOURCE_TOKEN
  echo 'The token reached the transcript and the process table. Nothing decided'
  echo 'whether this read was allowed, and nothing recorded that it happened.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=acts/_lib.sh
  source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"
  act1_main
fi
