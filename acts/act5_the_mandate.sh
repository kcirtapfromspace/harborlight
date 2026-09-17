#!/usr/bin/env bash
# Act 5 — The mandate. A reviewed manifest, a one-shot allowance, replay denied,
# and a revoke — the bounded-task ledger. The featured path stands up a real
# HashiCorp Vault so the credential custody is real: the broker resolves a
# vault: reference and neither your shell nor the agent ever holds the plaintext.
# GitHub is a local mock (only the destination effect is faked). With --mock, or
# when vault is not installed, both providers are local stdlib mocks and the run
# shows the ledger mechanics without the real-custody claim.

# Featured real Vault unless --mock is set or vault is not on PATH.
act5_vault_mode() {
  if [[ "${OPAQUE_QUICKSTART_MOCK:-0}" == "1" ]]; then echo mock; return; fi
  if command -v vault >/dev/null 2>&1; then echo vault; return; fi
  echo mock
}

# Bring up a throwaway real Vault dev server and seed a DUMMY secret.
act5_start_vault() {
  local vport dev_token
  vport="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  dev_token="demo-root-token-$$"   # dummy; this dev server is thrown away at exit

  echo "\$ vault server -dev -dev-listen-address=127.0.0.1:$vport   # real Vault, throwaway dev mode"
  vault server -dev -dev-listen-address="127.0.0.1:$vport" \
    -dev-root-token-id="$dev_token" >"$ACT5_DIR/logs/vault.log" 2>&1 &
  ACT5_VAULT_PID=$!
  export VAULT_ADDR="http://127.0.0.1:$vport" VAULT_TOKEN="$dev_token"

  local ready=0 _
  for _ in $(seq 1 100); do
    if vault status >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.1
  done
  if [[ "$ready" != 1 ]]; then
    echo "error: vault dev server did not become ready; log follows" >&2
    cat "$ACT5_DIR/logs/vault.log" >&2
    exit 1
  fi
  echo

  # The dummy secret goes into real Vault KV v2. Do NOT use a real secret.
  run vault kv put secret/task-app TOKEN=bt-demo-secret-plaintext

  ACT5_VAULT_URL="$VAULT_ADDR"
  BT_VAULT_TOKEN="$dev_token"
  echo 'The plaintext now lives in Vault. Your shell and the agent below never'
  echo 'carry it; the broker resolves the vault: reference and injects it.'
  echo
}

act5_write_config() {
  local cfg="$HOME/.opaque/config.toml"
  {
    echo "data_dir = \"$HOME/.opaque\""
    echo "enable_task_grants = true"
    if [[ "$CI_MODE" == "1" ]]; then
      echo 'approval_backend = "insecure_auto_approve"'
    fi
    cat <<'RULES'

[[rules]]
name = "allow-task-publish-manifest"
operation_pattern = "github.publish_manifest"
allow = true
client_types = ["agent", "human"]

[rules.approval]
require = "always"
factors = ["local_bio"]

[[rules]]
name = "allow-task-publish-secret-action"
operation_pattern = "github.set_actions_secret"
allow = true
client_types = ["agent", "human"]

[rules.approval]
require = "always"
factors = ["local_bio"]
RULES
  } > "$cfg"

  # shellcheck disable=SC2016  # banner prints literally; expansion is the bug class we avoid
  echo '$ cat > "$HOME/.opaque/config.toml"   # enable_task_grants + the two task rules'
  echo
  if [[ "$CI_MODE" == "1" ]]; then
    ci_banner
    export OPAQUE_INSECURE_AUTO_APPROVE=1
  fi
  run opaque policy check
}

act5_start_daemon() {
  local gh_url="$1" vault_url="$2"

  echo "\$ opaqued   # started in the background; log: $ACT5_DIR/logs/opaqued.log"
  # BT_PAT and BT_VAULT_TOKEN are exported already; the daemon resolves the
  # manifest's env: refs from its own environment. OPAQUE_DOGFOOD_LOOPBACK lets
  # the broker accept the plain-HTTP loopback provider URLs used by this demo.
  OPAQUE_DOGFOOD_LOOPBACK=1 \
  OPAQUE_GITHUB_API_URL="$gh_url" \
  OPAQUE_VAULT_URL="$vault_url" \
  OPAQUE_VAULT_TOKEN_REF="env:BT_VAULT_TOKEN" \
  RUST_LOG=info \
    opaqued >"$ACT5_DIR/logs/opaqued.log" 2>&1 &
  ACT5_DAEMON_PID=$!

  local sock="$HOME/.opaque/run/opaqued.sock" token="$HOME/.opaque/run/daemon.token" _
  for _ in $(seq 1 200); do
    if [[ -S "$sock" && -f "$token" ]]; then break; fi
    sleep 0.05
  done
  if [[ ! -S "$sock" ]]; then
    echo "error: opaqued did not start; log follows" >&2
    cat "$ACT5_DIR/logs/opaqued.log" >&2
    exit 1
  fi
  # Pin the CLI to this daemon; with data_dir set the socket lives under it.
  export OPAQUE_SOCK="$sock"
  echo

  run opaque ping
}

# Parse the task UUID from plan output. The manifest digest is 64 hex with no
# dashes and the repository id is an integer, so the first UUID is the task id.
act5_task_id() {
  grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
}

act5_lifecycle() {
  local mode="$1" manifest="$HARBORLIGHT_REPO/mandate/manifest.json"
  local plan_out tid plan2 tid2

  say "Plan the task"
  # shellcheck disable=SC2016  # banner prints literally
  echo '$ opaque task plan --manifest mandate/manifest.json'
  plan_out="$(opaque task plan --manifest "$manifest" --plain)"
  printf '%s\n\n' "$plan_out"
  tid="$(printf '%s' "$plan_out" | act5_task_id)"
  if [[ -z "$tid" ]]; then
    echo "error: could not parse task id from plan output" >&2
    exit 1
  fi

  say "Run it once"
  run opaque task run "$tid"

  say "Run it again — the allowance is spent"
  echo "\$ opaque task run $tid"
  if opaque task run "$tid"; then
    echo 'unexpected: the task ran a second time' >&2
    exit 1
  fi
  echo
  echo '(refused: the manifest authorized one write, and it was consumed.'
  echo 'A spent allowance is not restored by retrying.)'
  echo

  say "Read the receipt"
  run opaque task show "$tid"

  say "Revoke a second task before it runs"
  # shellcheck disable=SC2016  # banner prints literally
  echo '$ opaque task plan --manifest mandate/manifest.json'
  plan2="$(opaque task plan --manifest "$manifest" --plain)"
  printf '%s\n\n' "$plan2"
  tid2="$(printf '%s' "$plan2" | act5_task_id)"
  if [[ -z "$tid2" || "$tid2" == "$tid" ]]; then
    echo "error: could not parse a distinct second task id" >&2
    exit 1
  fi
  run opaque task revoke "$tid2"
  echo "\$ opaque task run $tid2"
  if opaque task run "$tid2"; then
    echo 'unexpected: a revoked task ran' >&2
    exit 1
  fi
  echo
  echo '(refused: revocation blocks a task that has not run.)'
  echo

  say "List the ledger"
  run opaque task list

  act5_closing "$mode"
}

act5_closing() {
  local mode="$1"
  if [[ "$mode" == "vault" ]]; then
    echo 'What was real here: the manifest digest, the one-shot allowance, the'
    echo 'replay denial, the revoke — and the credential custody. The secret'
    echo 'lived in a real Vault; the broker resolved the reference, and neither'
    echo 'your shell nor the agent ever held the plaintext.'
  else
    echo 'What was real here: the manifest digest, the one-shot allowance, the'
    echo 'replay denial, and the revoke. Both providers were local mocks, so'
    echo 'this run shows the ledger mechanics; the real-custody claim needs the'
    echo 'featured path with a real Vault (install it with "brew install vault").'
  fi
  echo
  echo 'What was not proven, either way: a real GitHub effect. The GitHub'
  echo 'Actions API here is a local mock. From the bounded-work guide:'
  echo
  echo '  "Automated mock-provider and disposable fixtures validate mechanisms;'
  echo '  they do not qualify a live repository'\''s credentials, workflow'
  echo '  protections, artifact, reviewer installation or business outcome.'
  echo '  Qualify those controls for the selected deployment before treating a'
  echo '  successful API response as evidence that the task achieved its goal."'
}

act5_main() {
  say "Act 5 — The mandate"

  need_opaque

  # Act 5 runs in its own isolated throwaway environment with a task-enabled
  # daemon, separate from the shared Acts 1-4 environment. Keep the path short:
  # the daemon's socket lives under data_dir/run and must fit within SUN_LEN.
  ACT5_DIR="$(mktemp -d /private/tmp/harborlight.XXXXXX 2>/dev/null || mktemp -d /tmp/harborlight.XXXXXX)"
  trap harborlight_cleanup EXIT
  export HOME="$ACT5_DIR/home"
  export XDG_RUNTIME_DIR="$ACT5_DIR/xdg"
  mkdir -p "$HOME/.opaque/run" "$XDG_RUNTIME_DIR" "$ACT5_DIR/logs"
  chmod 700 "$HOME" "$XDG_RUNTIME_DIR" >/dev/null 2>&1 || true

  local mode gh_port gh_url vault_url _
  mode="$(act5_vault_mode)"

  # Dummy credentials the daemon resolves by reference. Do NOT replace them.
  export BT_PAT="ghp_demo_bounded_task_pat_0000000000"
  export BT_VAULT_TOKEN="demo-vault-token"

  # The GitHub Actions API is a local mock in both modes.
  # shellcheck disable=SC2016  # banner prints literally
  echo '$ python3 mandate/mock_providers.py &   # local mock GitHub Actions API (dummy values)'
  python3 "$HARBORLIGHT_REPO/mandate/mock_providers.py" \
    >"$ACT5_DIR/mock.port" 2>"$ACT5_DIR/logs/mock.log" &
  ACT5_MOCK_PID=$!
  for _ in $(seq 1 100); do
    gh_port="$(head -1 "$ACT5_DIR/mock.port" 2>/dev/null || true)"
    [[ -n "$gh_port" ]] && break
    sleep 0.05
  done
  if [[ -z "${gh_port:-}" ]]; then
    echo "error: mock provider did not start" >&2
    exit 1
  fi
  gh_url="http://127.0.0.1:$gh_port"
  echo

  if [[ "$mode" == "vault" ]]; then
    act5_start_vault
    vault_url="$ACT5_VAULT_URL"
  else
    if ! command -v vault >/dev/null 2>&1 && [[ "${OPAQUE_QUICKSTART_MOCK:-0}" != "1" ]]; then
      echo 'note: vault is not on PATH. The featured path stands up a real'
      echo 'HashiCorp Vault to prove credential custody; install it with'
      echo '"brew install vault" (see the README). Falling back to the'
      echo 'fully-mocked path, which shows the same ledger mechanics.'
      echo
    fi
    # The mock also serves the Vault KV v2 path in this mode.
    vault_url="$gh_url"
  fi

  act5_write_config
  act5_start_daemon "$gh_url" "$vault_url"
  act5_lifecycle "$mode"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # shellcheck source=acts/_lib.sh
  source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"
  for arg in "$@"; do
    case "$arg" in
      --ci) export OPAQUE_QUICKSTART_CI=1; CI_MODE=1 ;;
      --mock) export OPAQUE_QUICKSTART_MOCK=1 ;;
    esac
  done
  act5_main
fi
