// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {UpgradePayload} from '../src/UpgradePayload.sol';
import {PloutosMainnetConfig} from './config/PloutosMainnetConfig.sol';

library DeployUpgrade {
  function _deploy(
    StaticATokenFactory staticATokenFactory,
    IPool pool,
    IRewardsController rewardsController
  ) internal returns (UpgradePayload) {
    ITransparentProxyFactory proxyFactory = staticATokenFactory.TRANSPARENT_PROXY_FACTORY();
    address sharedProxyAdmin = staticATokenFactory.ADMIN();

    StaticATokenLM staticImpl = new StaticATokenLM(pool, rewardsController);

    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      pool,
      sharedProxyAdmin,
      proxyFactory,
      address(staticImpl)
    );

    return
      new UpgradePayload(
        sharedProxyAdmin,
        staticATokenFactory,
        factoryImpl,
        address(staticImpl)
      );
  }

  function deployMainnet(
    address staticATokenFactoryAddress
  ) internal returns (UpgradePayload) {
    return
      _deploy(
        StaticATokenFactory(staticATokenFactoryAddress),
        IPool(PloutosMainnetConfig.POOL),
        IRewardsController(PloutosMainnetConfig.INCENTIVES_CONTROLLER)
      );
  }

  // Backward-compatible signature used by existing tests/helpers.
  function deployMainnet() internal pure returns (UpgradePayload) {
    revert('STATIC_A_TOKEN_FACTORY_ADDRESS_REQUIRED');
  }

  // Kept for backward compatibility with older test helpers/import sites.
  function deployPolygon() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployAvalanche() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployOptimism() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployArbitrum() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployMetis() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployBNB() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployScroll() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployBase() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }

  function deployGnosis() internal pure returns (UpgradePayload) {
    revert('UNSUPPORTED_NETWORK');
  }
}

contract DeployMainnet is Script {
  error ChainIdMismatch(uint256 expected, uint256 actual);

  function run() external returns (UpgradePayload payload) {
    if (block.chainid != PloutosMainnetConfig.CHAIN_ID) {
      revert ChainIdMismatch(PloutosMainnetConfig.CHAIN_ID, block.chainid);
    }

    address staticATokenFactory = vm.envAddress('PLOUTOS_STATIC_A_TOKEN_FACTORY');

    vm.startBroadcast();
    payload = DeployUpgrade.deployMainnet(staticATokenFactory);
    vm.stopBroadcast();

    console2.log('Ploutos Ethereum Mainnet upgrade payload deployed');
    console2.log('STATIC_A_TOKEN_FACTORY', staticATokenFactory);
    console2.log('UPGRADE_PAYLOAD', address(payload));
    console2.log('NEW_FACTORY_IMPLEMENTATION', address(payload.NEW_FACTORY_IMPLEMENTATION()));
    console2.log('NEW_TOKEN_IMPLEMENTATION', payload.NEW_TOKEN_IMPLEMENTATION());
  }
}
