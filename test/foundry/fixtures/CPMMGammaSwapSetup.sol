// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/GammaPoolFactory.sol";
import "@gammaswap/v1-core/contracts/base/PoolViewer.sol";

import "./UniswapSetup.sol";
import "./TokensSetup.sol";
import "@gammaswap/v1-implementations/contracts/pools/CPMMGammaPool.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMBorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMRepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/rebalance/CPMMExternalRebalanceStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMBatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMExternalLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/CPMMShortStrategy.sol";
import "@gammaswap/v1-implementations/contracts/libraries/cpmm/CPMMMath.sol";
import "@gammaswap/v1-periphery/contracts/PositionManager.sol";

contract CPMMGammaSwapSetup is UniswapSetup, TokensSetup {

    bool constant IS_DELTASWAP = true;

    struct LogRateParams {
        uint64 baseRate;
        uint80 factor;
        uint80 maxApy;
    }

    GammaPoolFactory public factory;

    CPMMBorrowStrategy public longStrategy;
    CPMMRepayStrategy public repayStrategy;
    CPMMShortStrategy public shortStrategy;
    CPMMLiquidationStrategy public liquidationStrategy;
    CPMMBatchLiquidationStrategy public batchLiquidationStrategy;
    CPMMExternalLiquidationStrategy public externalLiquidationStrategy;
    CPMMExternalRebalanceStrategy public externalRebalanceStrategy;
    CPMMGammaPool public protocol;
    CPMMGammaPool public protocol2;
    CPMMGammaPool public pool;
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
        owner = address(this);
        super.initTokens(4 * 1e6 * 1e18, use6Decimals);

        factory = new GammaPoolFactory(owner);

        if(IS_DELTASWAP) {
            super.initDeltaSwap(owner, address(weth), address(factory));
        } else {
            super.initUniswap(owner, address(weth));
        }

        approveRouter();

        uint16 PROTOCOL_ID = 1;
        uint64 baseRate = 1e16;
        uint80 factor = 4 * 1e16;
        uint80 maxApy = 75 * 1e16;
        uint256 maxTotalApy = 1e19;

        mathLib = new CPMMMath();
        viewer = new PoolViewer();
        longStrategy = new CPMMBorrowStrategy(address(mathLib), maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);
        repayStrategy = new CPMMRepayStrategy(address(mathLib), maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);
        shortStrategy = new CPMMShortStrategy(maxTotalApy, 2252571, baseRate, factor, maxApy);
        liquidationStrategy = new CPMMLiquidationStrategy(address(mathLib), maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);
        batchLiquidationStrategy = new CPMMBatchLiquidationStrategy(address(mathLib), maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);
        externalRebalanceStrategy = new CPMMExternalRebalanceStrategy(maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);
        externalLiquidationStrategy = new CPMMExternalLiquidationStrategy(address(mathLib), maxTotalApy, 2252571, 997, cfmmFactory, baseRate, factor, maxApy);

        protocol = new CPMMGammaPool(PROTOCOL_ID, address(factory), address(longStrategy), address(repayStrategy), address(shortStrategy),
            address(liquidationStrategy), address(batchLiquidationStrategy), address(viewer), address(externalRebalanceStrategy),
            address(externalLiquidationStrategy), address(uniFactory), cfmmHash);

        protocol2 = new CPMMGammaPool(PROTOCOL_ID, address(factory), address(longStrategy), address(repayStrategy), address(shortStrategy),
            address(liquidationStrategy), address(batchLiquidationStrategy), address(viewer), address(externalRebalanceStrategy),
            address(externalLiquidationStrategy), address(uniFactory), cfmmHash);

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
