#!/usr/bin/env bash
set -euo pipefail

TARGET_CHAIN="${CHAIN:-mainnet}"
CHAIN_ID="${CHAIN_ID:-}"
RPC_URL="${RPC_URL:-$TARGET_CHAIN}"
FACTORY_PROXY="${FACTORY_PROXY:-${PLOUTOS_STATIC_A_TOKEN_FACTORY:-}}"
BROADCAST_FILE="${BROADCAST_FILE:-broadcast/Deploy.s.sol/1/run-latest.json}"
INCLUDE_FACTORY_PROXY="${INCLUDE_FACTORY_PROXY:-1}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-20}"
POLL_SLEEP_SECONDS="${POLL_SLEEP_SECONDS:-3}"
ETHERSCAN_API_BASE_URL="${ETHERSCAN_API_BASE_URL:-}"
DRY_RUN=0

# EIP-1967 implementation slot
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

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
require_cmd curl
require_cmd jq

resolve_chain_id() {
  case "$1" in
    1|mainnet|ethereum|eth) echo "1" ;;
    10|optimism|op) echo "10" ;;
    42161|arbitrum|arb) echo "42161" ;;
    137|polygon|matic) echo "137" ;;
    43114|avalanche|avax) echo "43114" ;;
    8453|base) echo "8453" ;;
    534352|scroll) echo "534352" ;;
    56|bnb|bsc) echo "56" ;;
    100|gnosis|xdai) echo "100" ;;
    1088|metis) echo "1088" ;;
    1101|zkevm|polygonzkevm) echo "1101" ;;
    250|fantom|ftm) echo "250" ;;
    43111|hemi|hemi-mainnet) echo "43111" ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "$1"
      else
        echo ""
      fi
      ;;
  esac
}

resolve_api_key() {
  local chain_id="$1"
  if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
    echo "$ETHERSCAN_API_KEY"
    return
  fi

  case "$chain_id" in
    1) echo "${ETHERSCAN_API_KEY_MAINNET:-}" ;;
    10) echo "${ETHERSCAN_API_KEY_OPTIMISM:-}" ;;
    42161) echo "${ETHERSCAN_API_KEY_ARBITRUM:-}" ;;
    137) echo "${ETHERSCAN_API_KEY_POLYGON:-}" ;;
    43114) echo "${ETHERSCAN_API_KEY_AVALANCHE:-}" ;;
    8453) echo "${ETHERSCAN_API_KEY_BASE:-}" ;;
    534352) echo "${ETHERSCAN_API_KEY_SCROLL:-}" ;;
    56) echo "${ETHERSCAN_API_KEY_BNB:-}" ;;
    100) echo "${ETHERSCAN_API_KEY_GNOSIS:-}" ;;
    1101) echo "${ETHERSCAN_API_KEY_ZKEVM:-}" ;;
    250) echo "${ETHERSCAN_API_KEY_FANTOM:-}" ;;
    43111) echo "${ETHERSCAN_API_KEY_HEMI:-abc}" ;;
    *) echo "" ;;
  esac
}

resolve_api_base() {
  local chain_id="$1"
  case "$chain_id" in
    43111) echo "https://explorer.hemi.xyz/api" ;;
    *) echo "https://api.etherscan.io/v2/api" ;;
  esac
}

requires_chainid_param() {
  local chain_id="$1"
  case "$chain_id" in
    43111) echo "0" ;;
    *) echo "1" ;;
  esac
}

run_or_echo() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_deployed_code() {
  local address="$1"
  local label="$2"
  local code
  code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [[ "$code" == "0x" ]]; then
    echo "$label is not deployed on CHAIN_ID=$CHAIN_ID: $address" >&2
    exit 1
  fi
}

submit_verify_proxy() {
  local proxy="$1"
  local implementation="$2"
  local output

  if ((DRY_RUN)); then
    echo "DRY-RUN: verifyproxycontract address=$proxy expectedimplementation=$implementation" >&2
    echo "DRY_RUN_GUID"
    return 0
  fi

  local -a curl_args=(
    --request POST
    --url "$ETHERSCAN_API_BASE_URL"
    --data-urlencode "module=contract"
    --data-urlencode "action=verifyproxycontract"
    --data-urlencode "address=$proxy"
    --data-urlencode "expectedimplementation=$implementation"
    --data-urlencode "apikey=$ETHERSCAN_API_KEY_RESOLVED"
  )

  if [[ "$USE_CHAIN_ID_PARAM" == "1" ]]; then
    curl_args+=(--data-urlencode "chainid=$CHAIN_ID")
  fi

  output="$(curl -s "${curl_args[@]}")"

  local status message result
  status="$(jq -r '.status // ""' <<< "$output")"
  message="$(jq -r '.message // ""' <<< "$output")"
  result="$(jq -r '.result // ""' <<< "$output")"

  if [[ "$status" == "1" ]]; then
    echo "$result"
    return 0
  fi

  if [[ "$message" =~ [Aa]lready ]] || [[ "$result" =~ [Aa]lready ]]; then
    echo "ALREADY_VERIFIED"
    return 0
  fi

  echo "verifyproxycontract failed for $proxy: $output" >&2
  return 1
}

poll_verify_proxy() {
  local guid="$1"
  local proxy="$2"

  if ((DRY_RUN)); then
    echo "DRY-RUN: checkproxyverification guid=$guid"
    return 0
  fi

  if [[ "$guid" == "ALREADY_VERIFIED" ]]; then
    return 0
  fi

  for ((i = 1; i <= POLL_ATTEMPTS; i++)); do
    local output status result
    local -a curl_args=(
      -G
      "$ETHERSCAN_API_BASE_URL"
      --data-urlencode "module=contract"
      --data-urlencode "action=checkproxyverification"
      --data-urlencode "guid=$guid"
      --data-urlencode "apikey=$ETHERSCAN_API_KEY_RESOLVED"
    )

    if [[ "$USE_CHAIN_ID_PARAM" == "1" ]]; then
      curl_args+=(--data-urlencode "chainid=$CHAIN_ID")
    fi

    output="$(curl -s "${curl_args[@]}")"
    status="$(jq -r '.status // ""' <<< "$output")"
    result="$(jq -r '.result // ""' <<< "$output")"

    if [[ "$status" == "1" ]]; then
      echo "$result"
      return 0
    fi

    if [[ "$result" =~ [Pp]ending|[Qq]ueue|In\ Progress ]]; then
      sleep "$POLL_SLEEP_SECONDS"
      continue
    fi

    if [[ "$result" =~ [Aa]lready ]]; then
      return 0
    fi

    echo "checkproxyverification failed for $proxy: $output" >&2
    return 1
  done

  echo "checkproxyverification timeout for $proxy (guid=$guid)" >&2
  return 1
}

check_proxy_flag() {
  local proxy="$1"

  if ((DRY_RUN)); then
    echo "DRY-RUN: getsourcecode address=$proxy"
    return 0
  fi

  local output proxy_flag impl
  local -a curl_args=(
    -G
    "$ETHERSCAN_API_BASE_URL"
    --data-urlencode "module=contract"
    --data-urlencode "action=getsourcecode"
    --data-urlencode "address=$proxy"
    --data-urlencode "apikey=$ETHERSCAN_API_KEY_RESOLVED"
  )

  if [[ "$USE_CHAIN_ID_PARAM" == "1" ]]; then
    curl_args+=(--data-urlencode "chainid=$CHAIN_ID")
  fi

  output="$(curl -s "${curl_args[@]}")"
  proxy_flag="$(jq -r '.result[0].Proxy // ""' <<< "$output")"
  impl="$(jq -r '.result[0].Implementation // ""' <<< "$output")"
  echo "    Proxy flag: $proxy_flag  Implementation: $impl"
}

if [[ -z "$CHAIN_ID" ]]; then
  CHAIN_ID="$(resolve_chain_id "$TARGET_CHAIN")"
fi

if [[ -z "$CHAIN_ID" ]]; then
  echo "CHAIN_ID is missing and CHAIN='$TARGET_CHAIN' is not recognized." >&2
  exit 1
fi

# Avoid leaking CHAIN env var into cast/forge argument parsing on non-standard names (e.g. hemi).
unset CHAIN || true

if [[ -z "$ETHERSCAN_API_BASE_URL" ]]; then
  ETHERSCAN_API_BASE_URL="$(resolve_api_base "$CHAIN_ID")"
fi
USE_CHAIN_ID_PARAM="$(requires_chainid_param "$CHAIN_ID")"

if [[ -z "$FACTORY_PROXY" ]] && [[ -f "$BROADCAST_FILE" ]]; then
  FACTORY_PROXY="$(
    jq -er '[.transactions[] | select(.function == "create(address,address,bytes)") | .additionalContracts[0].address] | last' "$BROADCAST_FILE" 2>/dev/null || true
  )"
fi

if [[ -z "$FACTORY_PROXY" ]]; then
  echo "FACTORY_PROXY is missing." >&2
  echo "Set FACTORY_PROXY/PLOUTOS_STATIC_A_TOKEN_FACTORY or provide BROADCAST_FILE." >&2
  exit 1
fi

ETHERSCAN_API_KEY_RESOLVED="$(resolve_api_key "$CHAIN_ID")"
if (( ! DRY_RUN )) && [[ -z "$ETHERSCAN_API_KEY_RESOLVED" ]]; then
  echo "Etherscan API key is missing for CHAIN_ID=$CHAIN_ID." >&2
  echo "Set ETHERSCAN_API_KEY or chain-specific key in .env." >&2
  exit 1
fi

require_deployed_code "$FACTORY_PROXY" "FACTORY_PROXY"

declare -a proxies
if [[ "$INCLUDE_FACTORY_PROXY" == "1" ]]; then
  proxies+=("$FACTORY_PROXY")
fi

mapfile -t stata_proxies < <(
  cast call "$FACTORY_PROXY" "getStaticATokens()(address[])" --rpc-url "$RPC_URL" |
    grep -Eo '0x[a-fA-F0-9]{40}'
)
proxies+=("${stata_proxies[@]}")

if [[ ${#proxies[@]} -eq 0 ]]; then
  echo "No proxies to process." >&2
  exit 1
fi

declare -A seen
declare -a unique_proxies
for p in "${proxies[@]}"; do
  local_key="$(tr '[:upper:]' '[:lower:]' <<< "$p")"
  if [[ -z "${seen[$local_key]:-}" ]]; then
    seen["$local_key"]=1
    unique_proxies+=("$p")
  fi
done

echo "Etherscan proxy verification summary"
echo "  CHAIN: $TARGET_CHAIN"
echo "  CHAIN_ID: $CHAIN_ID"
echo "  RPC_URL: $RPC_URL"
echo "  FACTORY_PROXY: $FACTORY_PROXY"
echo "  EXPLORER_API: $ETHERSCAN_API_BASE_URL"
echo "  PROXY_COUNT: ${#unique_proxies[@]}"

for proxy in "${unique_proxies[@]}"; do
  require_deployed_code "$proxy" "PROXY"

  impl_slot_value="$(cast storage "$proxy" "$IMPLEMENTATION_SLOT" --rpc-url "$RPC_URL")"
  impl="0x${impl_slot_value:26}"
  impl="$(cast to-check-sum-address "$impl")"

  echo "  verify proxy: $proxy"
  echo "    expected implementation: $impl"

  guid="$(submit_verify_proxy "$proxy" "$impl")"
  poll_verify_proxy "$guid" "$proxy"
  check_proxy_flag "$proxy"
done

echo "Proxy verification flow finished."
