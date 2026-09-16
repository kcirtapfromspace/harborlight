#!/usr/bin/env bash
# Act 2 — The policy. Opaque installed, no daemon yet. Deny by default.

act2_main() {
  say "Act 2 — The policy"

  need_opaque
  harborlight_env
  ensure_initialized

  # The same policy file answers both questions. ALLOW names the rule and the
  # approval it will demand; DENY is the default for everything unmatched.
  run opaque policy simulate --operation test.noop --client-type agent
  run opaque policy simulate --operation gitlab.set_ci_variable --client-type agent

  echo 'Simulation is a dry run of the policy file. The daemon can hold an'
  echo 'operation to a stricter approval than the rule states; it never holds'
  echo 'one to a looser one.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=acts/_lib.sh
  source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"
  act2_main
fi
