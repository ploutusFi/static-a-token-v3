// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

library PloutosHemiConfig {
  uint256 internal constant CHAIN_ID = 43111;

  // Ploutos Hemi Mainnet addresses (source: lending-deploy README)
  address internal constant POOL_ADDRESSES_PROVIDER =
    0xA4753a119B2272047bef65850898eb603283Aae9;
  address internal constant POOL = 0xDdc98fF53945e334Ecca339b4DD8847b3769e8f0;
  address internal constant INCENTIVES_CONTROLLER =
    0x14D64D857EBDb2B4C51d5c83452cb624Acc47c2E;

  // ProxyAdmin owner for staticAToken deployment on Ploutos Hemi Mainnet.
  address internal constant PROXY_ADMIN_OWNER =
    0xfb33205D32Ca482a4d428c23181A9665d4EC02Cc;
}
