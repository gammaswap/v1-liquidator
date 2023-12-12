// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
import "@gammaswap/v1-core/contracts/test/strategies/external/TestExternalCallee.sol";
import "@gammaswap/v1-core/contracts/test/strategies/external/TestExternalCallee2.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";

contract LiquidationStrategyTest is CPMMGammaSwapSetup {
    function setUp() public {
        super.initCPMMGammaSwap(false);
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

    ///////////////////////////////////////
    ///// LIQUIDATE with Flash Loan ///////
    ///////////////////////////////////////
    function testExternalLiquidationInsufficientLPError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        uint256 lpAmount = lpTokens/10;
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);

        address[] memory tokens = pool.tokens();
        TestExternalCallee.SwapData memory swapData = TestExternalCallee.SwapData({ strategy: address(pool),
            cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: 0});

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);
        lpAmount = convertInvariantToLP(loanData.liquidity);
        TestExternalCallee callee = new TestExternalCallee();

        uint128[] memory amounts = new uint128[](2);

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, 0, address(callee), abi.encode(swapData));

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount/2);

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, 0, address(callee), abi.encode(swapData));

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), (lpAmount/2 - 1));

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, 0, address(callee), abi.encode(swapData));

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), 10);
        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateExternally(tokenId, amounts, 0, address(callee), abi.encode(swapData));

        uint256[] memory _amounts = calcTokensFromInvariant(loanData.liquidity + loanData.liquidity * 250 / 10000);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund[0]/1e3,_amounts[0]/1e3);
        assertEq(refund[1]/1e3,_amounts[1]/1e3);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, 0);
    }

    function testExternalLiquidationInsufficientLPError2() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        //lpAmount = bound(lpAmount, 1e18, lpTokens/10);
        uint256 lpAmount = lpTokens/10;
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);

        address[] memory tokens = pool.tokens();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);
        lpAmount = convertInvariantToLP(loanData.liquidity);
        TestExternalCallee2 callee = new TestExternalCallee2();

        uint128[] memory amounts = new uint128[](2);

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
            cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount/2});

        vm.expectRevert(bytes4(keccak256("LPBalanceShortfall()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("LPBalanceShortfall()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount + 100, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount/2});

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount/2);

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount/2});

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount/3});

        vm.expectRevert(bytes4(keccak256("LPBalanceShortfall()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount + 100, address(callee), abi.encode(swapData));

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount/2);

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), 10);
        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        uint256[] memory _amounts = calcTokensFromInvariant(loanData.liquidity + loanData.liquidity * 250 / 10000);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund[0]/1e3,_amounts[0]/1e3);
        assertEq(refund[1]/1e3,_amounts[1]/1e3);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, 0);
        assertGt(loanData1.tokensHeld[0], 0);
        assertGt(loanData1.tokensHeld[1], 0);
        assertLt(loanData1.tokensHeld[0], loanData.tokensHeld[0]);
        assertLt(loanData1.tokensHeld[1], loanData.tokensHeld[1]);
    }


    function testExternalLiquidationInsufficientCollateralError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        //lpAmount = bound(lpAmount, 1e18, lpTokens/10);
        uint256 lpAmount = lpTokens/10;
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);

        address[] memory tokens = pool.tokens();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);
        lpAmount = convertInvariantToLP(loanData.liquidity);
        TestExternalCallee2 callee = new TestExternalCallee2();

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = loanData.tokensHeld[0] + 1;
        amounts[1] = loanData.tokensHeld[1] + 1;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: loanData.tokensHeld[1], lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        amounts[0] = loanData.tokensHeld[0] + 1;
        amounts[1] = loanData.tokensHeld[1];
        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        amounts[0] = loanData.tokensHeld[0];
        amounts[1] = loanData.tokensHeld[1] + 1;
        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        amounts[0] = loanData.tokensHeld[0];
        amounts[1] = loanData.tokensHeld[1];

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));


        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        amounts[0] = loanData.tokensHeld[0];
        amounts[1] = loanData.tokensHeld[1];
        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount);

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), 10);

        vm.expectRevert(bytes4(keccak256("CollateralShortfall()")));
        pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: loanData.tokensHeld[1], lpTokens: lpAmount});

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        uint256[] memory _amounts = calcTokensFromInvariant(loanData.liquidity + loanData.liquidity * 250 / 10000);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund[0]/1e3,_amounts[0]/1e3);
        assertEq(refund[1]/1e3,_amounts[1]/1e3);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, 0);
        assertGt(loanData1.tokensHeld[0], 0);
        assertGt(loanData1.tokensHeld[1], 0);
        assertLt(loanData1.tokensHeld[0], loanData.tokensHeld[0]);
        assertLt(loanData1.tokensHeld[1], loanData.tokensHeld[1]);
    }

    /*function testExternalLiquidation2() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        //lpAmount = bound(lpAmount, 1e18, lpTokens/10);
        uint256 lpAmount = lpTokens/10;
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);

        address[] memory tokens = pool.tokens();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);
        lpAmount = convertInvariantToLP(loanData.liquidity);
        TestExternalCallee2 callee = new TestExternalCallee2();


        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: loanData.tokensHeld[1], lpTokens: lpAmount});

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = loanData.tokensHeld[0];
        amounts[1] = loanData.tokensHeld[1];
        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount);

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), 10);

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: loanData.tokensHeld[1], lpTokens: lpAmount});

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateExternally(tokenId, amounts, lpAmount, address(callee), abi.encode(swapData));

        uint256[] memory _amounts = calcTokensFromInvariant(loanData.liquidity + loanData.liquidity * 250 / 10000);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund[0]/1e3,_amounts[0]/1e3);
        assertEq(refund[1]/1e3,_amounts[1]/1e3);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, 0);
        assertGt(loanData1.tokensHeld[0], 0);
        assertGt(loanData1.tokensHeld[1], 0);
        assertLt(loanData1.tokensHeld[0], loanData.tokensHeld[0]);
        assertLt(loanData1.tokensHeld[1], loanData.tokensHeld[1]);
    }/**/

    ////////////////////////////////////
    ////////// FULL LIQUIDATE //////////
    ////////////////////////////////////
    function testLiquidateWithWritedown() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(100000000); // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        uint256 writeDown = loanData.liquidity - loanCollateralExLiqFee;
        assertGt(writeDown, 0);

        uint256 collateralAsLP = convertInvariantToLP(loanCollateralForLiq);

        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund, collateralAsLP);

        // All paid out! No collateral left
        assertEq(loanData1.tokensHeld[0]/1e3, 0);
        assertEq(loanData1.tokensHeld[1]/1e3, 0);
    }

    function testLiquidateWithWritedownSync() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(100000000); // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        uint256 writeDown = loanData.liquidity - loanCollateralExLiqFee;
        assertGt(writeDown, 0);

        uint256 collateralAsLP = convertInvariantToLP(loanCollateralForLiq);

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund, collateralAsLP);

        // All paid out! No collateral left
        assertEq(loanData1.tokensHeld[0]/1e3, 0);
        assertEq(loanData1.tokensHeld[1]/1e3, 0);
    }

    function testLiquidateNoWritedown() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(45000000);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        assertGt(loanCollateralExLiqFee, loanData.liquidity);   // No writedown

        uint256 expectedRefund = convertInvariantToLP(loanData.liquidity * 250 / 10000);

        uint256 cfmmBal0 = IERC20(cfmm).balanceOf(addr1);
        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
        uint256 cfmmBal1 = IERC20(cfmm).balanceOf(addr1);
        loanData = viewer.loan(address(pool), tokenId);

        assertGt(loanCollateralExLiqFee, loanLiquidity);
        assertEq(refund, expectedRefund);
        assertGt(cfmmBal1, cfmmBal0);
        assertEq(cfmmBal1 - cfmmBal0, refund);
    }

    function testLiquidateNoWritedownSync() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(45000000);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        assertGt(loanCollateralExLiqFee, loanData.liquidity);   // No writedown

        uint256 expectedRefund = convertInvariantToLP(loanData.liquidity * 250 / 10000);

        uint256 cfmmBal0 = IERC20(cfmm).balanceOf(addr1);

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        uint256 cfmmBal1 = IERC20(cfmm).balanceOf(addr1);
        loanData = viewer.loan(address(pool), tokenId);

        assertGt(loanCollateralExLiqFee, loanLiquidity);
        assertEq(refund, expectedRefund);
        assertGt(cfmmBal1, cfmmBal0);
        assertEq(cfmmBal1 - cfmmBal0 + 100, refund);
    }

    function testLiquidateHasMarginError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(1000);

        vm.expectRevert(bytes4(keccak256("HasMargin()")));
        pool.liquidate(tokenId);
    }

    ///////////////////////////////////////
    ////////// LIQUIDATE with LP //////////
    ///////////////////////////////////////
    function testLiquidateWithLp(uint256 lpAmount) public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        lpAmount = bound(lpAmount, 1e18, lpTokens/10);
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        lpAmount = convertInvariantToLP(loanData.liquidity) + 1000;

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount);

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateWithLP(tokenId);

        uint256[] memory amounts = calcTokensFromInvariant(loanData.liquidity + loanData.liquidity * 250 / 10000);

        assertEq(loanLiquidity/1e3, loanData.liquidity/1e3);
        assertEq(refund[0]/1e3,amounts[0]/1e3);
        assertEq(refund[1]/1e3,amounts[1]/1e3);
    }

    function testLiquidateNoLpError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.liquidateWithLP(tokenId);
    }

    ///////////////////////////////////////
    ////////// BATCH LIQUIDATE ////////////
    ///////////////////////////////////////
    function testBatchLiquidate() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan(0);   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1, new uint256[](0));
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan(0);   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2, new uint256[](0));
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        // Send enough lp tokens for full liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpTokens * 4/5);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId1);
        IGammaPool.LoanData memory loanData2 = viewer.loan(address(pool), tokenId2);
        uint256 loanCollateral1 = calcInvariant(loanData1.tokensHeld);
        uint256 loanCollateralExLiqFee1 = loanCollateral1 * (10000 - 250) / 10000;
        uint256 loanCollateral2 = calcInvariant(loanData2.tokensHeld);
        uint256 loanCollateralExLiqFee2 = loanCollateral2 * (10000 - 250) / 10000;

        uint256 loanCollateralForLiq = loanCollateral1 + loanCollateral2;
        uint256[] memory amounts = calcTokensFromInvariant(loanCollateralForLiq);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        (uint256 totalLoanLiquidity, uint256[] memory refund) = pool.batchLiquidations(tokenIds);

        assertEq(totalLoanLiquidity/1e3, (loanCollateralExLiqFee1 + loanCollateralExLiqFee2)/1e3);
        assertEq(refund[0]/1e3, amounts[0]/1e3);
        assertEq(refund[1]/1e3, amounts[1]/1e3);
    }

    function testBatchLiquidate2() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan(0);   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1, new uint256[](0));
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan(0);   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2, new uint256[](0));
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        uint256 tokenId3 = pool.createLoan(0);   // Loan 2
        usdc.transfer(address(pool), 250_000 * 1e18);
        weth.transfer(address(pool), 250 * 1e18);
        pool.increaseCollateral(tokenId3, new uint256[](0));
        pool.borrowLiquidity(tokenId3, lpTokens/4, new uint256[](0));

        vm.roll(8000000);

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId1);
        IGammaPool.LoanData memory loanData2 = viewer.loan(address(pool), tokenId2);
        IGammaPool.LoanData memory loanData3 = viewer.loan(address(pool), tokenId3);

        {
            uint256 totLiquidity = loanData1.liquidity + loanData2.liquidity + loanData3.liquidity;

            uint256 collateral1 = GSMath.sqrt(uint256(loanData1.tokensHeld[0]) * loanData1.tokensHeld[1]);
            uint256 collateral2 = GSMath.sqrt(uint256(loanData2.tokensHeld[0]) * loanData2.tokensHeld[1]);
            uint256 totCollateral = collateral1 + collateral2;

            (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(cfmm).getReserves();
            uint256 lpDeposit = (totLiquidity - loanData3.liquidity) * IERC20(cfmm).totalSupply() / GSMath.sqrt(reserve0 * reserve1);

            // Send enough lp tokens for full liquidation
            GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpDeposit + 500);
        }
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        (uint256 totalLoanLiquidity, uint256[] memory refund) = pool.batchLiquidations(tokenIds);

        poolData = viewer.getLatestPoolData(address(pool));

        loanData1 = viewer.loan(address(pool), tokenId1);
        loanData2 = viewer.loan(address(pool), tokenId2);
        {
            loanData3 = viewer.loan(address(pool), tokenId3);
            uint256 totLiquidity = loanData1.liquidity + loanData2.liquidity + loanData3.liquidity;
            assertLe(totLiquidity,poolData.BORROWED_INVARIANT);

            uint256 collateral1 = GSMath.sqrt(uint256(loanData1.tokensHeld[0]) * loanData1.tokensHeld[1]);
            uint256 collateral2 = GSMath.sqrt(uint256(loanData2.tokensHeld[0]) * loanData2.tokensHeld[1]);
            uint256 totCollateral = collateral1 + collateral2;
        }
    }

    function testBatchNoFullLiquidationError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan(0);   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1, new uint256[](0));
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan(0);   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2, new uint256[](0));
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        // Send insufficient lp tokens for full liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpTokens/2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectRevert(bytes4(keccak256("InsufficientDeposit()")));
        pool.batchLiquidations(tokenIds);
    }

    function testBatchLiquidateNoDebtError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan(0);   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1, new uint256[](0));
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan(0);   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2, new uint256[](0));
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(1000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectRevert(bytes4(keccak256("NoLiquidityDebt()")));
        pool.batchLiquidations(tokenIds);
    }

    function testBorrowedInvariant() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256[] memory tokenIds = new uint256[](200);
        for(uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId1 = pool.createLoan(0);   // Loan 1
            usdc.transfer(address(pool), 15_000 * 1e17);
            weth.transfer(address(pool), 15 * 1e17);
            pool.increaseCollateral(tokenId1, new uint256[](0));
            pool.borrowLiquidity(tokenId1, lpTokens/400, new uint256[](0));
            tokenIds[i] = tokenId1;
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        uint256 totLiquidity = 0;
        for(uint256 i = 0; i < tokenIds.length; i++) {
            IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenIds[i]);
            totLiquidity = totLiquidity + loanData.liquidity;
        }

        assertEq(poolData.BORROWED_INVARIANT, totLiquidity);
        uint256 blockNum = 0;
        for(uint256 i = 0; i < 1000; i++) {
            for(uint256 j = 0; j < tokenIds.length; j++) {
                blockNum = blockNum + 10;
                vm.roll(blockNum);
                pool.updatePool(tokenIds[j]);
            }
        }

        poolData = viewer.getLatestPoolData(address(pool));

        totLiquidity = 0;
        for(uint256 i = 0; i < tokenIds.length; i++) {
            IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenIds[i]);
            totLiquidity = totLiquidity + loanData.liquidity;
        }
        assertEq(poolData.BORROWED_INVARIANT/1e11, totLiquidity/1e11);
    }

    function testBorrowedInvariantLiquidations() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256[] memory tokenIds = new uint256[](2);
        for(uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId1 = pool.createLoan(0);   // Loan 1
            usdc.transfer(address(pool), 15_000 * 1e17);
            weth.transfer(address(pool), 15 * 1e17);
            pool.increaseCollateral(tokenId1, new uint256[](0));
            pool.borrowLiquidity(tokenId1, lpTokens/400, new uint256[](0));
            tokenIds[i] = tokenId1;
        }

        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 px0 = uint256(reserve1) * 1e18 / reserve0;
        sellTokenIn(reserve1/2, address(usdc), address(weth), addr1);

        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();
        px0 = uint256(reserve1) * 1e18 / reserve0;
        IPoolViewer viewer = IPoolViewer(pool.viewer());
        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        uint256 totLiquidity = 0;
        for(uint256 i = 0; i < tokenIds.length; i++) {
            IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenIds[i]);
            uint256 collateralLiq = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);
            uint256 ltv = loanData.liquidity * 1e18 / collateralLiq;
            totLiquidity = totLiquidity + loanData.liquidity;
        }

        assertEq(poolData.BORROWED_INVARIANT, totLiquidity);
        vm.stopPrank();
        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 250, 255);// setting origination fees to zero

        vm.startPrank(addr1);
        uint256 blockNum = 0;
        for(uint256 i = 0; i < 150; i++) {
            for(uint256 j = 0; j < tokenIds.length; j++) {
                blockNum = blockNum + 200;
                vm.roll(blockNum);
                if(i > 0 && i%10 == 0) {
                    IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenIds[0]);
                    if(loanData.liquidity > 0) {
                        pool.liquidate(tokenIds[0]);
                    }
                }
            }
        }

        poolData = viewer.getLatestPoolData(address(pool));

        totLiquidity = 0;
        for(uint256 i = 0; i < tokenIds.length; i++) {
            IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenIds[i]);
            totLiquidity = totLiquidity + loanData.liquidity;
        }
        assertEq(poolData.BORROWED_INVARIANT/1e3, totLiquidity/1e3);
    }
}
