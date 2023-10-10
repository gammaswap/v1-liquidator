// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMShortStrategyTest is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

    function testSyncWithMint() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);
        uint256 lpTokens1 = IERC20(cfmm).balanceOf(address(addr1));
        assertGt(lpTokens1, 0);
        vm.startPrank(addr1);
        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory data = pool.getPoolData();

        pool.mint(1, addr1);
        IGammaPool.PoolData memory data1 = pool.getPoolData();
        assertGt(data1.LP_INVARIANT, data.LP_INVARIANT);
        assertGt(data1.LP_TOKEN_BALANCE, data.LP_TOKEN_BALANCE);

        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(cfmm).getReserves();
        uint256 cfmmInvariant = GSMath.sqrt(reserve0 * reserve1);
        assertEq(data1.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));
        assertEq(data1.LP_INVARIANT, data1.LP_TOKEN_BALANCE * cfmmInvariant / IERC20(cfmm).totalSupply());
        assertEq(data1.totalSupply, data.totalSupply + 1);
    }

    function testSkimCFMM() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);
        uint256 lpTokens1 = IERC20(cfmm).balanceOf(address(addr1));
        assertGt(lpTokens1, 0);
        vm.startPrank(addr1);
        IERC20(cfmm).transfer(address(pool), 100);

        assertEq(IERC20(cfmm).balanceOf(addr1), lpTokens1 - 100);

        IGammaPool.PoolData memory data = pool.getPoolData();
        assertEq(data.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)) - 100);

        pool.skim(addr1);

        assertEq(IERC20(cfmm).balanceOf(addr1), lpTokens1);
        assertEq(data.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));
    }

    function testSkimTokens() public {
        uint256 wethTokens = weth.balanceOf(address(pool));
        assertEq(wethTokens, 0);
        uint256 usdcTokens = usdc.balanceOf(address(pool));
        assertEq(usdcTokens, 0);
        uint256 wethTokensAddr1 = weth.balanceOf(address(addr1));
        assertGt(wethTokensAddr1, 100);
        uint256 usdcTokensAddr1 = usdc.balanceOf(address(addr1));
        assertGt(usdcTokensAddr1, 100);

        IGammaPool.PoolData memory data = pool.getPoolData();
        assertEq(data.TOKEN_BALANCE[0], wethTokens);
        assertEq(data.TOKEN_BALANCE[1], usdcTokens);

        vm.startPrank(addr1);
        weth.transfer(address(pool), 100);
        usdc.transfer(address(pool), 100);

        assertEq(weth.balanceOf(addr1), wethTokensAddr1 - 100);
        assertEq(usdc.balanceOf(addr1), usdcTokensAddr1 - 100);

        data = pool.getPoolData();

        pool.skim(addr1);

        assertEq(weth.balanceOf(addr1), wethTokensAddr1);
        assertEq(usdc.balanceOf(addr1), usdcTokensAddr1);

        assertEq(data.TOKEN_BALANCE[0], weth.balanceOf(address(pool)));
        assertEq(data.TOKEN_BALANCE[1], usdc.balanceOf(address(pool)));
    }

    function testClearTokens() public {
        uint256 usdtTokens = usdt.balanceOf(address(pool));
        assertEq(usdtTokens, 0);

        uint256 usdtTokensAddr1 = usdt.balanceOf(address(addr1));
        assertGt(usdtTokensAddr1, 0);

        vm.startPrank(addr1);
        usdt.transfer(address(pool), 100);

        assertEq(usdt.balanceOf(addr1), usdtTokensAddr1 - 100);
        assertEq(usdt.balanceOf(address(pool)), 100);

        pool.clearToken(address(usdt), addr1, 100);

        assertEq(usdt.balanceOf(addr1), usdtTokensAddr1);
        assertEq(usdt.balanceOf(address(pool)), 0);
    }
}
