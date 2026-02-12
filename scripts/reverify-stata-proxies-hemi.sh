#!/usr/bin/env bash
set -euo pipefail

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

export CHAIN="${CHAIN:-43111}"
export RPC_URL="${RPC_URL:-hemi}"
export BROADCAST_FILE="${BROADCAST_FILE:-broadcast/Deploy.s.sol/43111/run-latest.json}"

if [[ -z "${ETHERSCAN_API_KEY_HEMI:-}" ]]; then
  if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
    export ETHERSCAN_API_KEY_HEMI="$ETHERSCAN_API_KEY"
  else
    # Hemi explorer accepts placeholder-like keys in etherscan-compatible flows.
    export ETHERSCAN_API_KEY_HEMI="abc"
  fi
fi

if [[ -z "${ETHERSCAN_API_KEY_MAINNET:-}" ]]; then
  export ETHERSCAN_API_KEY_MAINNET="$ETHERSCAN_API_KEY_HEMI"
fi

bash scripts/reverify-stata-proxies-mainnet.sh "$@"
