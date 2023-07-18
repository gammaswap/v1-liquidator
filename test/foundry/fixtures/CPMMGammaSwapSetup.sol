// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/GammaPoolFactory.sol";
import "@gammaswap/v1-core/contracts/base/PoolViewer.sol";

import "./UniswapSetup.sol";
import "./TokensSetup.sol";
import "@gammaswap/v1-implementations/contracts/pools/CPMMGammaPool.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMBorrowStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/lending/CPMMRepayStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/liquidation/CPMMBatchLiquidationStrategy.sol";
import "@gammaswap/v1-implementations/contracts/strategies/cpmm/CPMMShortStrategy.sol";
import "@gammaswap/v1-implementations/contracts/libraries/cpmm/CPMMMath.sol";

contract CPMMGammaSwapSetup is UniswapSetup, TokensSetup {

    GammaPoolFactory public factory;

    CPMMBorrowStrategy public longStrategy;
    CPMMRepayStrategy public repayStrategy;
    CPMMShortStrategy public shortStrategy;
    CPMMLiquidationStrategy public liquidationStrategy;
    CPMMBatchLiquidationStrategy public batchLiquidationStrategy;
    CPMMGammaPool public protocol;
    CPMMGammaPool public pool;
    IPoolViewer public viewer;

    CPMMMath public mathLib;

    address public cfmm;
    address public owner;

    function initCPMMGammaSwap() public {
        owner = address(this);
        super.initTokens(4 * 1e24);
        super.initUniswap(owner, address(weth));

        approveRouter();

        factory = new GammaPoolFactory(owner);

        uint16 PROTOCOL_ID = 1;
        uint64 baseRate = 1e16;
        uint80 factor = 4 * 1e16;
        uint80 maxApy = 75 * 1e16;
        uint256 maxTotalApy = 1e19;

        mathLib = new CPMMMath();
        viewer = new PoolViewer();
        longStrategy = new CPMMBorrowStrategy(address(mathLib), 8000, maxTotalApy, 2252571, 0, 997, 1000, baseRate, factor, maxApy);
        repayStrategy = new CPMMRepayStrategy(address(mathLib), 8000, maxTotalApy, 2252571, 0, 997, 1000, baseRate, factor, maxApy);
        shortStrategy = new CPMMShortStrategy(maxTotalApy, 2252571, baseRate, factor, maxApy);
        liquidationStrategy = new CPMMLiquidationStrategy(address(mathLib), 9500, 250, maxTotalApy, 2252571, 997, 1000, baseRate, factor, maxApy);
        batchLiquidationStrategy = new CPMMBatchLiquidationStrategy(address(mathLib), 9500, 250, maxTotalApy, 2252571, 997, 1000, baseRate, factor, maxApy);



        bytes32 cfmmHash = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'; // UniV2Pair init_code_hash

        protocol = new CPMMGammaPool(PROTOCOL_ID, address(factory), address(longStrategy), address(repayStrategy), address(shortStrategy),
            address(liquidationStrategy), address(batchLiquidationStrategy), address(viewer), address(0), address(0), address(uniFactory), cfmmHash);

        factory.addProtocol(address(protocol));

        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        cfmm = createPair(tokens[0], tokens[1]);

        pool = CPMMGammaPool(factory.createPool(PROTOCOL_ID, cfmm, tokens, new bytes(0)));

        approvePool();
    }

    function approveRouter() public {
        vm.startPrank(addr1);
        usdc.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        usdc.approve(address(uniRouter), type(uint256).max);
        weth.approve(address(uniRouter), type(uint256).max);
        vm.stopPrank();
    }

    function approvePool() public {
        vm.startPrank(addr1);
        pool.approve(address(pool), type(uint256).max);
        IERC20(cfmm).approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(addr2);
        pool.approve(address(pool), type(uint256).max);
        IERC20(cfmm).approve(address(pool), type(uint256).max);
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

    function calcInvariant(uint128[] memory tokensHeld) internal pure returns (uint256) {
        return Math.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);
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
