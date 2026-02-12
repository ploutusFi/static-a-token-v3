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
deploy-ploutos-mainnet-upgrade :; forge script scripts/DeployUpgrade.s.sol:DeployMainnet --rpc-url mainnet --optimizer-runs 1 $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 ${FORGE_VERBOSITY},--broadcast --private-key ${PRIVATE_KEY} --verify ${FORGE_VERBOSITY} --slow)
verify-ploutos-mainnet-dry-run :; bash scripts/verify-ploutos-mainnet.sh --dry-run
verify-ploutos-mainnet :; bash scripts/verify-ploutos-mainnet.sh
reverify-ploutos-mainnet-stata-proxies-dry-run :; bash scripts/reverify-stata-proxies-mainnet.sh --dry-run
reverify-ploutos-mainnet-stata-proxies :; bash scripts/reverify-stata-proxies-mainnet.sh
deploy-ploutos-mainnet-auto-verify :; $(MAKE) deploy-ploutos-mainnet && $(MAKE) verify-ploutos-mainnet

# Utilities
download :; cast etherscan-source --chain ${chain} -d src/etherscan/${chain}_${address} ${address}
git-diff :
	@mkdir -p diffs
	@printf '%s\n%s\n%s\n' "\`\`\`diff" "$$(git diff --no-index --diff-algorithm=patience --ignore-space-at-eol ${before} ${after})" "\`\`\`" > diffs/${out}.md
