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
make deploy-ploutos-mainnet dry=1
```

Broadcast deploy (`forge script --verify`):

```sh
make deploy-ploutos-mainnet
```

Automatic verification for all proxy-created contracts (`ProxyAdmin`, factory proxy, all static token proxies):

```sh
make verify-ploutos-mainnet
```

One-shot deploy + full auto verification:

```sh
make deploy-ploutos-mainnet-auto-verify
```

NPM alternatives:

```sh
npm run verify:ploutos:mainnet
npm run deploy:ploutos:mainnet:auto-verify
```

If some static token proxies appear as `Similar Match`, run targeted re-verification:

```sh
make reverify-ploutos-mainnet-stata-proxies
npm run reverify:ploutos:mainnet:stata-proxies
```

### Ploutos Ethereum Mainnet Upgrade Payload

For upgrade payload deployment, set `PLOUTOS_STATIC_A_TOKEN_FACTORY` in `.env`, then run:

```sh
make deploy-pk contract=scripts/DeployUpgrade.s.sol:DeployMainnet chain=mainnet
```

# Ploutos Deployments
## Mainnet
```
  createStaticATokens completed
    Total staticATokens in factory 5
    underlying 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    underlying symbol WETH
    staticAToken 0x29a50bfa7e3F1043D0dE40E03C60289FD8aC26Bd
    underlying 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    underlying symbol WBTC
    staticAToken 0xc0F63947638b32d3B26e06Bdb161D217A8f62428
    underlying 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    underlying symbol USDC
    staticAToken 0x76ED952b16e5b02629A8d40f73F9364134030270
    underlying 0xdAC17F958D2ee523a2206206994597C13D831ec7
    underlying symbol USDT
    staticAToken 0x070313a96f757f449f49a90aA38cdDe8AaD64711
    underlying 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3
    underlying symbol USDe
    staticAToken 0x63524D3d71341f74875835eFd72447541cCE833c
  Ploutos Ethereum Mainnet deployment completed
  TRANSPARENT_PROXY_FACTORY 0x636B19cC688b1e670AFd71B0da83fc32DC77D483 +
  PROXY_ADMIN 0x92dE4BFcAe819E0a8F9d3C22D1daD5cE09114e7C +
  STATIC_A_TOKEN_IMPL 0x92ba74a2b130a7267e3B4e7b11b0E8b6884b56fD
  STATIC_A_TOKEN_FACTORY_IMPL 0xb65cbcfC429eaFd08A77df9f0279E312531B72cb
  STATIC_A_TOKEN_FACTORY_PROXY 0x6bdb25661623596552d2EF0A76892E700B2243a9
  STATIC_A_TOKEN_FACTORY_PROXY_IMPL 0xb65cbcfC429eaFd08A77df9f0279E312531B72cb
  STATIC_A_TOKEN_COUNT 5
```
