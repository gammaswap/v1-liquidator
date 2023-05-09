// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/Math.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";
import "../../contracts/Liquidator.sol";

contract LiquidatorTest is CPMMGammaSwapSetup {
    Liquidator liquidator;

    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);

        liquidator = new Liquidator();
    }

    ////////////////////////////////////
    ////////// FULL LIQUIDATE //////////
    ////////////////////////////////////
    function testLiquidateFull() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);  // After a while

        (uint256 liquidity, uint256 collateral) = liquidator.canLiquidate(address(pool), tokenId);
        assertGt(liquidity, 0);
        assertGt(collateral, 0);

        liquidator.liquidate(address(pool), tokenId, 0, new uint256[](0));
        IGammaPool.LoanData memory loanData = pool.loan(tokenId);

        assertFalse(IGammaPool(pool).canLiquidate(tokenId));

        // All paid out! No collateral left
        assertEq(loanData.tokensHeld[0], 0);
        assertEq(loanData.tokensHeld[1], 0);
    }

    function testLiquidatePartialWithLp(uint256 lpAmount) public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        lpAmount = bound(lpAmount, 1e18, lpTokens/10);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);  // After a while

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), lpAmount);
        liquidator.liquidateWithLP(address(pool), tokenId, lpAmount, false);
    }

    function testLiquidateFullWithLp() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId);
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);  // After a while

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        liquidator.liquidateWithLP(address(pool), tokenId, 0, true);

        assertFalse(IGammaPool(pool).canLiquidate(tokenId));
    }

    function testLiquidateBatch() public {
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

        vm.roll(50000000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        assertTrue(IGammaPool(pool).canLiquidate(tokenId1));
        assertTrue(IGammaPool(pool).canLiquidate(tokenId2));

        (uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) = liquidator.canBatchLiquidate(address(pool), tokenIds);
        assertGt(_liquidity, 0);
        assertGt(_collateral, 0);
        assertEq(tokenIds[0], _tokenIds[0]);
        assertEq(tokenIds[1], _tokenIds[1]);

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        liquidator.batchLiquidate(address(pool), tokenIds);

        assertFalse(IGammaPool(pool).canLiquidate(tokenId1));
        assertFalse(IGammaPool(pool).canLiquidate(tokenId2));
    }
}
