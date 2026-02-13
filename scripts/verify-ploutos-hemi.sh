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

ensure_etherscan_keys_defaults() {
  local keys=(
    ETHERSCAN_API_KEY_MAINNET
    ETHERSCAN_API_KEY_OPTIMISM
    ETHERSCAN_API_KEY_AVALANCHE
    ETHERSCAN_API_KEY_POLYGON
    ETHERSCAN_API_KEY_ARBITRUM
    ETHERSCAN_API_KEY_FANTOM
    ETHERSCAN_API_KEY_BASE
    ETHERSCAN_API_KEY_ZKEVM
    ETHERSCAN_API_KEY_GNOSIS
    ETHERSCAN_API_KEY_BNB
    ETHERSCAN_API_KEY_SCROLL
  )

  for key in "${keys[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      export "$key=abc"
    fi
  done
}

ensure_etherscan_keys_defaults

export CHAIN="${CHAIN:-43111}"
export RPC_URL="${RPC_URL:-hemi}"
export BROADCAST_FILE="${BROADCAST_FILE:-broadcast/Deploy.s.sol/43111/run-latest.json}"

if [[ -z "${ETHERSCAN_API_KEY_HEMI:-}" ]]; then
  if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
    export ETHERSCAN_API_KEY_HEMI="$ETHERSCAN_API_KEY"
  else
    export ETHERSCAN_API_KEY_HEMI="abc"
  fi
fi

if [[ -z "${ETHERSCAN_API_KEY_MAINNET:-}" ]]; then
  export ETHERSCAN_API_KEY_MAINNET="$ETHERSCAN_API_KEY_HEMI"
fi

export VERIFIER="${VERIFIER:-custom}"
export VERIFIER_URL="${VERIFIER_URL:-https://explorer.hemi.xyz/api}"
export VERIFIER_API_KEY="${VERIFIER_API_KEY:-$ETHERSCAN_API_KEY_HEMI}"

bash scripts/verify-ploutos-mainnet.sh "$@"
