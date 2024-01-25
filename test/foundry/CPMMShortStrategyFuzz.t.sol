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
        lockProtocol();
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

        assertApproxEqAbs(amountsDesired[0], reserves[0], 1e8);
        assertApproxEqAbs(amountsDesired[1], reserves[1], 1e8);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        uint256 reserve0 = poolData.LP_TOKEN_BALANCE * IERC20(address(weth)).balanceOf(address(cfmm)) / IERC20(cfmm).totalSupply();
        uint256 reserve1 = poolData.LP_TOKEN_BALANCE * IERC20(address(usdc)).balanceOf(address(cfmm)) / IERC20(cfmm).totalSupply();

        amount0 = shares * reserve0 / IERC20(address(pool)).totalSupply();
        amount1 = shares * reserve1 / IERC20(address(pool)).totalSupply();

        assertApproxEqAbs(amount0, reserves[0], 1e8);
        assertApproxEqAbs(amount1, reserves[1], 1e8);

        vm.stopPrank();
    }
    function testDepositReserves18x6(uint24 usdcAmount, uint24 weth6Amount, uint24 weth6Deposit) public {
        usdcAmount = usdcAmount / 10;
        weth6Amount = weth6Amount / 10;
        if(usdcAmount == 0) {
            usdcAmount = 1;
        }
        if(weth6Amount == 0) {
            weth6Amount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), uint256(usdcAmount)*1e18, uint256(weth6Amount)*1e6, addr1);

        vm.startPrank(addr1);

        weth6Deposit = weth6Deposit / 10;

        if(weth6Deposit == 0) {
            weth6Deposit = 1;
        }

        uint256 amount1 = uint256(weth6Deposit) * 1e6;
        uint256[] memory amountsDesired = new uint256[](2);
        amountsDesired[1] = IERC20(weth6).balanceOf(addr1) < amount1 ? IERC20(weth6).balanceOf(addr1) : amount1;

        uint256 amount0 = (amountsDesired[1] * 1e12 * usdcAmount / weth6Amount);
        amountsDesired[0] = IERC20(usdc).balanceOf(addr1) < amount0 ? IERC20(usdc).balanceOf(addr1) : amount0;

        if(amount0 != amountsDesired[0]) {
            amountsDesired[1] = (amountsDesired[0] / 1e12 * weth6Amount / usdcAmount);
        }

        uint256[] memory amountsMin = new uint256[](2);

        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr1,
            deadline: type(uint256).max,
            amountsDesired: amountsDesired,
            amountsMin: amountsMin
        });

        (uint256[] memory reserves, uint256 shares) = posMgr.depositReserves(params);

        assertApproxEqRel(amountsDesired[0], reserves[0], 1e13);    // 0.001% delta
        assertApproxEqRel(amountsDesired[1], reserves[1], 1e13);    // 0.001% delta

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();

        uint256 reserve0 = poolData.LP_TOKEN_BALANCE * IERC20(address(usdc)).balanceOf(address(cfmm18x6)) / IERC20(cfmm18x6).totalSupply();
        uint256 reserve1 = poolData.LP_TOKEN_BALANCE * IERC20(address(weth6)).balanceOf(address(cfmm18x6)) / IERC20(cfmm18x6).totalSupply();

        amount0 = shares * reserve0 / IERC20(address(pool18x6)).totalSupply();
        amount1 = shares * reserve1 / IERC20(address(pool18x6)).totalSupply();

        assertApproxEqRel(amount0, reserves[0], 1e14);    // 0.01% delta
        assertApproxEqRel(amount1, reserves[1], 1e14);    // 0.01% delta

        vm.stopPrank();
    }
    function testDepositReserves6x6(uint24 usdc6Amount, uint24 weth6Amount, uint24 weth6Deposit) public {
        lockProtocol();
        usdc6Amount = usdc6Amount / 10;
        weth6Amount = weth6Amount / 10;
        if(usdc6Amount == 0) {
            usdc6Amount = 1;
        }
        if(weth6Amount == 0) {
            weth6Amount = 1;
        }
        if (usdc6Amount < weth6Amount) {
            (weth6Amount, usdc6Amount) = (usdc6Amount, weth6Amount);
        }
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), uint256(usdc6Amount)*1e6, uint256(weth6Amount)*1e6, addr1);

        vm.startPrank(addr1);

        weth6Deposit = weth6Deposit / 10;

        if(weth6Deposit == 0) {
            weth6Deposit = 1;
        }

        uint256 amount1 = uint256(weth6Deposit) * 1e6;
        uint256[] memory amountsDesired = new uint256[](2);
        amountsDesired[1] = IERC20(weth6).balanceOf(addr1) < amount1 ? IERC20(weth6).balanceOf(addr1) : amount1;

        uint256 amount0 = (amountsDesired[1] * usdc6Amount / weth6Amount);
        amountsDesired[0] = IERC20(usdc6).balanceOf(addr1) < amount0 ? IERC20(usdc6).balanceOf(addr1) : amount0;

        if(amount0 != amountsDesired[0]) {
            amountsDesired[1] = amountsDesired[0] * weth6Amount / usdc6Amount;
        }
        uint256[] memory amountsMin = new uint256[](2);

        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr1,
            deadline: type(uint256).max,
            amountsDesired: amountsDesired,
            amountsMin: amountsMin
        });

        (uint256[] memory reserves, uint256 shares) = posMgr.depositReserves(params);

        assertApproxEqRel(amountsDesired[0], reserves[0], 1e13);    // 0.001% delta
        assertApproxEqRel(amountsDesired[1], reserves[1], 1e13);    // 0.001% delta

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();

        uint256 reserve0 = poolData.LP_TOKEN_BALANCE * IERC20(address(usdc6)).balanceOf(address(cfmm6x6)) / IERC20(cfmm6x6).totalSupply();
        uint256 reserve1 = poolData.LP_TOKEN_BALANCE * IERC20(address(weth6)).balanceOf(address(cfmm6x6)) / IERC20(cfmm6x6).totalSupply();

        amount0 = shares * reserve0 / IERC20(address(pool6x6)).totalSupply();
        amount1 = shares * reserve1 / IERC20(address(pool6x6)).totalSupply();

        assertApproxEqRel(amount0, reserves[0], 125e13); // 0.125% delta
        assertApproxEqRel(amount1, reserves[1], 125e13); // 0.125% delta

        vm.stopPrank();
    }
    function testDepositReserves6x8(uint24 usdc6Amount, uint24 weth8Amount, uint24 weth8Deposit) public {
        lockProtocol();
        usdc6Amount = usdc6Amount / 10;
        weth8Amount = weth8Amount / 10;
        if(usdc6Amount == 0) {
            usdc6Amount = 1;
        }
        if(weth8Amount == 0) {
            weth8Amount = 1;
        }
        if (usdc6Amount < weth8Amount) {
            (weth8Amount, usdc6Amount) = (usdc6Amount, weth8Amount);
        }
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), uint256(usdc6Amount)*1e6, uint256(weth8Amount)*1e8, addr1);

        vm.startPrank(addr1);

        weth8Deposit = weth8Deposit / 10;

        if(weth8Deposit == 0) {
            weth8Deposit = 1;
        }

        uint256 amount1 = uint256(weth8Deposit) * 1e8;
        uint256[] memory amountsDesired = new uint256[](2);
        amountsDesired[1] = IERC20(weth8).balanceOf(addr1) < amount1 ? IERC20(weth8).balanceOf(addr1) : amount1;

        uint256 amount0 = (amountsDesired[1] * uint256(usdc6Amount) * 1e6 / (uint256(weth8Amount) * 1e8));
        amountsDesired[0] = IERC20(usdc6).balanceOf(addr1) < amount0 ? IERC20(usdc6).balanceOf(addr1) : amount0;

        uint256[] memory amountsMin = new uint256[](2);

        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: cfmm6x8,
            to: addr1,
            deadline: type(uint256).max,
            amountsDesired: amountsDesired,
            amountsMin: amountsMin
        });

        (uint256[] memory reserves, uint256 shares) = posMgr.depositReserves(params);

        assertApproxEqRel(amountsDesired[0], reserves[0], 1e13);    // 0.001% delta
        assertApproxEqRel(amountsDesired[1], reserves[1], 1e13);    // 0.001% delta

        IGammaPool.PoolData memory poolData = pool6x8.getPoolData();

        uint256 reserve0 = poolData.LP_TOKEN_BALANCE * IERC20(address(usdc6)).balanceOf(address(cfmm6x8)) / IERC20(cfmm6x8).totalSupply();
        uint256 reserve1 = poolData.LP_TOKEN_BALANCE * IERC20(address(weth8)).balanceOf(address(cfmm6x8)) / IERC20(cfmm6x8).totalSupply();

        amount0 = shares * reserve0 / IERC20(address(pool6x8)).totalSupply();
        amount1 = shares * reserve1 / IERC20(address(pool6x8)).totalSupply();

        assertApproxEqRel(amount0, reserves[0], 125e13); // 0.125% delta
        assertApproxEqRel(amount1, reserves[1], 125e13); // 0.125% delta

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

        assertEq(IERC20(cfmm).balanceOf(address(pool)), lpTokenDeposit + remainingDeposit);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        assertEq(poolData.LP_TOKEN_BALANCE, lpTokenDeposit + remainingDeposit);

        vm.stopPrank();
    }
    function testDepositNoPull18x6(uint24 usdcAmount, uint24 weth6Amount, uint80 cfmmDeposit) public {
        lockProtocol();
        usdcAmount = usdcAmount / 10;
        weth6Amount = weth6Amount / 10;
        if(usdcAmount == 0) {
            usdcAmount = 1;
        }
        if(weth6Amount == 0) {
            weth6Amount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), uint256(usdcAmount)*1e18, uint256(weth6Amount)*1e6, addr1);

        vm.startPrank(addr1);

        if(cfmmDeposit <= 2*1e4 ) {
            cfmmDeposit = 2*1e4; // if too small can cause a rounding error
        }

        cfmmDeposit = cfmmDeposit / 2;

        uint256 lpTokenDeposit = IERC20(cfmm18x6).balanceOf(addr1) < uint256(cfmmDeposit) ? IERC20(cfmm18x6).balanceOf(addr1) : uint256(cfmmDeposit);
        uint256 remainingDeposit = IERC20(cfmm18x6).balanceOf(addr1) - lpTokenDeposit;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: lpTokenDeposit
        });

        uint256 shares = posMgr.depositNoPull(params);

        assertEq(shares, lpTokenDeposit - 1000);

        if(remainingDeposit > 0) {
            params = IPositionManager.DepositWithdrawParams({
                protocolId: 1,
                cfmm: cfmm18x6,
                to: addr1,
                deadline: type(uint256).max,
                lpTokens: remainingDeposit
            });
            shares = posMgr.depositNoPull(params);
            assertEq(shares, remainingDeposit);
        }

        assertEq(IERC20(cfmm18x6).balanceOf(address(pool18x6)), lpTokenDeposit + remainingDeposit);

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();

        assertEq(poolData.LP_TOKEN_BALANCE, lpTokenDeposit + remainingDeposit);

        vm.stopPrank();
    }
    function testDepositNoPull6x6(uint24 usdc6Amount, uint24 weth6Amount, uint80 cfmmDeposit) public {
        usdc6Amount = usdc6Amount / 10;
        weth6Amount = weth6Amount / 10;
        if(usdc6Amount == 0) {
            usdc6Amount = 1;
        }
        if(weth6Amount == 0) {
            weth6Amount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), uint256(usdc6Amount)*1e6, uint256(weth6Amount)*1e6, addr1);

        vm.startPrank(addr1);

        if(cfmmDeposit <= 2*1e4 ) {
            cfmmDeposit = 2*1e4; // if too small can cause a rounding error
        }

        cfmmDeposit = cfmmDeposit / 2;

        uint256 lpTokenDeposit = IERC20(cfmm6x6).balanceOf(addr1) < uint256(cfmmDeposit) ? IERC20(cfmm6x6).balanceOf(addr1) : uint256(cfmmDeposit);
        uint256 remainingDeposit = IERC20(cfmm6x6).balanceOf(addr1) - lpTokenDeposit;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: lpTokenDeposit
        });

        uint256 shares = posMgr.depositNoPull(params);

        assertEq(shares, lpTokenDeposit - 1000);

        if(remainingDeposit > 0) {
            params = IPositionManager.DepositWithdrawParams({
                protocolId: 1,
                cfmm: cfmm6x6,
                to: addr1,
                deadline: type(uint256).max,
                lpTokens: remainingDeposit
            });
            shares = posMgr.depositNoPull(params);
            assertEq(shares, remainingDeposit);
        }

        assertEq(IERC20(cfmm6x6).balanceOf(address(pool6x6)), lpTokenDeposit + remainingDeposit);

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();

        assertEq(poolData.LP_TOKEN_BALANCE, lpTokenDeposit + remainingDeposit);

        vm.stopPrank();
    }
    function testDepositNoPull6x8(uint24 usdc6Amount, uint24 weth8Amount, uint80 cfmmDeposit) public {
        usdc6Amount = usdc6Amount / 10;
        weth8Amount = weth8Amount / 10;
        if(usdc6Amount == 0) {
            usdc6Amount = 1;
        }
        if(weth8Amount == 0) {
            weth8Amount = 1;
        }
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), uint256(usdc6Amount)*1e6, uint256(weth8Amount)*1e8, addr1);

        vm.startPrank(addr1);

        if(cfmmDeposit <= 2*1e4 ) {
            cfmmDeposit = 2*1e4; // if too small can cause a rounding error
        }

        cfmmDeposit = cfmmDeposit / 2;

        uint256 lpTokenDeposit = IERC20(cfmm6x8).balanceOf(addr1) < uint256(cfmmDeposit) ? IERC20(cfmm6x8).balanceOf(addr1) : uint256(cfmmDeposit);
        uint256 remainingDeposit = IERC20(cfmm6x8).balanceOf(addr1) - lpTokenDeposit;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm6x8,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: lpTokenDeposit
        });

        uint256 shares = posMgr.depositNoPull(params);

        assertEq(shares, lpTokenDeposit - 1000);

        if(remainingDeposit > 0) {
            params = IPositionManager.DepositWithdrawParams({
                protocolId: 1,
                cfmm: cfmm6x8,
                to: addr1,
                deadline: type(uint256).max,
                lpTokens: remainingDeposit
            });
            shares = posMgr.depositNoPull(params);
            assertEq(shares, remainingDeposit);
        }

        assertEq(IERC20(cfmm6x8).balanceOf(address(pool6x8)), lpTokenDeposit + remainingDeposit);

        IGammaPool.PoolData memory poolData = pool6x8.getPoolData();

        assertEq(poolData.LP_TOKEN_BALANCE, lpTokenDeposit + remainingDeposit);

        vm.stopPrank();
    }

    function testWithdrawReserves18x18(uint80 amount) public {
        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e3) {
            amount = 1e3;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            deadline: type(uint256).max,
            amount: gsLpAmount,
            amountsMin: new uint256[](2)
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm).balanceOf(address(pool)) / IERC20(address(pool)).totalSupply();

        (uint256[] memory reserves, uint256 assets) = posMgr.withdrawReserves(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);

        uint256 wethReceived = IERC20(weth).balanceOf(cfmm) * assets / IERC20(cfmm).totalSupply();
        uint256 usdcReceived = IERC20(usdc).balanceOf(cfmm) * assets / IERC20(cfmm).totalSupply();

        assertApproxEqAbs(reserves[0], wethReceived, 1e1);
        assertApproxEqAbs(reserves[1], usdcReceived, 1e1);

        vm.stopPrank();
    }
    function testWithdrawReserves18x6(uint80 amount) public {
        lockProtocol();
        uint256 usdcAmount = 2_500_000 / 2;
        uint256 weth6Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, weth6Amount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, weth6Amount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e8) {
            amount = 1e8;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool18x6)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr1,
            deadline: type(uint256).max,
            amount: gsLpAmount,
            amountsMin: new uint256[](2)
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm18x6).balanceOf(address(pool18x6)) / IERC20(address(pool18x6)).totalSupply();

        (uint256[] memory reserves, uint256 assets) = posMgr.withdrawReserves(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool18x6)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);

        uint256 weth6Received = IERC20(weth6).balanceOf(cfmm18x6) * assets / IERC20(cfmm18x6).totalSupply();
        uint256 usdcReceived = IERC20(usdc).balanceOf(cfmm18x6) * assets / IERC20(cfmm18x6).totalSupply();

        assertApproxEqAbs(reserves[1], weth6Received, 1e1);
        assertApproxEqAbs(reserves[0], usdcReceived, 1e1);

        vm.stopPrank();
    }
    function testWithdrawReserves6x6(uint80 amount) public {
        lockProtocol();
        uint256 usdc6Amount = 2_500_000 / 2;
        uint256 weth6Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdc6Amount*1e6, weth6Amount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdc6Amount*1e6, weth6Amount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e8) {
            amount = 1e8;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool6x6)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr1,
            deadline: type(uint256).max,
            amount: gsLpAmount,
            amountsMin: new uint256[](2)
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm6x6).balanceOf(address(pool6x6)) / IERC20(address(pool6x6)).totalSupply();

        (uint256[] memory reserves, uint256 assets) = posMgr.withdrawReserves(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool6x6)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);

        uint256 weth6Received = IERC20(weth6).balanceOf(cfmm6x6) * assets / IERC20(cfmm6x6).totalSupply();
        uint256 usdc6Received = IERC20(usdc6).balanceOf(cfmm6x6) * assets / IERC20(cfmm6x6).totalSupply();

        assertApproxEqAbs(reserves[1], weth6Received, 1e1);
        assertApproxEqAbs(reserves[0], usdc6Received, 1e1);

        vm.stopPrank();
    }
    function testWithdrawReserves6x8(uint80 amount) public {
        lockProtocol();
        uint256 usdc6Amount = 2_500_000 / 2;
        uint256 weth8Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), usdc6Amount*1e6, weth8Amount*1e8, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), usdc6Amount*1e6, weth8Amount*1e8, addr2);
        depositLiquidityInPoolFromCFMM(pool6x8, cfmm6x8, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e8) {
            amount = 1e8;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool6x8)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: cfmm6x8,
            to: addr1,
            deadline: type(uint256).max,
            amount: gsLpAmount,
            amountsMin: new uint256[](2)
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm6x8).balanceOf(address(pool6x8)) / IERC20(address(pool6x8)).totalSupply();

        (uint256[] memory reserves, uint256 assets) = posMgr.withdrawReserves(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool6x8)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);

        uint256 weth8Received = IERC20(weth8).balanceOf(cfmm6x8) * assets / IERC20(cfmm6x8).totalSupply();
        uint256 usdc6Received = IERC20(usdc6).balanceOf(cfmm6x8) * assets / IERC20(cfmm6x8).totalSupply();

        assertApproxEqAbs(reserves[1], weth8Received, 1e1);
        assertApproxEqAbs(reserves[0], usdc6Received, 1e1);

        vm.stopPrank();
    }

    function testWithdrawNoPull18x18(uint80 amount) public {
        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e3) {
            amount = 1e3;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool)).balanceOf(addr1);
        uint256 beforeCfmmBalance = IERC20(address(cfmm)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: gsLpAmount
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm).balanceOf(address(pool)) / IERC20(address(pool)).totalSupply();

        uint256 assets = posMgr.withdrawNoPull(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool)).balanceOf(addr1);
        uint256 afterCfmmBalance = IERC20(address(cfmm)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);
        assertEq(assets, afterCfmmBalance - beforeCfmmBalance);

        vm.stopPrank();
    }
    function testWithdrawNoPull18x6(uint80 amount) public {
        uint256 usdcAmount = 2_500_000 / 2;
        uint256 weth6Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, weth6Amount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, weth6Amount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e3) {
            amount = 1e3;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool18x6)).balanceOf(addr1);
        uint256 beforeCfmmBalance = IERC20(address(cfmm18x6)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: gsLpAmount
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm18x6).balanceOf(address(pool18x6)) / IERC20(address(pool18x6)).totalSupply();

        uint256 assets = posMgr.withdrawNoPull(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool18x6)).balanceOf(addr1);
        uint256 afterCfmmBalance = IERC20(address(cfmm18x6)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);
        assertEq(assets, afterCfmmBalance - beforeCfmmBalance);

        vm.stopPrank();
    }
    function testWithdrawNoPull6x6(uint80 amount) public {
        lockProtocol();
        uint256 usdc6Amount = 2_500_000 / 2;
        uint256 weth6Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdc6Amount*1e6, weth6Amount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdc6Amount*1e6, weth6Amount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e3) {
            amount = 1e3;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool6x6)).balanceOf(addr1);
        uint256 beforeCfmmBalance = IERC20(address(cfmm6x6)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: gsLpAmount
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm6x6).balanceOf(address(pool6x6)) / IERC20(address(pool6x6)).totalSupply();

        uint256 assets = posMgr.withdrawNoPull(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool6x6)).balanceOf(addr1);
        uint256 afterCfmmBalance = IERC20(address(cfmm6x6)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);
        assertEq(assets, afterCfmmBalance - beforeCfmmBalance);

        vm.stopPrank();
    }
    function testWithdrawNoPull6x8(uint80 amount) public {
        lockProtocol();
        uint256 usdc6Amount = 2_500_000 / 2;
        uint256 weth8Amount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), usdc6Amount*1e6, weth8Amount*1e8, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth8), usdc6Amount*1e6, weth8Amount*1e8, addr2);
        depositLiquidityInPoolFromCFMM(pool6x8, cfmm6x8, addr2);

        vm.startPrank(addr1);

        if(amount <= 1e3) {
            amount = 1e3;
        }

        uint256 beforeGSLPBalance = IERC20(address(pool6x8)).balanceOf(addr1);
        uint256 beforeCfmmBalance = IERC20(address(cfmm6x8)).balanceOf(addr1);
        uint256 gsLpAmount = beforeGSLPBalance < amount ? beforeGSLPBalance : amount;

        IPositionManager.DepositWithdrawParams memory params = IPositionManager.DepositWithdrawParams({
            protocolId: 1,
            cfmm: cfmm6x8,
            to: addr1,
            deadline: type(uint256).max,
            lpTokens: gsLpAmount
        });

        vm.roll(100);

        uint256 expectedAssets = gsLpAmount * IERC20(cfmm6x8).balanceOf(address(pool6x8)) / IERC20(address(pool6x8)).totalSupply();

        uint256 assets = posMgr.withdrawNoPull(params);

        assertEq(assets, expectedAssets);

        uint256 afterGSLPBalance = IERC20(address(pool6x8)).balanceOf(addr1);
        uint256 afterCfmmBalance = IERC20(address(cfmm6x8)).balanceOf(addr1);

        assertEq(gsLpAmount, beforeGSLPBalance - afterGSLPBalance);
        assertEq(assets, afterCfmmBalance - beforeCfmmBalance);

        vm.stopPrank();
    }
}
