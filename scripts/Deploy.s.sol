// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {PloutosMainnetConfig} from './config/PloutosMainnetConfig.sol';

library DeployATokenFactory {
  struct DeploymentResult {
    address transparentProxyFactory;
    address proxyAdmin;
    address staticATokenImpl;
    address staticATokenFactoryImpl;
    address staticATokenFactoryProxy;
    address staticATokenFactoryProxyImplementation;
    uint256 staticATokenCount;
  }

  function _deploy(
    ITransparentProxyFactory proxyFactory,
    address sharedProxyAdmin,
    IPool pool,
    IRewardsController rewardsController
  ) internal returns (StaticATokenFactory) {
    // Deploy static token implementation.
    StaticATokenLM staticImpl = new StaticATokenLM(pool, rewardsController);

    // Deploy factory implementation.
    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      pool,
      sharedProxyAdmin,
      proxyFactory,
      address(staticImpl)
    );

    // Deploy and initialize factory proxy.
    StaticATokenFactory factory = StaticATokenFactory(
      proxyFactory.create(
        address(factoryImpl),
        sharedProxyAdmin,
        abi.encodeWithSelector(StaticATokenFactory.initialize.selector)
      )
    );

    factory.createStaticATokens(pool.getReservesList());
    return factory;
  }

  function deployPloutosMainnet(
    address proxyAdminOwner
  ) internal returns (DeploymentResult memory result) {
    if (block.chainid != PloutosMainnetConfig.CHAIN_ID) {
      revert('CHAIN_ID_MISMATCH');
    }

    IPool pool = IPool(PloutosMainnetConfig.POOL);
    IRewardsController rewardsController = IRewardsController(
      PloutosMainnetConfig.INCENTIVES_CONTROLLER
    );

    TransparentProxyFactory proxyFactory = new TransparentProxyFactory();
    result.transparentProxyFactory = address(proxyFactory);

    result.proxyAdmin = proxyFactory.createProxyAdmin(proxyAdminOwner);

    StaticATokenLM staticImpl = new StaticATokenLM(pool, rewardsController);
    result.staticATokenImpl = address(staticImpl);

    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      pool,
      result.proxyAdmin,
      ITransparentProxyFactory(result.transparentProxyFactory),
      result.staticATokenImpl
    );
    result.staticATokenFactoryImpl = address(factoryImpl);

    StaticATokenFactory factory = StaticATokenFactory(
      ITransparentProxyFactory(result.transparentProxyFactory).create(
        result.staticATokenFactoryImpl,
        result.proxyAdmin,
        abi.encodeWithSelector(StaticATokenFactory.initialize.selector)
      )
    );
    result.staticATokenFactoryProxy = address(factory);

    result.staticATokenFactoryProxyImplementation = ProxyAdmin(result.proxyAdmin)
      .getProxyImplementation(
        TransparentUpgradeableProxy(payable(result.staticATokenFactoryProxy))
      );

    factory.createStaticATokens(pool.getReservesList());
    result.staticATokenCount = factory.getStaticATokens().length;
  }
}

contract DeployMainnet is Script {
  error ChainIdMismatch(uint256 expected, uint256 actual);

  function run() external returns (DeployATokenFactory.DeploymentResult memory result) {
    if (block.chainid != PloutosMainnetConfig.CHAIN_ID) {
      revert ChainIdMismatch(PloutosMainnetConfig.CHAIN_ID, block.chainid);
    }

    vm.startBroadcast();
    result = DeployATokenFactory.deployPloutosMainnet(PloutosMainnetConfig.PROXY_ADMIN_OWNER);
    vm.stopBroadcast();

    console2.log('Ploutos Ethereum Mainnet deployment completed');
    console2.log('TRANSPARENT_PROXY_FACTORY', result.transparentProxyFactory);
    console2.log('PROXY_ADMIN', result.proxyAdmin);
    console2.log('STATIC_A_TOKEN_IMPL', result.staticATokenImpl);
    console2.log('STATIC_A_TOKEN_FACTORY_IMPL', result.staticATokenFactoryImpl);
    console2.log('STATIC_A_TOKEN_FACTORY_PROXY', result.staticATokenFactoryProxy);
    console2.log(
      'STATIC_A_TOKEN_FACTORY_PROXY_IMPL',
      result.staticATokenFactoryProxyImplementation
    );
    console2.log('STATIC_A_TOKEN_COUNT', result.staticATokenCount);
  }
}
