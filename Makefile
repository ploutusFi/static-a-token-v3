# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

FORGE_VERBOSITY ?= -v

# deps
update:; forge update

# Build & test
build  :; forge build --sizes

test   :; forge test -vvv

# Deploy
deploy-ledger :; forge script ${contract} --rpc-url ${chain} --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify ${FORGE_VERBOSITY} --slow)
deploy-pk :; forge script ${contract} --rpc-url ${chain} --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --private-key ${PRIVATE_KEY} --verify ${FORGE_VERBOSITY} --slow)
deploy-ploutos-mainnet :; forge script scripts/Deploy.s.sol:DeployMainnet --rpc-url mainnet --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --private-key ${PRIVATE_KEY} --verify ${FORGE_VERBOSITY} --slow)
deploy-ploutos-hemi :; forge script scripts/Deploy.s.sol:DeployHemi --rpc-url hemi --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --private-key ${PRIVATE_KEY} --verify ${FORGE_VERBOSITY} --slow)
deploy-ploutos-mainnet-upgrade :; forge script scripts/DeployUpgrade.s.sol:DeployMainnet --rpc-url mainnet --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --private-key ${PRIVATE_KEY} --verify ${FORGE_VERBOSITY} --slow)
verify-ploutos-mainnet-dry-run :; bash scripts/verify-ploutos-mainnet.sh --dry-run
verify-ploutos-mainnet :; bash scripts/verify-ploutos-mainnet.sh
verify-ploutos-hemi-dry-run :; bash scripts/verify-ploutos-hemi.sh --dry-run
verify-ploutos-hemi :; bash scripts/verify-ploutos-hemi.sh
verify-ploutos-mainnet-proxy-tabs-dry-run :; CHAIN=mainnet CHAIN_ID=1 bash scripts/etherscan-verify-proxies.sh --dry-run
verify-ploutos-mainnet-proxy-tabs :; CHAIN=mainnet CHAIN_ID=1 bash scripts/etherscan-verify-proxies.sh
verify-ploutos-hemi-proxy-tabs-dry-run :; CHAIN=hemi CHAIN_ID=43111 RPC_URL=hemi bash scripts/etherscan-verify-proxies.sh --dry-run
verify-ploutos-hemi-proxy-tabs :; CHAIN=hemi CHAIN_ID=43111 RPC_URL=hemi bash scripts/etherscan-verify-proxies.sh
reverify-ploutos-mainnet-stata-proxies-dry-run :; bash scripts/reverify-stata-proxies-mainnet.sh --dry-run
reverify-ploutos-mainnet-stata-proxies :; bash scripts/reverify-stata-proxies-mainnet.sh
reverify-ploutos-hemi-stata-proxies-dry-run :; bash scripts/reverify-stata-proxies-hemi.sh --dry-run
reverify-ploutos-hemi-stata-proxies :; bash scripts/reverify-stata-proxies-hemi.sh
deploy-ploutos-mainnet-auto-verify :; $(MAKE) deploy-ploutos-mainnet && $(MAKE) verify-ploutos-mainnet && $(MAKE) verify-ploutos-mainnet-proxy-tabs
deploy-ploutos-hemi-auto-verify :; $(MAKE) deploy-ploutos-hemi && $(MAKE) verify-ploutos-hemi && $(MAKE) verify-ploutos-hemi-proxy-tabs

# Utilities
download :; cast etherscan-source --chain ${chain} -d src/etherscan/${chain}_${address} ${address}
git-diff :
	@mkdir -p diffs
	@printf '%s\n%s\n%s\n' "\`\`\`diff" "$$(git diff --no-index --diff-algorithm=patience --ignore-space-at-eol ${before} ${after})" "\`\`\`" > diffs/${out}.md
