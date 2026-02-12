#!/usr/bin/env bash
set -euo pipefail

CHAIN="${CHAIN:-mainnet}"
RPC_URL="${RPC_URL:-mainnet}"
BROADCAST_FILE="${BROADCAST_FILE:-broadcast/Deploy.s.sol/1/run-latest.json}"
OPTIMIZER_RUNS="${OPTIMIZER_RUNS:-1}"
DRY_RUN=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd cast
require_cmd forge

if [[ ! -f "$BROADCAST_FILE" ]]; then
  echo "Broadcast file not found: $BROADCAST_FILE" >&2
  echo "Run deployment with --broadcast first." >&2
  exit 1
fi

json_last() {
  jq -er "$1" "$BROADCAST_FILE"
}

run_or_echo() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

require_deployed_code() {
  local address="$1"
  local label="$2"
  local code
  code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [[ "$code" == "0x" ]]; then
    echo "$label is not deployed on $CHAIN: $address" >&2
    echo "Check BROADCAST_FILE. Do not use a dry-run broadcast for verification." >&2
    exit 1
  fi
}

verify_contract() {
  local address="$1"
  local contract_id="$2"
  local constructor_args="${3:-}"

  local cmd=(
    forge verify-contract
    "$address"
    "$contract_id"
    --chain "$CHAIN"
    --rpc-url "$RPC_URL"
    --verifier etherscan
    --num-of-optimizations "$OPTIMIZER_RUNS"
    --watch
  )

  if [[ -n "$constructor_args" ]]; then
    cmd+=(--constructor-args "$constructor_args")
  fi

  run_or_echo "${cmd[@]}"
}

TRANSPARENT_PROXY_FACTORY="$(json_last '[.transactions[] | select(.transactionType == "CREATE" and .contractName == "TransparentProxyFactory") | .contractAddress] | last')"
PROXY_ADMIN="$(json_last '[.transactions[] | select(.function == "createProxyAdmin(address)") | .additionalContracts[0].address] | last')"
STATIC_A_TOKEN_IMPL="$(json_last '[.transactions[] | select(.transactionType == "CREATE" and .contractName == "StaticATokenLM") | .contractAddress] | last')"
STATIC_A_TOKEN_FACTORY_IMPL="$(json_last '[.transactions[] | select(.transactionType == "CREATE" and .contractName == "StaticATokenFactory") | .contractAddress] | last')"
STATIC_A_TOKEN_FACTORY_PROXY="$(json_last '[.transactions[] | select(.function == "create(address,address,bytes)") | .additionalContracts[0].address] | last')"

mapfile -t STATIC_A_TOKEN_PROXIES < <(
  jq -r '
    .transactions[]
    | select(.contractName == "TransparentUpgradeableProxy" and .function == null)
    | .additionalContracts[]?.address
  ' "$BROADCAST_FILE"
)

if [[ ${#STATIC_A_TOKEN_PROXIES[@]} -eq 0 ]]; then
  echo "No static token proxy addresses in broadcast; reading from factory..." >&2
  mapfile -t STATIC_A_TOKEN_PROXIES < <(
    cast call "$STATIC_A_TOKEN_FACTORY_PROXY" "getStaticATokens()(address[])" --rpc-url "$RPC_URL" |
      grep -Eo '0x[a-fA-F0-9]{40}'
  )
fi

if [[ ${#STATIC_A_TOKEN_PROXIES[@]} -eq 0 ]]; then
  echo "No static token proxies found to verify." >&2
  exit 1
fi

echo "Verification input summary"
echo "  CHAIN: $CHAIN"
echo "  RPC_URL: $RPC_URL"
echo "  BROADCAST_FILE: $BROADCAST_FILE"
echo "  TRANSPARENT_PROXY_FACTORY: $TRANSPARENT_PROXY_FACTORY"
echo "  PROXY_ADMIN: $PROXY_ADMIN"
echo "  STATIC_A_TOKEN_IMPL: $STATIC_A_TOKEN_IMPL"
echo "  STATIC_A_TOKEN_FACTORY_IMPL: $STATIC_A_TOKEN_FACTORY_IMPL"
echo "  STATIC_A_TOKEN_FACTORY_PROXY: $STATIC_A_TOKEN_FACTORY_PROXY"
echo "  STATIC_A_TOKEN_PROXY_COUNT: ${#STATIC_A_TOKEN_PROXIES[@]}"

require_deployed_code "$STATIC_A_TOKEN_IMPL" "STATIC_A_TOKEN_IMPL"
require_deployed_code "$STATIC_A_TOKEN_FACTORY_IMPL" "STATIC_A_TOKEN_FACTORY_IMPL"
require_deployed_code "$STATIC_A_TOKEN_FACTORY_PROXY" "STATIC_A_TOKEN_FACTORY_PROXY"

POOL="$(cast call "$STATIC_A_TOKEN_IMPL" "POOL()(address)" --rpc-url "$RPC_URL")"
INCENTIVES_CONTROLLER="$(cast call "$STATIC_A_TOKEN_IMPL" "INCENTIVES_CONTROLLER()(address)" --rpc-url "$RPC_URL")"

STATIC_IMPL_CTOR="$(cast abi-encode "constructor(address,address)" "$POOL" "$INCENTIVES_CONTROLLER")"
FACTORY_IMPL_CTOR="$(cast abi-encode "constructor(address,address,address,address)" "$POOL" "$PROXY_ADMIN" "$TRANSPARENT_PROXY_FACTORY" "$STATIC_A_TOKEN_IMPL")"
FACTORY_PROXY_CTOR="$(cast abi-encode "constructor(address,address,bytes)" "$STATIC_A_TOKEN_FACTORY_IMPL" "$PROXY_ADMIN" 0x8129fc1c)"

echo "Verifying core contracts..."
verify_contract "$TRANSPARENT_PROXY_FACTORY" "solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol:TransparentProxyFactory"
verify_contract "$PROXY_ADMIN" "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol:ProxyAdmin"
verify_contract "$STATIC_A_TOKEN_IMPL" "src/StaticATokenLM.sol:StaticATokenLM" "$STATIC_IMPL_CTOR"
verify_contract "$STATIC_A_TOKEN_FACTORY_IMPL" "src/StaticATokenFactory.sol:StaticATokenFactory" "$FACTORY_IMPL_CTOR"
verify_contract "$STATIC_A_TOKEN_FACTORY_PROXY" "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy" "$FACTORY_PROXY_CTOR"

echo "Verifying static token proxies..."
for proxy in "${STATIC_A_TOKEN_PROXIES[@]}"; do
  a_token="$(cast call "$proxy" "aToken()(address)" --rpc-url "$RPC_URL")"
  token_name="$(cast call "$proxy" "name()(string)" --rpc-url "$RPC_URL" | jq -r '.')"
  token_symbol="$(cast call "$proxy" "symbol()(string)" --rpc-url "$RPC_URL" | jq -r '.')"

  init_data="$(cast abi-encode "initialize(address,string,string)" "$a_token" "$token_name" "$token_symbol")"
  proxy_ctor="$(cast abi-encode "constructor(address,address,bytes)" "$STATIC_A_TOKEN_IMPL" "$PROXY_ADMIN" "$init_data")"

  echo "  proxy: $proxy  symbol: $token_symbol  aToken: $a_token"
  verify_contract "$proxy" "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy" "$proxy_ctor"
done

echo "Automatic verification flow finished."
