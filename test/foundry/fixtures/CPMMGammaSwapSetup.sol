// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/GammaPoolFactory.sol";
import "@gammaswap/v1-core/contracts/base/PoolViewer.sol";
import "@gammaswap/v1-implementations/contracts/viewers/vault/VaultPoolViewer.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/vault/IVaultPoolViewer.sol";

import "./UniswapSetup.sol";
import "./TokensSetup.sol";
import "@gammaswap/v1-implementations/contracts/pools/CPMMGammaPool.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMBorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMRepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/rebalance/CPMMRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/rebalance/CPMMExternalRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMBatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMExternalLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/CPMMShortStrategy.sol";

import "@gammaswap/v1-implementations/contracts/pools/VaultGammaPool.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/lending/VaultBorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/lending/VaultRepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/rebalance/VaultRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/rebalance/VaultExternalRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/liquidation/VaultLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/liquidation/VaultBatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/liquidation/VaultExternalLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/vault/VaultShortStrategy.sol";

import "@gammaswap/v1-implementations/contracts/libraries/cpmm/CPMMMath.sol";
import "@gammaswap/v1-periphery/contracts/PositionManager.sol";

import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/lending/DSV2BorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/lending/DSV2RepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/rebalance/DSV2ExternalRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/liquidation/DSV2LiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/liquidation/DSV2BatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/liquidation/DSV2ExternalLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/deltaswap/DSV2ShortStrategy.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/deltaswap/IDSV2Pair.sol";

contract CPMMGammaSwapSetup is UniswapSetup, TokensSetup {

    bool constant IS_DELTASWAP = true;
    bool constant IS_DELTASWAP_V2 = false;
    bool IS_VAULT = true;

    struct LogRateParams {
        uint64 baseRate;
        uint64 optimalUtilRate;
        uint64 slope1;
        uint64 slope2;
    }

    GammaPoolFactory public factory;

    CPMMBorrowStrategy public longStrategy;
    CPMMRepayStrategy public repayStrategy;
    CPMMRebalanceStrategy public rebalanceStrategy;
    CPMMShortStrategy public shortStrategy;
    CPMMLiquidationStrategy public liquidationStrategy;
    CPMMBatchLiquidationStrategy public batchLiquidationStrategy;
    CPMMExternalLiquidationStrategy public externalLiquidationStrategy;
    CPMMExternalRebalanceStrategy public externalRebalanceStrategy;
    CPMMGammaPool public protocol;
    CPMMGammaPool public protocol2;
    CPMMGammaPool public pool;
    CPMMGammaPool public pool2;
    CPMMGammaPool public pool6x18;
    CPMMGammaPool public pool18x6;
    CPMMGammaPool public pool6x6;
    CPMMGammaPool public pool6x8;
    CPMMGammaPool public pool18x8;
    IPoolViewer public viewer;

    PositionManager posMgr;

    CPMMMath public mathLib;

    address public cfmm;
    address public cfmm6x18;
    address public cfmm18x6;
    address public cfmm6x6;
    address public cfmm6x8;
    address public cfmm18x8;

    address public owner;

    function initCPMMGammaSwap(bool use6Decimals) public {
        _initCPMMGammaSwap(use6Decimals, false);
    }

    function _initCPMMGammaSwap(bool use6Decimals, bool hasLiquidator) public {
        owner = address(this);
        super.initTokens(4 * 1e8, use6Decimals);

        factory = new GammaPoolFactory(owner);

        if(IS_DELTASWAP) {
            if(IS_DELTASWAP_V2) {
                super.initDeltaSwapV2(owner, address(weth), address(factory));
            } else {
                super.initDeltaSwap(owner, address(weth), address(factory));
            }
        } else {
            super.initUniswap(owner, address(weth));
        }

        approveRouter();

        uint16 PROTOCOL_ID = 1;
        uint64 baseRate = 1e16;
        uint64 optimalUtilRate = 8 * 1e17;
        uint64 slope1 = 5 * 1e16;
        uint64 slope2 = 75 * 1e16;
        uint256 maxTotalApy = 15 * 1e18;

        mathLib = new CPMMMath();

        if(IS_VAULT) {
            viewer = IPoolViewer(address(new VaultPoolViewer()));
        } else {
            viewer = new PoolViewer();
        }

        address liquidator = hasLiquidator ? owner : address(0);
        if(IS_DELTASWAP_V2) {
            longStrategy = new DSV2BorrowStrategy(address(mathLib), maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            repayStrategy = new DSV2RepayStrategy(address(mathLib), maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            shortStrategy = new DSV2ShortStrategy(maxTotalApy, 2252571, baseRate, optimalUtilRate, slope1, slope2);
            liquidationStrategy = new DSV2LiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            batchLiquidationStrategy = new DSV2BatchLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            externalRebalanceStrategy = new DSV2ExternalRebalanceStrategy(maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            externalLiquidationStrategy = new DSV2ExternalLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 9970, 10000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
        } else if (IS_VAULT) {
            longStrategy = CPMMBorrowStrategy(address(new VaultBorrowStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            repayStrategy = CPMMRepayStrategy(address(new VaultRepayStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            rebalanceStrategy = CPMMRebalanceStrategy(address(new VaultRebalanceStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            shortStrategy = CPMMShortStrategy(address(new VaultShortStrategy(maxTotalApy, 2252571, baseRate, optimalUtilRate, slope1, slope2)));
            liquidationStrategy = CPMMLiquidationStrategy(address(new VaultLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            batchLiquidationStrategy = CPMMBatchLiquidationStrategy(address(new VaultBatchLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            externalRebalanceStrategy = CPMMExternalRebalanceStrategy(address(new VaultExternalRebalanceStrategy(maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
            externalLiquidationStrategy = CPMMExternalLiquidationStrategy(address(new VaultExternalLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2)));
        } else {
            longStrategy = new CPMMBorrowStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            repayStrategy = new CPMMRepayStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            rebalanceStrategy = new CPMMRebalanceStrategy(address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            shortStrategy = new CPMMShortStrategy(maxTotalApy, 2252571, baseRate, optimalUtilRate, slope1, slope2);
            liquidationStrategy = new CPMMLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            batchLiquidationStrategy = new CPMMBatchLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            externalRebalanceStrategy = new CPMMExternalRebalanceStrategy(maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
            externalLiquidationStrategy = new CPMMExternalLiquidationStrategy(liquidator, address(mathLib), maxTotalApy, 2252571, 997, 1000, cfmmFactory, baseRate, optimalUtilRate, slope1, slope2);
        }

        ICPMMGammaPool.InitializationParams memory params = ICPMMGammaPool.InitializationParams({
            protocolId: PROTOCOL_ID,
            factory: address(factory),
            borrowStrategy: address(longStrategy),
            repayStrategy: address(repayStrategy),
            rebalanceStrategy: address(rebalanceStrategy),
            shortStrategy: address(shortStrategy),
            liquidationStrategy: address(liquidationStrategy),
            batchLiquidationStrategy: address(batchLiquidationStrategy),
            viewer: address(viewer),
            externalRebalanceStrategy: address(externalRebalanceStrategy),
            externalLiquidationStrategy: address(externalLiquidationStrategy),
            cfmmFactory: address(uniFactory),
            cfmmInitCodeHash: cfmmHash
        });

        if(IS_VAULT) {
            protocol = new VaultGammaPool(params);
            protocol2 = new VaultGammaPool(params);
        } else {
            protocol = new CPMMGammaPool(params);
            protocol2 = new CPMMGammaPool(params);
        }

        factory.addProtocol(address(protocol));

        posMgr = new PositionManager(address(factory), address(weth));

        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        cfmm = createPair(tokens[0], tokens[1]);

        pool = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm, tokens, new bytes(0)));
        if(IS_DELTASWAP) {
            assertEq(IDeltaSwapPair(cfmm).gammaPool(), address(pool));
        }

        if(use6Decimals) {
            // 18x6 = usdc/weth6
            tokens[0] = address(usdc);
            tokens[1] = address(weth6);
            cfmm18x6 = createPair(tokens[0], tokens[1]);
            pool18x6 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm18x6, tokens, new bytes(0)));
            if(IS_DELTASWAP) {
                assertEq(IDeltaSwapPair(cfmm18x6).gammaPool(), address(pool18x6));
            }
            approvePoolAndCFMM(pool18x6, cfmm18x6);

            // 6x18 = usdc6/weth
            tokens[0] = address(usdc6);
            tokens[1] = address(weth);
            cfmm6x18 = createPair(tokens[0], tokens[1]);
            pool6x18 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm6x18, tokens, new bytes(0)));
            if(IS_DELTASWAP) {
                assertEq(IDeltaSwapPair(cfmm6x18).gammaPool(), address(pool6x18));
            }
            approvePoolAndCFMM(pool6x18, cfmm6x18);

            // 6x6 = usdc6/weth6
            tokens[0] = address(usdc6);
            tokens[1] = address(weth6);
            cfmm6x6 = createPair(tokens[0], tokens[1]);
            pool6x6 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm6x6, tokens, new bytes(0)));
            if(IS_DELTASWAP) {
                assertEq(IDeltaSwapPair(cfmm6x6).gammaPool(), address(pool6x6));
            }
            approvePoolAndCFMM(pool6x6, cfmm6x6);

            // 6x8 = usdc6/weth8
            tokens[0] = address(usdc6);
            tokens[1] = address(weth8);
            cfmm6x8 = createPair(tokens[0], tokens[1]);
            pool6x8 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm6x8, tokens, new bytes(0)));
            if(IS_DELTASWAP) {
                assertEq(IDeltaSwapPair(cfmm6x8).gammaPool(), address(pool6x8));
            }
            approvePoolAndCFMM(pool6x8, cfmm6x8);

            // 18x8 = usdc/weth8
            tokens[0] = address(usdc);
            tokens[1] = address(weth8);
            cfmm18x8 = createPair(tokens[0], tokens[1]);
            pool18x8 = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm18x8, tokens, new bytes(0)));
            if(IS_DELTASWAP) {
                assertEq(IDeltaSwapPair(cfmm18x8).gammaPool(), address(pool18x8));
            }
            approvePoolAndCFMM(pool18x8, cfmm18x8);
        }

        setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 250, 200, 1e3);// setting origination fees to zero

        approvePool();
        approvePosMgr();
    }

    function lockProtocol() internal {
        factory.lockProtocol(1);
        vm.expectRevert(bytes4(keccak256("ProtocolLocked()")));
        factory.updateProtocol(1,address(protocol2));
    }

    function setPoolParams(address pool, uint16 origFee, uint8 extSwapFee, uint8 emaMultiplier, uint8 minUtilRate1, uint8 minUtilRate2,
        uint16 feeDivisor, uint8 liquidationFee, uint8 ltvThreshold, uint72 minBorrow) internal {
        vm.startPrank(address(factory));
        IGammaPool(pool).setPoolParams(origFee, extSwapFee, emaMultiplier, minUtilRate1, minUtilRate2, feeDivisor, liquidationFee, ltvThreshold, minBorrow);// setting origination fees to zero
        vm.stopPrank();
    }

    function approvePosMgr() public {
        vm.startPrank(addr1);
        usdc.approve(address(posMgr), type(uint256).max);
        weth.approve(address(posMgr), type(uint256).max);
        weth6.approve(address(posMgr), type(uint256).max);
        weth8.approve(address(posMgr), type(uint256).max);
        usdc6.approve(address(posMgr), type(uint256).max);
        usdt.approve(address(posMgr), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        usdc.approve(address(posMgr), type(uint256).max);
        weth.approve(address(posMgr), type(uint256).max);
        weth6.approve(address(posMgr), type(uint256).max);
        weth8.approve(address(posMgr), type(uint256).max);
        usdc6.approve(address(posMgr), type(uint256).max);
        usdt.approve(address(posMgr), type(uint256).max);
        vm.stopPrank();
    }

    function approveRouter() public {
        vm.startPrank(addr1);
        usdc.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        usdc6.approve(address(uniRouter), type(uint256).max);
        weth6.approve(address(uniRouter), type(uint256).max);
        weth8.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        usdc.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        usdc6.approve(address(uniRouter), type(uint256).max);
        weth6.approve(address(uniRouter), type(uint256).max);
        weth8.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();
    }

    function approvePool() public {
        vm.startPrank(addr1);
        pool.approve(address(pool), type(uint256).max);
        pool.approve(address(posMgr), type(uint256).max);
        IERC20(cfmm).approve(address(pool), type(uint256).max);
        IERC20(cfmm).approve(address(posMgr), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        pool.approve(address(pool), type(uint256).max);
        pool.approve(address(posMgr), type(uint256).max);
        IERC20(cfmm).approve(address(pool), type(uint256).max);
        IERC20(cfmm).approve(address(posMgr), type(uint256).max);
        vm.stopPrank();
    }

    function approvePoolAndCFMM(CPMMGammaPool _pool, address _cfmm) public {
        vm.startPrank(addr1);
        _pool.approve(address(_pool), type(uint256).max);
        _pool.approve(address(posMgr), type(uint256).max);
        IERC20(_cfmm).approve(address(_pool), type(uint256).max);
        IERC20(_cfmm).approve(address(posMgr), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        _pool.approve(address(_pool), type(uint256).max);
        _pool.approve(address(posMgr), type(uint256).max);
        IERC20(_cfmm).approve(address(_pool), type(uint256).max);
        IERC20(_cfmm).approve(address(posMgr), type(uint256).max);
        vm.stopPrank();
    }

    function depositLiquidityInPool(address addr) public {
        vm.startPrank(addr);
        uint256 lpTokens = IERC20(cfmm).balanceOf(addr);
        pool.deposit(lpTokens, addr1);
        vm.stopPrank();
    }

    function depositLiquidityInCFMM(address addr, uint256 usdcAmount, uint256 wethAmount) public {
        vm.startPrank(addr);
        addLiquidity(address(usdc), address(weth), usdcAmount, wethAmount, addr); // 1 weth = 1,000 USDC
        vm.stopPrank();
    }

    function depositLiquidityInPoolFromCFMM(CPMMGammaPool _pool, address _cfmm, address addr) public {
        vm.startPrank(addr);
        uint256 lpTokens = IERC20(_cfmm).balanceOf(addr);
        _pool.deposit(lpTokens, addr1);
        vm.stopPrank();
    }

    function depositLiquidityInCFMMByToken(address token0, address token1, uint256 amount0, uint256 amount1, address addr) public {
        vm.startPrank(addr);
        addLiquidity(token0, token1, amount0, amount1, addr); // 1 weth = 1,000 USDC
        vm.stopPrank();
    }

    function calcInvariant(uint128[] memory tokensHeld) internal pure returns (uint256) {
        return GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);
    }

    function calcTokensFromInvariant(uint256 liquidity) internal view returns(uint256[] memory amounts) {
        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        uint256 lastCFMMInvariant = calcInvariant(poolData.CFMM_RESERVES);

        amounts = new uint256[](2);
        amounts[0] = liquidity * poolData.CFMM_RESERVES[0] / lastCFMMInvariant;
        amounts[1] = liquidity * poolData.CFMM_RESERVES[1] / lastCFMMInvariant;
    }

    function convertLPToInvariant(uint256 lpTokens) internal view returns (uint256) {
        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        uint128 cfmmInvariant = poolData.lastCFMMInvariant;
        uint256 cfmmTotalSupply = poolData.lastCFMMTotalSupply;

        return cfmmTotalSupply == 0 ? 0 : lpTokens * cfmmInvariant / cfmmTotalSupply;
    }

    function convertInvariantToLP(uint256 liquidity) internal view returns (uint256) {
        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        uint128 cfmmInvariant = poolData.lastCFMMInvariant;
        uint256 cfmmTotalSupply = poolData.lastCFMMTotalSupply;

        return cfmmTotalSupply == 0 ? 0 : liquidity * cfmmTotalSupply / cfmmInvariant;
    }
}
