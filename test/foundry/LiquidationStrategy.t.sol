// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/Math.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";

contract LiquidationStrategyTest is CPMMGammaSwapSetup {
    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

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

        uint256 collateralAsLP = convertInvariantToLP(loanCollateralForLiq) - 1000;

        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
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

        uint256 expectedRefund = convertInvariantToLP(loanData.liquidity * 250 / 10000) - 1000;

        uint256 cfmmBal0 = IERC20(cfmm).balanceOf(addr1);
        (uint256 loanLiquidity, uint256 refund) = pool.liquidate(tokenId);
        uint256 cfmmBal1 = IERC20(cfmm).balanceOf(addr1);
        loanData = viewer.loan(address(pool), tokenId);

        assertGt(loanCollateralExLiqFee, loanLiquidity);
        assertEq(refund, expectedRefund);
        assertGt(cfmmBal1, cfmmBal0);
        assertEq(cfmmBal1 - cfmmBal0, refund);
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
    ////////// PARTIAL LIQUIDATE //////////
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
}
