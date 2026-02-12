// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

library PloutosMainnetConfig {
  uint256 internal constant CHAIN_ID = 1;

  // Ploutos Ethereum Mainnet addresses (source: lending-deploy README)
  address internal constant POOL_ADDRESSES_PROVIDER =
    0xdA438F45470B924Bc944aB156406F7868E72C5F3;
  address internal constant POOL = 0x7398e7e3603119D9241E45f688734436Fd7B1540;
  address internal constant INCENTIVES_CONTROLLER =
    0xFEa311150ebc0913B1473545156e7B372d6F6107;

  // ProxyAdmin owner for staticAToken deployment on Ploutos Ethereum Mainnet.
  address internal constant PROXY_ADMIN_OWNER =
    0xfb33205D32Ca482a4d428c23181A9665d4EC02Cc;
}
