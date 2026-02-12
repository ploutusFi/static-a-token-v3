# stataToken - Static aToken vault/wrapper

Project has been moved to [Aave V3 Origin](https://github.com/aave-dao/aave-v3-origin/tree/main/src/periphery/contracts/static-a-token);

## Disclaimer

<p align="center">
<img src="./wrapping.jpg" width="300">
</p>

## About

This repository contains an [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) generic token vault/wrapper for all [Aave v3](https://github.com/aave/aave-v3-core) pools.

## Features

- **Full [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) compatibility.**
- **Accounting for any potential liquidity mining rewards.** Let’s say some team of the Aave ecosystem (or the Aave community itself) decides to incentivize deposits of USDC on Aave v3 Ethereum. By holding `stataUSDC`, the user will still be eligible for those incentives.
  It is important to highlight that while currently the wrapper supports infinite reward tokens by design (e.g. AAVE incentivizing stETH & Lido incentivizing stETH as well), each reward needs to be permissionlessly registered which bears some [⁽¹⁾](#limitations).
- **Meta-transactions support.** To enable interfaces to offer gas-less transactions to deposit/withdraw on the wrapper/Aave protocol (also supported on Aave v3). Including permit() for transfers of the `stataAToken` itself.
- **Upgradable by the Aave governance.** Similar to other contracts of the Aave ecosystem, the Level 1 executor (short executor) will be able to add new features to the deployed instances of the `stataTokens`.
- **Powered by a stataToken Factory.** Whenever a token will be listed on Aave v3, anybody will be able to call the stataToken Factory to deploy an instance for the new asset, permissionless, but still assuring the code used and permissions are properly configured without any extra headache.

See [IStaticATokenLM.sol](./src/interfaces/IStaticATokenLM.sol) for detailed method documentation.

## Deployed Addresses

The staticATokenFactory is deployed for all major Aave v3 pools.
An up to date address can be fetched from the respective [address-book pool library](https://github.com/bgd-labs/aave-address-book/blob/main/src/AaveV3Ethereum.sol#L67).

## Limitations

The `stataToken` is not natively integrated into the aave protocol and therefore cannot hook into the emissionManager.
This means a `reward` added **after** `statToken` creation needs to be registered manually on the token via the permissionless `refreshRewardTokens()` method.
As this process is not currently automated users might be missing out on rewards until the method is called.

## Security procedures

For this project, the security procedures applied/being finished are:

- The test suite of the codebase itself.
- Certora [audit/property checking](./audits/Formal_Verification_Report_staticAToken.pdf) for all the dynamics of the `stataToken`, including respecting all the specs of [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626).
- Certora [manual review of static aToken oracle](./audits/Certora-Review-StatAToken-Oracle.pdf)

## Development

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for detailed instructions on how to install and use Foundry.
The template ships with sensible default so you can use default `foundry` commands without resorting to `MakeFile`.

### Setup

```sh
cp .env.example .env
forge install
```

### Test

```sh
forge test
```

### Ploutos Ethereum Mainnet Deployment

`scripts/config/PloutosMainnetConfig.sol` is the source of truth for on-chain config:

- `POOL`: `0x7398e7e3603119D9241E45f688734436Fd7B1540`
- `INCENTIVES_CONTROLLER`: `0xFEa311150ebc0913B1473545156e7B372d6F6107`
- `PROXY_ADMIN_OWNER`: `0xfb33205d32ca482a4d428c23181a9665d4ec02cc`

The deployment script `scripts/Deploy.s.sol:DeployMainnet` performs:

1. Deploy `TransparentProxyFactory`
2. Create `ProxyAdmin` with `PROXY_ADMIN_OWNER`
3. Deploy `StaticATokenLM` implementation
4. Deploy `StaticATokenFactory` implementation + proxy
5. Create staticATokens for `POOL.getReservesList()`

Dry-run (no broadcast):

```sh
make deploy-pk contract=scripts/Deploy.s.sol:DeployMainnet chain=mainnet dry=1
```

Broadcast + verify:

```sh
make deploy-pk contract=scripts/Deploy.s.sol:DeployMainnet chain=mainnet
```

### Manual Verification (Proxy-Created Contracts)

If auto-verify misses contracts created by `TransparentProxyFactory`, verify manually:

```sh
forge verify-contract <PROXY_ADMIN> \
  solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol:ProxyAdmin \
  --chain mainnet --etherscan-api-key $ETHERSCAN_API_KEY_MAINNET

forge verify-contract <FACTORY_PROXY> \
  solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
  --constructor-args $(cast abi-encode "constructor(address,address,bytes)" <FACTORY_IMPL> <PROXY_ADMIN> 0x8129fc1c) \
  --chain mainnet --etherscan-api-key $ETHERSCAN_API_KEY_MAINNET
```

### Ploutos Ethereum Mainnet Upgrade Payload

For upgrade payload deployment, set `PLOUTOS_STATIC_A_TOKEN_FACTORY` in `.env`, then run:

```sh
make deploy-pk contract=scripts/DeployUpgrade.s.sol:DeployMainnet chain=mainnet
```
