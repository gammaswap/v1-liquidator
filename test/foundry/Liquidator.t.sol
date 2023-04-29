// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/Math.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";

contract LiquidatorTest is CPMMGammaSwapSetup {

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
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(100000000);  // After a while

        loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        uint256 writeDown = loanData.liquidity - loanCollateralExLiqFee;
        assertGt(writeDown, 0);

        uint256[] memory amounts = calcTokensFromInvariant(loanCollateralForLiq);

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidate(tokenId, new int256[](0), new uint256[](0));
        loanData = pool.loan(tokenId);

        assertEq(loanLiquidity/1e3, loanCollateralExLiqFee/1e3);
        assertEq(refund[0]/1e5, amounts[0]/1e5);
        assertEq(refund[1]/1e5, amounts[1]/1e5);

        // All paid out! No collateral left
        assertEq(loanData.tokensHeld[0], 0);
        assertEq(loanData.tokensHeld[1], 0);
    }

    function testLiquidateNoWritedown() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(45000000);

        loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);

        uint256 loanCollateral = calcInvariant(loanData.tokensHeld);
        uint256 loanCollateralForLiq = loanCollateral * 250 / 10000;
        uint256 loanCollateralExLiqFee = loanCollateral - loanCollateralForLiq;

        assertGt(loanCollateralExLiqFee, loanData.liquidity);   // No writedown

        uint256[] memory amounts = calcTokensFromInvariant(loanCollateral - loanData.liquidity);

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidate(tokenId, new int256[](0), new uint256[](0));
        loanData = pool.loan(tokenId);

        assertGt(loanCollateralExLiqFee, loanLiquidity);
        assertEq(refund[0]/1e5, amounts[0]/1e5);
        assertEq(refund[1]/1e5, amounts[1]/1e5);
    }

    function testLiquidateHasMarginError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(1000);

        vm.expectRevert(bytes4(keccak256("HasMargin()")));
        pool.liquidate(tokenId, new int256[](0), new uint256[](0));
    }

    ///////////////////////////////////////
    ////////// PARTIAL LIQUIDATE //////////
    ///////////////////////////////////////
    function testLiquidateWithLp(uint256 lpAmount) public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        lpAmount = bound(lpAmount, 1e18, lpTokens/10);
        uint256 lpInvariant = convertLPToInvariant(lpAmount);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(45000000);

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount);
        IGammaPool.LoanData memory loanData = pool.loan(tokenId);

        (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateWithLP(tokenId);

        assertEq(loanLiquidity/1e3, lpInvariant/1e3);
        assertEq(refund[0], loanData.tokensHeld[0] * lpInvariant / loanData.liquidity);
        assertEq(refund[1], loanData.tokensHeld[1] * lpInvariant / loanData.liquidity);
    }
    function testLiquidateNoLpError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        vm.expectRevert(bytes4(keccak256("NoLiquidityProvided()")));
        pool.liquidateWithLP(tokenId);
    }

    ///////////////////////////////////////
    ////////// BATCH LIQUIDATE ////////////
    ///////////////////////////////////////
    function testBatchLiquidate() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan();   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1);
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan();   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2);
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        // Send enough lp tokens for full liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpTokens * 4/5);

        IGammaPool.LoanData memory loanData1 = pool.loan(tokenId1);
        IGammaPool.LoanData memory loanData2 = pool.loan(tokenId2);
        uint256 loanCollateral1 = calcInvariant(loanData1.tokensHeld);
        uint256 loanCollateralExLiqFee1 = loanCollateral1 * (10000 - 250) / 10000;
        uint256 loanCollateral2 = calcInvariant(loanData2.tokensHeld);
        uint256 loanCollateralExLiqFee2 = loanCollateral2 * (10000 - 250) / 10000;

        uint256 loanCollateralForLiq = loanCollateral1 + loanCollateral2;
        uint256[] memory amounts = calcTokensFromInvariant(loanCollateralForLiq);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        (uint256 totalLoanLiquidity, uint256 totalCollateral, uint256[] memory refund) = pool.batchLiquidations(tokenIds);

        assertEq(totalLoanLiquidity, loanCollateralExLiqFee1 + loanCollateralExLiqFee2);
        assertEq(totalCollateral, loanCollateral1 + loanCollateral2);
        assertEq(refund[0], amounts[0]);
        assertEq(refund[1], amounts[1]);
    }

    function testBatchNoFullLiquidationError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan();   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1);
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan();   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2);
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(100000000);

        // Send insufficient lp tokens for full liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpTokens/2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectRevert(bytes4(keccak256("NotFullLiquidation()")));
        pool.batchLiquidations(tokenIds);
    }

    function testBatchLiquidateNoDebtError() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);

        uint256 tokenId1 = pool.createLoan();   // Loan 1
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId1);
        pool.borrowLiquidity(tokenId1, lpTokens/4, new uint256[](0));

        uint256 tokenId2 = pool.createLoan();   // Loan 2
        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);
        pool.increaseCollateral(tokenId2);
        pool.borrowLiquidity(tokenId2, lpTokens/4, new uint256[](0));

        vm.roll(1000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectRevert(bytes4(keccak256("NoLiquidityDebt()")));
        pool.batchLiquidations(tokenIds);
    }
}
