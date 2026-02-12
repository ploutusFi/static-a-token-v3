#!/usr/bin/env bash
set -euo pipefail

CHAIN="${CHAIN:-mainnet}"
RPC_URL="${RPC_URL:-mainnet}"
FACTORY_PROXY="${FACTORY_PROXY:-${PLOUTOS_STATIC_A_TOKEN_FACTORY:-}}"
BROADCAST_FILE="${BROADCAST_FILE:-broadcast/Deploy.s.sol/1/run-latest.json}"
OPTIMIZER_RUNS="${OPTIMIZER_RUNS:-1}"
COMPILER_VERSION="${COMPILER_VERSION:-}"
DRY_RUN=0

PROXY_CONTRACT_ID="lib/aave-helpers/lib/solidity-utils/src/contracts/transparent-proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy"

# EIP-1967 slots:
# bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
# bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

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

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

load_dotenv ".env"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd cast
require_cmd forge
require_cmd jq

if [[ -z "$COMPILER_VERSION" ]] && [[ -f out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json ]]; then
  COMPILER_VERSION="$(
    jq -r '.metadata.compiler.version // .compiler.version // empty' out/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json
  )"
fi

if [[ -z "$COMPILER_VERSION" ]]; then
  echo "COMPILER_VERSION is missing and could not be auto-detected from artifacts." >&2
  echo "Run forge build or set COMPILER_VERSION explicitly." >&2
  exit 1
fi

if [[ -z "$FACTORY_PROXY" ]] && [[ -f "$BROADCAST_FILE" ]]; then
  FACTORY_PROXY="$(
    jq -er '[.transactions[] | select(.function == "create(address,address,bytes)") | .additionalContracts[0].address] | last' "$BROADCAST_FILE" 2>/dev/null || true
  )"
fi

if [[ -z "$FACTORY_PROXY" ]]; then
  echo "FACTORY_PROXY is missing." >&2
  echo "Set FACTORY_PROXY or PLOUTOS_STATIC_A_TOKEN_FACTORY in .env." >&2
  echo "Or provide BROADCAST_FILE with a real --broadcast deployment." >&2
  exit 1
fi

if (( ! DRY_RUN )) && [[ -z "${ETHERSCAN_API_KEY_MAINNET:-}" && -z "${ETHERSCAN_API_KEY:-}" ]]; then
  echo "ETHERSCAN_API_KEY_MAINNET (or ETHERSCAN_API_KEY) is missing." >&2
  echo "Set it in .env or environment before re-verification." >&2
  exit 1
fi

run_or_echo() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

slot_to_address() {
  local slot_value="${1#0x}"
  if [[ ${#slot_value} -ne 64 ]]; then
    echo "Invalid storage slot value: $1" >&2
    exit 1
  fi
  cast to-check-sum-address "0x${slot_value:24}"
}

verify_proxy() {
  local proxy="$1"
  local constructor_args="$2"
  local cmd=(
    forge verify-contract
    "$proxy"
    "$PROXY_CONTRACT_ID"
    --constructor-args "$constructor_args"
    --chain "$CHAIN"
    --rpc-url "$RPC_URL"
    --verifier etherscan
    --compiler-version "$COMPILER_VERSION"
    --num-of-optimizations "$OPTIMIZER_RUNS"
    --skip-is-verified-check
    --watch
  )

  if ((DRY_RUN)); then
    run_or_echo "${cmd[@]}"
    return 0
  fi

  local output
  if output="$("${cmd[@]}" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi

  printf '%s\n' "$output" >&2
  if printf '%s\n' "$output" | grep -Eiq 'already verified|already been verified'; then
    echo "  already verified on explorer, skipping: $proxy"
    return 0
  fi

  return 1
}

require_deployed_code() {
  local address="$1"
  local label="$2"
  local code
  code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [[ "$code" == "0x" ]]; then
    echo "$label is not deployed on $CHAIN: $address" >&2
    exit 1
  fi
}

require_deployed_code "$FACTORY_PROXY" "FACTORY_PROXY"

mapfile -t STATA_PROXIES < <(
  cast call "$FACTORY_PROXY" "getStaticATokens()(address[])" --rpc-url "$RPC_URL" |
    grep -Eo '0x[a-fA-F0-9]{40}'
)

if [[ ${#STATA_PROXIES[@]} -eq 0 ]]; then
  echo "No static token proxies returned by factory $FACTORY_PROXY" >&2
  exit 1
fi

FIRST_PROXY="${STATA_PROXIES[0]}"
STATIC_A_TOKEN_IMPL="$(slot_to_address "$(cast storage "$FIRST_PROXY" "$IMPLEMENTATION_SLOT" --rpc-url "$RPC_URL")")"
PROXY_ADMIN="$(slot_to_address "$(cast storage "$FIRST_PROXY" "$ADMIN_SLOT" --rpc-url "$RPC_URL")")"

echo "Re-verification input summary"
echo "  CHAIN: $CHAIN"
echo "  RPC_URL: $RPC_URL"
echo "  FACTORY_PROXY: $FACTORY_PROXY"
echo "  STATIC_A_TOKEN_IMPL (from proxy slot): $STATIC_A_TOKEN_IMPL"
echo "  PROXY_ADMIN (from proxy slot): $PROXY_ADMIN"
echo "  COMPILER_VERSION: $COMPILER_VERSION"
echo "  STATA_PROXY_COUNT: ${#STATA_PROXIES[@]}"

for proxy in "${STATA_PROXIES[@]}"; do
  require_deployed_code "$proxy" "STATA_PROXY"

  current_impl="$(slot_to_address "$(cast storage "$proxy" "$IMPLEMENTATION_SLOT" --rpc-url "$RPC_URL")")"
  current_admin="$(slot_to_address "$(cast storage "$proxy" "$ADMIN_SLOT" --rpc-url "$RPC_URL")")"
  if [[ "$current_impl" != "$STATIC_A_TOKEN_IMPL" ]]; then
    echo "Implementation mismatch for $proxy: $current_impl != $STATIC_A_TOKEN_IMPL" >&2
    exit 1
  fi
  if [[ "$current_admin" != "$PROXY_ADMIN" ]]; then
    echo "Admin mismatch for $proxy: $current_admin != $PROXY_ADMIN" >&2
    exit 1
  fi

  a_token="$(cast call "$proxy" "aToken()(address)" --rpc-url "$RPC_URL")"
  token_name="$(cast call "$proxy" "name()(string)" --rpc-url "$RPC_URL" | jq -r '.')"
  token_symbol="$(cast call "$proxy" "symbol()(string)" --rpc-url "$RPC_URL" | jq -r '.')"

  init_data="$(cast abi-encode "initialize(address,string,string)" "$a_token" "$token_name" "$token_symbol")"
  proxy_ctor="$(cast abi-encode "constructor(address,address,bytes)" "$STATIC_A_TOKEN_IMPL" "$PROXY_ADMIN" "$init_data")"

  echo "  re-verify proxy: $proxy  symbol: $token_symbol  aToken: $a_token"
  verify_proxy "$proxy" "$proxy_ctor"
done

echo "Stata proxy re-verification flow finished."
