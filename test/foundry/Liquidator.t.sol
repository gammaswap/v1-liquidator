// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract LiquidatorTest is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

    function testBorrowAndRebalance(uint8 num1, uint8 num2) public {
        if(num1 == 0) {
            num1++;
        }
        if(num2 == 0) {
            num2++;
        }
        if(num1 == num2) {
            if(num1 < 255) {
                num1++;
            } else {
                num1--;
            }
        }

        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * 1e18 / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2000 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1;
        ratio[1] = uint256(reserve1) * num2;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/100, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();

        uint256 diff = strikePx > desiredRatio ? strikePx - desiredRatio : desiredRatio - strikePx;
        assertEq(diff/1e12,0);
    }

    function testFailBorrowAndRebalance() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 20;
        ratio[1] = reserve1 * 210; // Margin error

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertLt(desiredRatio,price);

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();
        assertEq(strikePx/1e9,desiredRatio/1e9);
    }

    function testFailBorrowAndRebalanceWrongRatio() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](1);
        ratio[0] = reserve0 * 3;
        //ratio[1] = reserve1 * 2; // Margin error
        //ratio[2] = 210000;

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);


        vm.stopPrank();
    }

    function testFailBorrowAndRebalanceWrongRatio2() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 3;
        //ratio[1] = reserve1 * 2; // Margin error
        //ratio[2] = 210000;

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);


        vm.stopPrank();
    }

    function testFailBorrowAndRebalanceWrongRatio3() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[1] = reserve0 * 3;
        //ratio[1] = reserve1 * 2; // Margin error
        //ratio[2] = 210000;

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);


        vm.stopPrank();
    }

    function testLowerStrikePx() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 3;
        ratio[1] = reserve1 * 2;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertLt(desiredRatio,price);

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();
        assertEq(strikePx/1e9,desiredRatio/1e9);
    }

    function testHigherStrikePx() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 2;
        ratio[1] = reserve1 * 3;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertGt(desiredRatio,price);

        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();
        assertEq(strikePx/1e9,desiredRatio/1e9); // will be off slightly because of different reserve quantities
    }

    function testPxUpCloseFullToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, new uint256[](0), 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = pool.loan(tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseFullToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, new uint256[](0), 2, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = pool.loan(tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseHalfToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, new uint256[](0), 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = pool.loan(tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseHalfToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, new uint256[](0), 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = pool.loan(tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseFullToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, new uint256[](0), 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = pool.loan(tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseFullToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, new uint256[](0), 2, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = pool.loan(tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseHalfToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, new uint256[](0), 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = pool.loan(tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseHalfToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, new uint256[](0), 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = pool.loan(tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseToken0(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256[] memory fees = new uint256[](2);
        fees[0] = 0;
        fees[1] = _amountIn > 100 ? 1 : 0; // adding a bit more otherwise if price changed too much we get MinBorrow error

        uint256 liquidityPaid;
        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        (liquidityPaid,) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, fees, 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);

        loanData = pool.loan(tokenId);
        if(liquidityDiv == 1) {
            assertEq(loanData.tokensHeld[0],0);
            if(fees[1] > 0) {
                assertGt(loanData.tokensHeld[1],0);
            } else {
                assertEq(loanData.tokensHeld[1],0);
            }
        } else {
            assertGt(loanData.tokensHeld[0],0);
            assertGt(loanData.tokensHeld[1],0);
        }

        assertGt(usdc.balanceOf(addr1), usdcBal0);
        assertGt(weth.balanceOf(addr1), wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseToken1(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, new uint256[](0), 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);

        loanData = pool.loan(tokenId);
        if(liquidityDiv == 1) {
            assertEq(loanData.tokensHeld[0],0);
            assertEq(loanData.tokensHeld[1],0);
        } else {
            assertGt(loanData.tokensHeld[0],0);
            assertGt(loanData.tokensHeld[1],0);
        }

        assertGt(usdc.balanceOf(addr1), usdcBal0);
        assertGt(weth.balanceOf(addr1), wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseToken0(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, new uint256[](0), 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);

        loanData = pool.loan(tokenId);
        if(liquidityDiv == 1) {
            assertEq(loanData.tokensHeld[0],0);
            assertEq(loanData.tokensHeld[1],0);
        } else {
            assertGt(loanData.tokensHeld[0],0);
            assertGt(loanData.tokensHeld[1],0);
        }

        assertGt(usdc.balanceOf(addr1), usdcBal0);
        assertGt(weth.balanceOf(addr1), wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseToken1(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan();
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId);
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IUniswapV2Pair(cfmm).getReserves();

        {
            uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        uint256[] memory fees = new uint256[](2);
        fees[0] = _amountIn > 100 ? 1 : 0; // adding a bit more otherwise if price changed too much we get MinBorrow error
        fees[1] = 0;
        (liquidityPaid,) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, fees, 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);

        loanData = pool.loan(tokenId);
        if(liquidityDiv == 1) {
            if(fees[0] > 0) {
                assertGt(loanData.tokensHeld[0],0);
            } else {
                assertEq(loanData.tokensHeld[0],0);
            }
            assertEq(loanData.tokensHeld[1],0);
        } else {
            assertGt(loanData.tokensHeld[0],0);
            assertGt(loanData.tokensHeld[1],0);
        }

        assertGt(usdc.balanceOf(addr1), usdcBal0);
        assertGt(weth.balanceOf(addr1), wethBal0);

        vm.stopPrank();
    }
}
