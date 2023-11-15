// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMShortStrategyFuzz is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap(true);

        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        /*depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        // 18x6 = usdc/weth6
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        // 6x18 = usdc6/weth
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool6x18, cfmm6x18, addr2);

        // 6x6 = weth6/usdc6
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);/**/
    }

    function testDepositReserves18x18(uint24 usdcAmount, uint24 wethAmount, uint24 wethDeposit) public {
        usdcAmount = usdcAmount / 10;
        wethAmount = wethAmount / 10;
        if(usdcAmount == 0) {
            usdcAmount = 1;
        }
        if(wethAmount == 0) {
            wethAmount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc), address(weth), uint256(usdcAmount)*1e18, uint256(wethAmount)*1e18, addr1);

        vm.startPrank(addr1);

        wethDeposit = wethDeposit / 10;

        if(wethDeposit == 0) {
            wethDeposit = 1;
        }

        uint256 amount0 = uint256(wethDeposit) * 1e18;
        uint256[] memory amountsDesired = new uint256[](2);
        amountsDesired[0] = IERC20(weth).balanceOf(addr1)  < amount0 ? IERC20(weth).balanceOf(addr1) : amount0;

        uint256 amount1 = (amountsDesired[0] * usdcAmount / wethAmount);
        amountsDesired[1] = IERC20(usdc).balanceOf(addr1)  < amount1 ? IERC20(usdc).balanceOf(addr1) : amount1;

        if(amount1 != amountsDesired[1]) {
            amountsDesired[0] = (amountsDesired[1] * wethAmount / usdcAmount);
        }

        uint256[] memory amountsMin = new uint256[](2);

        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            deadline: type(uint256).max,
            amountsDesired: amountsDesired,
            amountsMin: amountsMin
        });

        (uint256[] memory reserves, uint256 shares) = posMgr.depositReserves(params);

        uint256 diff = amountsDesired[0] > reserves[0] ? amountsDesired[0] - reserves[0] : reserves[0] - amountsDesired[0];
        assertEq(diff/1e6, 0);

        diff = amountsDesired[1] > reserves[1] ? amountsDesired[1] - reserves[1] : reserves[1] - amountsDesired[1];
        assertEq(diff/1e6, 0);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        uint256 reserve0 = poolData.LP_TOKEN_BALANCE * IERC20(address(weth)).balanceOf(address(cfmm)) / IERC20(cfmm).totalSupply();
        uint256 reserve1 = poolData.LP_TOKEN_BALANCE * IERC20(address(usdc)).balanceOf(address(cfmm)) / IERC20(cfmm).totalSupply();

        amount0 = shares * reserve0 / IERC20(address(pool)).totalSupply();
        amount1 = shares * reserve1 / IERC20(address(pool)).totalSupply();

        diff = amount0 > reserves[0] ? amount0 - reserves[0] : reserves[0] - amount0;
        assertEq(diff/1e8, 0);

        diff = amount1 > reserves[1] ? amount1 - reserves[1] : reserves[1] - amount1;
        assertEq(diff/1e8, 0);

        vm.stopPrank();
    }

    function testDepositNoPull18x18(uint24 usdcAmount, uint24 wethAmount, uint80 cfmmDeposit) public {
        usdcAmount = usdcAmount / 10;
        wethAmount = wethAmount / 10;
        if(usdcAmount == 0) {
            usdcAmount = 1;
        }
        if(wethAmount == 0) {
            wethAmount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc), address(weth), uint256(usdcAmount)*1e18, uint256(wethAmount)*1e18, addr1);

        vm.startPrank(addr1);

        if(cfmmDeposit <= 2*1e4 ) {
            cfmmDeposit = 2*1e4; // if too small can cause a rounding error
        }

        cfmmDeposit = cfmmDeposit / 2;

        uint256 lpTokenDeposit = IERC20(cfmm).balanceOf(addr1) < uint256(cfmmDeposit) ? IERC20(cfmm).balanceOf(addr1) : uint256(cfmmDeposit);
        uint256 remainingDeposit = IERC20(cfmm).balanceOf(addr1) - lpTokenDeposit;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: lpTokenDeposit
        });

        uint256 shares = posMgr.depositNoPull(params);

        assertEq(shares, lpTokenDeposit - 1000);

        if(remainingDeposit > 0) {
            params = IPositionManager.DepositWithdrawParams({
                protocolId: 1,
                cfmm: cfmm,
                to: addr1,
                deadline: type(uint256).max,
                lpTokens: remainingDeposit
            });
            shares = posMgr.depositNoPull(params);
            assertEq(shares, remainingDeposit);
        }

        assertEq(IERC20(cfmm).balanceOf(address(pool)),lpTokenDeposit + remainingDeposit);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        assertEq(poolData.LP_TOKEN_BALANCE,lpTokenDeposit + remainingDeposit);

        vm.stopPrank();
    }
}
