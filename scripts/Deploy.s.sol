// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {DataTypes} from 'aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {PloutosMainnetConfig} from './config/PloutosMainnetConfig.sol';
import {PloutosHemiConfig} from './config/PloutosHemiConfig.sol';

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

  function _readSymbol(address token) internal view returns (string memory) {
    try IERC20Metadata(token).symbol() returns (string memory symbol) {
      return symbol;
    } catch {
      return 'UNKNOWN';
    }
  }

  function _logReservePlanItem(
    IPool pool,
    ITransparentProxyFactory proxyFactory,
    address staticATokenImpl,
    address proxyAdmin,
    address underlying,
    uint256 index
  ) internal view {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(underlying);
    address aToken = reserveData.aTokenAddress;
    string memory underlyingSymbol = _readSymbol(underlying);

    string memory staticATokenName = string(
      abi.encodePacked('Static ', IERC20Metadata(aToken).name())
    );
    string memory staticATokenSymbol = string(
      abi.encodePacked('stat', IERC20Metadata(aToken).symbol())
    );
    bytes memory initData = abi.encodeWithSelector(
      StaticATokenLM.initialize.selector,
      aToken,
      staticATokenName,
      staticATokenSymbol
    );
    bytes32 salt = bytes32(uint256(uint160(underlying)));
    address predictedStaticAToken = proxyFactory.predictCreateDeterministic(
      staticATokenImpl,
      proxyAdmin,
      initData,
      salt
    );

    console2.log('Reserve index', index);
    console2.log('  Underlying', underlying);
    console2.log('  Underlying symbol', underlyingSymbol);
    console2.log('  aToken', aToken);
    console2.log('  Static symbol', staticATokenSymbol);
    console2.log('  Salt');
    console2.logBytes32(salt);
    console2.log('  Predicted staticAToken', predictedStaticAToken);
  }

  function _logReservePlan(
    IPool pool,
    ITransparentProxyFactory proxyFactory,
    address staticATokenImpl,
    address proxyAdmin,
    address[] memory underlyings
  ) internal view {
    console2.log('Reserves to wrap:', underlyings.length);
    for (uint256 i = 0; i < underlyings.length; i++) {
      _logReservePlanItem(pool, proxyFactory, staticATokenImpl, proxyAdmin, underlyings[i], i);
    }
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
    address[] memory reserves = pool.getReservesList();

    console2.log('Deploy config');
    console2.log('  Chain ID', block.chainid);
    console2.log('  Pool', address(pool));
    console2.log('  Incentives', address(rewardsController));
    console2.log('  ProxyAdmin owner', proxyAdminOwner);
    console2.log('  Reserves count', reserves.length);

    console2.log('Step 1/6: Deploy TransparentProxyFactory');
    TransparentProxyFactory proxyFactory = new TransparentProxyFactory();
    result.transparentProxyFactory = address(proxyFactory);
    console2.log('  TransparentProxyFactory', result.transparentProxyFactory);

    console2.log('Step 2/6: Create ProxyAdmin');
    result.proxyAdmin = proxyFactory.createProxyAdmin(proxyAdminOwner);
    console2.log('  ProxyAdmin', result.proxyAdmin);
    console2.log('  ProxyAdmin owner (on-chain)', ProxyAdmin(result.proxyAdmin).owner());

    console2.log('Step 3/6: Deploy StaticATokenLM implementation');
    StaticATokenLM staticImpl = new StaticATokenLM(pool, rewardsController);
    result.staticATokenImpl = address(staticImpl);
    console2.log('  StaticATokenLM implementation', result.staticATokenImpl);

    console2.log('Step 4/6: Deploy StaticATokenFactory implementation');
    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      pool,
      result.proxyAdmin,
      ITransparentProxyFactory(result.transparentProxyFactory),
      result.staticATokenImpl
    );
    result.staticATokenFactoryImpl = address(factoryImpl);
    console2.log('  StaticATokenFactory implementation', result.staticATokenFactoryImpl);

    console2.log('Step 5/6: Deploy StaticATokenFactory proxy');
    StaticATokenFactory factory = StaticATokenFactory(
      ITransparentProxyFactory(result.transparentProxyFactory).create(
        result.staticATokenFactoryImpl,
        result.proxyAdmin,
        abi.encodeWithSelector(StaticATokenFactory.initialize.selector)
      )
    );
    result.staticATokenFactoryProxy = address(factory);
    console2.log('  StaticATokenFactory proxy', result.staticATokenFactoryProxy);

    result.staticATokenFactoryProxyImplementation = ProxyAdmin(result.proxyAdmin)
      .getProxyImplementation(
        TransparentUpgradeableProxy(payable(result.staticATokenFactoryProxy))
      );
    console2.log(
      '  StaticATokenFactory proxy impl (read via ProxyAdmin)',
      result.staticATokenFactoryProxyImplementation
    );

    console2.log('Step 6/6: createStaticATokens(pool.getReservesList())');
    _logReservePlan(
      pool,
      ITransparentProxyFactory(result.transparentProxyFactory),
      result.staticATokenImpl,
      result.proxyAdmin,
      reserves
    );
    factory.createStaticATokens(reserves);
    result.staticATokenCount = factory.getStaticATokens().length;
    console2.log('createStaticATokens completed');
    console2.log('  Total staticATokens in factory', result.staticATokenCount);
    for (uint256 i = 0; i < reserves.length; i++) {
      string memory underlyingSymbol = _readSymbol(reserves[i]);
      address staticAToken = factory.getStaticAToken(reserves[i]);
      console2.log('  underlying', reserves[i]);
      console2.log('  underlying symbol', underlyingSymbol);
      console2.log('  staticAToken', staticAToken);
    }
  }

  function deployPloutosHemi(
    address proxyAdminOwner
  ) internal returns (DeploymentResult memory result) {
    if (block.chainid != PloutosHemiConfig.CHAIN_ID) {
      revert('CHAIN_ID_MISMATCH');
    }

    IPool pool = IPool(PloutosHemiConfig.POOL);
    IRewardsController rewardsController = IRewardsController(
      PloutosHemiConfig.INCENTIVES_CONTROLLER
    );
    address[] memory reserves = pool.getReservesList();

    console2.log('Deploy config');
    console2.log('  Chain ID', block.chainid);
    console2.log('  Pool', address(pool));
    console2.log('  Incentives', address(rewardsController));
    console2.log('  ProxyAdmin owner', proxyAdminOwner);
    console2.log('  Reserves count', reserves.length);

    console2.log('Step 1/6: Deploy TransparentProxyFactory');
    TransparentProxyFactory proxyFactory = new TransparentProxyFactory();
    result.transparentProxyFactory = address(proxyFactory);
    console2.log('  TransparentProxyFactory', result.transparentProxyFactory);

    console2.log('Step 2/6: Create ProxyAdmin');
    result.proxyAdmin = proxyFactory.createProxyAdmin(proxyAdminOwner);
    console2.log('  ProxyAdmin', result.proxyAdmin);
    console2.log('  ProxyAdmin owner (on-chain)', ProxyAdmin(result.proxyAdmin).owner());

    console2.log('Step 3/6: Deploy StaticATokenLM implementation');
    StaticATokenLM staticImpl = new StaticATokenLM(pool, rewardsController);
    result.staticATokenImpl = address(staticImpl);
    console2.log('  StaticATokenLM implementation', result.staticATokenImpl);

    console2.log('Step 4/6: Deploy StaticATokenFactory implementation');
    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      pool,
      result.proxyAdmin,
      ITransparentProxyFactory(result.transparentProxyFactory),
      result.staticATokenImpl
    );
    result.staticATokenFactoryImpl = address(factoryImpl);
    console2.log('  StaticATokenFactory implementation', result.staticATokenFactoryImpl);

    console2.log('Step 5/6: Deploy StaticATokenFactory proxy');
    StaticATokenFactory factory = StaticATokenFactory(
      ITransparentProxyFactory(result.transparentProxyFactory).create(
        result.staticATokenFactoryImpl,
        result.proxyAdmin,
        abi.encodeWithSelector(StaticATokenFactory.initialize.selector)
      )
    );
    result.staticATokenFactoryProxy = address(factory);
    console2.log('  StaticATokenFactory proxy', result.staticATokenFactoryProxy);

    result.staticATokenFactoryProxyImplementation = ProxyAdmin(result.proxyAdmin)
      .getProxyImplementation(
        TransparentUpgradeableProxy(payable(result.staticATokenFactoryProxy))
      );
    console2.log(
      '  StaticATokenFactory proxy impl (read via ProxyAdmin)',
      result.staticATokenFactoryProxyImplementation
    );

    console2.log('Step 6/6: createStaticATokens(pool.getReservesList())');
    _logReservePlan(
      pool,
      ITransparentProxyFactory(result.transparentProxyFactory),
      result.staticATokenImpl,
      result.proxyAdmin,
      reserves
    );
    factory.createStaticATokens(reserves);
    result.staticATokenCount = factory.getStaticATokens().length;
    console2.log('createStaticATokens completed');
    console2.log('  Total staticATokens in factory', result.staticATokenCount);
    for (uint256 i = 0; i < reserves.length; i++) {
      string memory underlyingSymbol = _readSymbol(reserves[i]);
      address staticAToken = factory.getStaticAToken(reserves[i]);
      console2.log('  underlying', reserves[i]);
      console2.log('  underlying symbol', underlyingSymbol);
      console2.log('  staticAToken', staticAToken);
    }
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

contract DeployHemi is Script {
  error ChainIdMismatch(uint256 expected, uint256 actual);

  function run() external returns (DeployATokenFactory.DeploymentResult memory result) {
    if (block.chainid != PloutosHemiConfig.CHAIN_ID) {
      revert ChainIdMismatch(PloutosHemiConfig.CHAIN_ID, block.chainid);
    }

    vm.startBroadcast();
    result = DeployATokenFactory.deployPloutosHemi(PloutosHemiConfig.PROXY_ADMIN_OWNER);
    vm.stopBroadcast();

    console2.log('Ploutos Hemi Mainnet deployment completed');
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
