#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-broadcast}"

load_dotenv() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="${raw%$'\r'}"
    [[ -z "$raw" ]] && continue
    [[ "${raw:0:1}" == "#" ]] && continue
    [[ "$raw" != *=* ]] && continue

    if [[ "${raw:0:7}" == "export " ]]; then
      raw="${raw:7}"
    fi

    local key="${raw%%=*}"
    local value="${raw#*=}"

    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -z "$key" ]] && continue

    export "$key=$value"
  done < "$env_file"
}

load_dotenv ".env"

if [[ "$MODE" == "dry-run" ]]; then
  forge script scripts/Deploy.s.sol:DeployMainnet \
    --rpc-url mainnet \
    --sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 \
    -v \
    --optimizer-runs 1
  exit 0
fi

if [[ "$MODE" != "broadcast" ]]; then
  echo "Unsupported mode: $MODE (expected: dry-run | broadcast)" >&2
  exit 1
fi

: "${PRIVATE_KEY:?PRIVATE_KEY is missing. Set it in .env or environment.}"

forge script scripts/Deploy.s.sol:DeployMainnet \
  --rpc-url mainnet \
  --broadcast \
  --private-key "$PRIVATE_KEY" \
  --verify \
  -v \
  --slow \
  --optimizer-runs 1
