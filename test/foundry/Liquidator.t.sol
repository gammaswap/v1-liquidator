// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
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
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);  // After a while

        (uint256 liquidity, uint256 collateral) = liquidator.canLiquidate(address(pool), tokenId);
        assertGt(liquidity, 0);
        assertGt(collateral, 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        address cfmm = pool.cfmm();
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr1);
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0]/1e3, 0);
        assertGt(loanData.tokensHeld[1]/1e3, 0);

        liquidator.liquidate(address(pool), tokenId, addr1);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        uint256 afterBalance = IERC20(cfmm).balanceOf(addr1);
        assertGt(afterBalance, beforeBalance);

        assertFalse(viewer.canLiquidate(address(pool), tokenId));

        // All paid out! No collateral left
        assertEq(loanData1.tokensHeld[0]/1e3, 0);
        assertEq(loanData1.tokensHeld[1]/1e3, 0);
    }

    function testLiquidateFullTo() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000);  // After a while

        (uint256 liquidity, uint256 collateral) = liquidator.canLiquidate(address(pool), tokenId);
        assertGt(liquidity, 0);
        assertGt(collateral, 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        address cfmm = pool.cfmm();
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr2);
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0]/1e3, 0);
        assertGt(loanData.tokensHeld[1]/1e3, 0);

        liquidator.liquidate(address(pool), tokenId, addr2);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        uint256 afterBalance = IERC20(cfmm).balanceOf(addr2);
        assertGt(afterBalance, beforeBalance);

        assertFalse(viewer.canLiquidate(address(pool), tokenId));

        // All paid out! No collateral left
        assertEq(loanData1.tokensHeld[0]/1e3, 0);
        assertEq(loanData1.tokensHeld[1]/1e3, 0);
    }

    function testFailLiquidatePartialWithLp(uint256 lpAmount) public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        lpAmount = bound(lpAmount, 1e18, lpTokens/10);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000); // After a while

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), lpAmount);
        liquidator.liquidateWithLP(address(pool), tokenId, lpAmount, false, addr1);
    }

    function testLiquidateFullWithLp() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000); // After a while

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        console.log(convertInvariantToLP(loanData.liquidity));

        address cfmm = pool.cfmm();
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        liquidator.liquidateWithLP(address(pool), tokenId, 0, true, addr1);
        assertFalse(viewer.canLiquidate(address(pool), tokenId));

        uint256 afterBalance = IERC20(cfmm).balanceOf(addr1);
        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);

        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        uint256 usdcDiff = usdcBal1 - usdcBal0;
        uint256 wethDiff = wethBal1 - wethBal0;
        assertGt(afterBalance + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)),beforeBalance);
        assertEq((afterBalance + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)) * 975/1000)/10,beforeBalance/10);
    }

    function testLiquidateFullWithLpTo() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.roll(100000000); // After a while

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        console.log(convertInvariantToLP(loanData.liquidity));

        address cfmm = pool.cfmm();
        IERC20(cfmm).transfer(addr2,1000);
        uint256 beforeBalanceSender = IERC20(cfmm).balanceOf(addr1);
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr2);
        assertEq(beforeBalance, 1000);
        uint256 usdcBal0 = usdc.balanceOf(addr2);
        uint256 wethBal0 = weth.balanceOf(addr2);

        liquidator.liquidateWithLP(address(pool), tokenId, 0, true, addr2);
        assertFalse(viewer.canLiquidate(address(pool), tokenId));

        uint256 afterBalanceSender = IERC20(cfmm).balanceOf(addr1);
        uint256 afterBalance = IERC20(cfmm).balanceOf(addr2);
        uint256 usdcBal1 = usdc.balanceOf(addr2);
        uint256 wethBal1 = weth.balanceOf(addr2);

        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        uint256 usdcDiff = usdcBal1 - usdcBal0;
        uint256 wethDiff = wethBal1 - wethBal0;
        assertEq(afterBalance,beforeBalance);
        assertGt(afterBalanceSender + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)),beforeBalanceSender);
        assertEq((afterBalanceSender + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)) * 975/1000)/10,beforeBalanceSender/10);
    }

    function testLiquidateBatch() public {
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

        vm.roll(50000000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        assertTrue(viewer.canLiquidate(address(pool), tokenId1));
        assertTrue(viewer.canLiquidate(address(pool), tokenId2));

        (uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) = liquidator.canBatchLiquidate(address(pool), tokenIds);
        assertGt(_liquidity, 0);
        assertGt(_collateral, 0);
        assertEq(tokenIds[0], _tokenIds[0]);
        assertEq(tokenIds[1], _tokenIds[1]);

        address cfmm = pool.cfmm();
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        liquidator.batchLiquidate(address(pool), tokenIds, addr1);

        assertFalse(viewer.canLiquidate(address(pool), tokenId1));
        assertFalse(viewer.canLiquidate(address(pool), tokenId2));

        uint256 afterBalance = IERC20(cfmm).balanceOf(addr1);
        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);

        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        uint256 usdcDiff = usdcBal1 - usdcBal0;
        uint256 wethDiff = wethBal1 - wethBal0;
        assertGt(afterBalance + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)),beforeBalance);
        assertEq((afterBalance + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)) * 975/1000)/10,beforeBalance/10);
    }

    function testLiquidateBatchTo() public {
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

        vm.roll(50000000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        assertTrue(viewer.canLiquidate(address(pool), tokenId1));
        assertTrue(viewer.canLiquidate(address(pool), tokenId2));

        (uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) = liquidator.canBatchLiquidate(address(pool), tokenIds);
        assertGt(_liquidity, 0);
        assertGt(_collateral, 0);
        assertEq(tokenIds[0], _tokenIds[0]);
        assertEq(tokenIds[1], _tokenIds[1]);

        address cfmm = pool.cfmm();
        IERC20(cfmm).transfer(addr2, 1000);

        uint256 beforeBalanceSender = IERC20(cfmm).balanceOf(addr1);
        uint256 beforeBalance = IERC20(cfmm).balanceOf(addr2);
        assertEq(beforeBalance, 1000);
        uint256 usdcBal0 = usdc.balanceOf(addr2);
        uint256 wethBal0 = weth.balanceOf(addr2);

        GammaSwapLibrary.safeApprove(cfmm, address(liquidator), type(uint256).max);
        liquidator.batchLiquidate(address(pool), tokenIds, addr2);

        assertFalse(viewer.canLiquidate(address(pool), tokenId1));
        assertFalse(viewer.canLiquidate(address(pool), tokenId2));

        uint256 afterBalanceSender = IERC20(cfmm).balanceOf(addr1);
        uint256 afterBalance = IERC20(cfmm).balanceOf(addr2);
        uint256 usdcBal1 = usdc.balanceOf(addr2);
        uint256 wethBal1 = weth.balanceOf(addr2);

        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        uint256 usdcDiff = usdcBal1 - usdcBal0;
        uint256 wethDiff = wethBal1 - wethBal0;
        assertEq(afterBalance, beforeBalance);
        assertGt(afterBalanceSender + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)),beforeBalanceSender);
        assertEq((afterBalanceSender + convertInvariantToLP(GSMath.sqrt(usdcDiff * wethDiff)) * 975/1000)/10,beforeBalanceSender/10);
    }
}
