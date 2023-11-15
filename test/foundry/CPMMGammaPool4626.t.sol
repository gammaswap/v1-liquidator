// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMGammaPool4626 is CPMMGammaSwapSetup {
    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr1);

        vm.startPrank(addr1);
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 100_000 * 1e18);
        weth.transfer(address(pool), 100 * 1e18);
        pool.increaseCollateral(tokenId, new uint256[](0));

        pool.borrowLiquidity(tokenId, lpTokens/10, new uint256[](0));
        vm.stopPrank();
    }

    function testParams() public {
        (address feeTo, uint256 protocolFee,,) = factory.getPoolFee(address(pool));
        assertEq(feeTo, owner);
        assertEq(protocolFee, 10000);   // Default fee of 10%
    }

    function testTotalSupply() public {
        uint256 totalSupply0 = pool.totalSupply();

        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));
        assertEq(totalSupply0, poolData.totalSupply);
        assertGe(poolData.lastFeeIndex, 1e18);
        assertGt(poolData.utilizationRate, 0);

        vm.roll(10000);

        poolData = viewer.getLatestPoolData(address(pool));
        uint256 totalSupply = IShortStrategy(shortStrategy).totalSupply(
            address(factory), address(pool), poolData.lastCFMMFeeIndex, poolData.lastFeeIndex, poolData.utilizationRate, poolData.totalSupply
        );

        assertGt(totalSupply, totalSupply0);
        // TODO
        // assertEq(totalSupply, pool.totalSupply());
    }

    function testTotalAssets() public {
        uint256 totalAssets0 = pool.totalAssets();

        vm.roll(10000);

        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));
        (, uint256 lastCFMMInvariant, uint256 lastCFMMTotalSupply) = pool.getLatestCFMMBalances();
        uint256 totalAssets = IShortStrategy(shortStrategy).totalAssets(
            poolData.BORROWED_INVARIANT, poolData.LP_TOKEN_BALANCE, lastCFMMInvariant, lastCFMMTotalSupply, poolData.lastFeeIndex
        );

        assertGt(totalAssets, totalAssets0);
        // TODO
        // assertEq(totalAssets, pool.totalAssets());
    }

    function testPreview() public {
        assertEq(pool.balanceOf(addr2), 0);

        vm.startPrank(addr2);
        uint256 lpToDeposit = IERC20(cfmm).balanceOf(addr2) / 5;
        pool.deposit(lpToDeposit, addr2);
        vm.stopPrank();

        assertGt(pool.balanceOf(addr2), 0);
        uint256 redeemable = pool.previewRedeem(pool.balanceOf(addr2));
        assertApproxEqAbs(redeemable, lpToDeposit, 1e2);

        vm.roll(10000);

        assertGt(pool.previewRedeem(pool.balanceOf(addr2)), redeemable);    // addr2 earned rewards
        redeemable = pool.previewRedeem(pool.balanceOf(addr2));
        uint256 lpBalanceBeforeRedeem = IERC20(cfmm).balanceOf(addr2);

        vm.startPrank(addr2);
        pool.redeem(pool.balanceOf(addr2), addr2, addr2);
        uint256 lpBalanceAfterRedeem = IERC20(cfmm).balanceOf(addr2);
        vm.stopPrank();

        assertEq(lpBalanceAfterRedeem - lpBalanceBeforeRedeem, redeemable);
    }
}