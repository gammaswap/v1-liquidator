// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/test/strategies/external/TestExternalCallee2.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMLongStrategyTest is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap(false);
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

    function testBorrowMoreMinBorrow() public {
        uint72 minBorrow = 2e18;
        setPoolParams(address(pool), 10, 0, 10, 100, 100, 1, 250, 200, minBorrow);// setting base origination fee to 10, disable dynamic part

        (, uint256 cfmmInvariant, uint256 cfmmTotalSupply) = IGammaPool(pool).getLatestCFMMBalances();
        uint256 lpTokens = minBorrow * cfmmTotalSupply / cfmmInvariant;
        assertGt(lpTokens, 0);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 5*1e18;
        _amounts[1] = 5_000*1e18;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: 32, // minimum amount of LP tokens you can burn in CFMM
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });
        vm.expectRevert(bytes4(keccak256("MinBorrow()")));
        posMgr.createLoanBorrowAndRebalance(params);

        params.lpTokens = lpTokens;
        vm.expectRevert(bytes4(keccak256("MinBorrow()")));
        posMgr.createLoanBorrowAndRebalance(params);

        params.lpTokens = lpTokens + 1;
        (uint256 tokenId,,,) = posMgr.createLoanBorrowAndRebalance(params);

        IGammaPool.LoanData memory loanData = IGammaPool(pool).loan(tokenId);
        uint256 initLiquidity0 = loanData.initLiquidity;
        assertGt(initLiquidity0, 0);

        IPositionManager.BorrowLiquidityParams memory params2 = IPositionManager.BorrowLiquidityParams({
            protocolId: 1,
            cfmm: cfmm,
            tokenId: tokenId,
            lpTokens: 32,
            ratio: new uint256[](0),
            deadline: type(uint256).max,
            minBorrowed: new uint256[](2),
            maxBorrowed: type(uint256).max,
            minCollateral: new uint128[](2)
        });
        posMgr.borrowLiquidity(params2);

        loanData = IGammaPool(pool).loan(tokenId);
        assertGt(loanData.initLiquidity, initLiquidity0);
        vm.stopPrank();
    }

    function testBorrowAndRebalanceSlippageUp() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 lpTokens = 3000 * 1e18;
        assertGt(lpTokens, 0);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 50*1e18;
        _amounts[1] = 50_000*1e18;

        vm.startPrank(addr1);
        uint256 poolBalance = IERC20(address(pool)).balanceOf(addr1);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 3;
        ratio[1] = reserve1;

        // actual tokensHeld
        //216144 806073 333229 151542
        //    72 048268 691111 076383

        uint128[] memory minCollateral = new uint128[](2);
        minCollateral[0] = 216145 * 1e18; // minimum collateral acceptable. Therefore, if collateral is 216144 it fails. Must be >= 216145
        minCollateral[1] = 73 * 1e18; // minimum collateral acceptable. Therefore, if collateral is 72 it fails. Must be >= 73
        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: lpTokens,
            ratio: ratio,
            minBorrowed: new uint256[](2),
            minCollateral: minCollateral,
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });
        vm.expectRevert(
            abi.encodeWithSelector(PositionManager.AmountsMin.selector, 2)
        );
        posMgr.createLoanBorrowAndRebalance(params);

        vm.stopPrank();
    }

    function testBorrowAndRebalanceSlippageDown() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 lpTokens = 3000 * 1e18;
        assertGt(lpTokens, 0);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 50*1e18;
        _amounts[1] = 50_000*1e18;

        vm.startPrank(addr1);
        uint256 poolBalance = IERC20(address(pool)).balanceOf(addr1);

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0;
        ratio[1] = reserve1 * 3;

        // actual tokensHeld
        //    72 048268 691111 076383
        //216144 806073 333229 151542

        uint128[] memory minCollateral = new uint128[](2);
        minCollateral[0] = 73 * 1e18; // minimum collateral acceptable. Therefore, if collateral is 72 it fails. Must be >= 73
        minCollateral[1] = 216145 * 1e18; // minimum collateral acceptable. Therefore, if collateral is 216144 it fails. Must be >= 216145
        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: lpTokens,
            ratio: ratio,
            minBorrowed: new uint256[](2),
            minCollateral: minCollateral,
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });
        vm.expectRevert(
            abi.encodeWithSelector(PositionManager.AmountsMin.selector, 2)
        );
        posMgr.createLoanBorrowAndRebalance(params);

        vm.stopPrank();
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

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * 1e18 / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2000 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1;
        ratio[1] = uint256(reserve1) * num2;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];

        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/100, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        vm.stopPrank();

        uint256 diff = strikePx > desiredRatio ? strikePx - desiredRatio : desiredRatio - strikePx;
        assertEq(diff/1e8,0);
    }

    function testBorrowAndRebalanceSync(uint8 num1, uint8 num2) public {
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

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * 1e18 / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2000 * 1e18);

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1;
        ratio[1] = uint256(reserve1) * num2;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];

        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/100, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        vm.stopPrank();

        uint256 diff = strikePx > desiredRatio ? strikePx - desiredRatio : desiredRatio - strikePx;
        assertEq(diff/1e8,0);
    }

    function testBorrowAndRebalanceWithMarginError() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 20;
        ratio[1] = reserve1 * 210; // Margin error

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertGt(desiredRatio,price);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.borrowLiquidity(tokenId, lpTokens/4, ratio);
    }

    function testBorrowAndRebalanceWrongRatio() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](1);
        ratio[0] = reserve0 * 3;

        uint256 lpTokensToBorrow = lpTokens/4;

        uint256 totSupply = IERC20(cfmm).totalSupply();
        uint256 expAmount0 = lpTokensToBorrow * reserve0 / totSupply;
        uint256 expAmount1 = lpTokensToBorrow * reserve1 / totSupply;

        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokensToBorrow, ratio);

        assertEq(expAmount0, amounts[0]);
        assertEq(expAmount1, amounts[1]);

        vm.stopPrank();
    }

    function testBorrowAndRebalanceWrongRatio2() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 3;

        uint256 lpTokensToBorrow = lpTokens/4;

        uint256 totSupply = IERC20(cfmm).totalSupply();
        uint256 expAmount0 = lpTokensToBorrow * reserve0 / totSupply;
        uint256 expAmount1 = lpTokensToBorrow * reserve1 / totSupply;

        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokensToBorrow, ratio);

        assertEq(expAmount0, amounts[0]);
        assertEq(expAmount1, amounts[1]);

        vm.stopPrank();
    }

    function testBorrowAndRebalanceWrongRatio3() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[1] = reserve0 * 3;

        uint256 lpTokensToBorrow = lpTokens/4;

        uint256 totSupply = IERC20(cfmm).totalSupply();
        uint256 expAmount0 = lpTokensToBorrow * reserve0 / totSupply;
        uint256 expAmount1 = lpTokensToBorrow * reserve1 / totSupply;

        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokensToBorrow, ratio);

        assertEq(expAmount0, amounts[0]);
        assertEq(expAmount1, amounts[1]);

        vm.stopPrank();
    }

    function testLowerStrikePx() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 3;
        ratio[1] = reserve1 * 2;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertLt(desiredRatio,price);

        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();
        assertEq(strikePx/1e9,desiredRatio/1e9);
    }

    function testHigherStrikePx() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        uint128[] memory collateral = pool.increaseCollateral(tokenId, new uint256[](0));

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 2;
        ratio[1] = reserve1 * 3;

        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];
        assertGt(desiredRatio,price);

        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/4, ratio);

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        vm.stopPrank();
        assertEq(strikePx/1e9,desiredRatio/1e9); // will be off slightly because of different reserve quantities
    }


    function testPxUpCloseFullToken0Sync() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);
        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseFullToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseFullToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, 2, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseHalfToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxUpCloseHalfToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseFullToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseFullToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity, 2, addr1);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseHalfToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseHalfToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/2, 2, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/2)/1e9);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testPxDownCloseToken0(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityPaid;
        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        (liquidityPaid,) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, 1, addr1);
        assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);

        loanData = viewer.loan(address(pool), tokenId);
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

    function testPxDownCloseToken1(uint8 _amountIn, uint8 _liquidityDiv) public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        weth.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(weth), address(usdc), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertLt(price1,price);

        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        {
            uint256 liquidityPaid;
            (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, 2, addr1);
            assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);
        }
        loanData = viewer.loan(address(pool), tokenId);
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
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        {
            uint256 liquidityPaid;
            (liquidityPaid, amounts) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, 1, addr1);
            assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);
        }
        loanData = viewer.loan(address(pool), tokenId);
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
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        assertGt(IERC20(cfmm).totalSupply(), 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 1000 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  (uint256(_amountIn) + 1) * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);


        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {
            uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityDiv = uint256(_liquidityDiv) + 1;
        {
            uint256 liquidityPaid;
            (liquidityPaid,) = pool.repayLiquidity(tokenId, loanData.liquidity/liquidityDiv, 2, addr1);
            assertEq(liquidityPaid/1e9, (loanData.liquidity/liquidityDiv)/1e9);
        }
        loanData = viewer.loan(address(pool), tokenId);
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

    function testRebalanceBuyCollateral(uint256 collateralId, int256 amount) public {
        collateralId = bound(collateralId, 0, 1);
        if (collateralId == 0) {    // if WETH rebalance
            amount = bound(amount, 1e16, 100*1e18);
        } else {    // if USDC rebalance
            amount = bound(amount, 10*1e18, 1_000_000*1e18);
        }
        if (amount == 0) return;

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        uint128[] memory tokensHeldBefore = new uint128[](2);
        tokensHeldBefore[0] = 2000 * 1e18;
        tokensHeldBefore[1] = 2_000_000 * 1e18;

        weth.transfer(address(pool), tokensHeldBefore[0]);
        usdc.transfer(address(pool), tokensHeldBefore[1]);

        pool.increaseCollateral(tokenId, new uint256[](0));

        int256[] memory deltas = new int256[](2);
        deltas[collateralId] = amount;
        deltas[1 - collateralId] = 0;

        uint128[] memory tokensHeldAfter = pool.rebalanceCollateral(tokenId, deltas, new uint256[](0));
        assertEq(tokensHeldAfter[collateralId], tokensHeldBefore[collateralId] + uint256(amount));
        assertLt(tokensHeldAfter[1-collateralId], tokensHeldBefore[1-collateralId]);
    }

    function testRebalanceSellCollateral(uint256 collateralId, int256 amount) public {
        collateralId = bound(collateralId, 0, 1);
        if (collateralId == 0) {    // if WETH rebalance
            amount = bound(amount, 1e16, 100*1e18);
        } else {    // if USDC rebalance
            amount = bound(amount, 10*1e18, 1_000_000*1e18);
        }
        if (amount == 0) return;

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        uint128[] memory tokensHeldBefore = new uint128[](2);
        tokensHeldBefore[0] = 2000 * 1e18;
        tokensHeldBefore[1] = 2_000_000 * 1e18;

        weth.transfer(address(pool), tokensHeldBefore[0]);
        usdc.transfer(address(pool), tokensHeldBefore[1]);

        pool.increaseCollateral(tokenId, new uint256[](0));

        int256[] memory deltas = new int256[](2);
        deltas[collateralId] = -amount;
        deltas[1 - collateralId] = 0;

        uint128[] memory tokensHeldAfter = pool.rebalanceCollateral(tokenId, deltas, new uint256[](0));
        assertEq(tokensHeldAfter[collateralId], tokensHeldBefore[collateralId] - uint256(amount));
        assertGt(tokensHeldAfter[1-collateralId], tokensHeldBefore[1-collateralId]);
    }

    function testRebalanceWithRatio(uint256 r0, uint256 r1) public {
        r0 = bound(r0, 1, 100);
        r1 = bound(r1, 1, 100);

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * r0;
        ratio[1] = reserve1 * r1;
        uint256 desiredRatio = ratio[1] * 1e18 / ratio[0];

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        uint128[] memory tokensHeldBefore = new uint128[](2);
        tokensHeldBefore[0] = 200 * 1e18;
        tokensHeldBefore[1] = 200_000 * 1e18;

        weth.transfer(address(pool), tokensHeldBefore[0]);
        usdc.transfer(address(pool), tokensHeldBefore[1]);

        pool.increaseCollateral(tokenId, new uint256[](0));

        uint128[] memory tokensHeldAfter = pool.rebalanceCollateral(tokenId, new int256[](0), ratio);
        assertEq((tokensHeldAfter[0] * desiredRatio / 1e18) / 1e15, tokensHeldAfter[1] / 1e15); // Precision of 3 decimals, good enough
    }

    function testRebalanceMarginError() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * 200;
        ratio[1] = reserve1 * 10;

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        weth.transfer(address(pool), 1000 * 1e18);
        usdc.transfer(address(pool), 1_000_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        uint256 lpTokens = IERC20(cfmm).totalSupply();
        pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceCollateral(tokenId, new int256[](0), ratio);
    }

    function testRepayLiquidityWrongCollateral(uint256 collateralId) public {
        collateralId = bound(collateralId, 3, 1000);
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        weth.transfer(address(pool), 200 * 1e18);
        usdc.transfer(address(pool), 200_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);
        assertEq(loanData.tokensHeld[0], 200 * 1e18 + amounts[0]);
        assertEq(loanData.tokensHeld[1], 200_000 * 1e18 + amounts[1]);

        vm.expectRevert();
        pool.repayLiquidity(tokenId, loanData.liquidity, collateralId, address(0));
    }

    /// @dev Try to repay loan debt with huge fees
    function testRepayLiquidityInParts() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 150_000 * 1e18);
        weth.transfer(address(pool), 150 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);
        assertEq(loanData.tokensHeld[0], 150 * 1e18 + amounts[0]);
        assertEq(loanData.tokensHeld[1], 150_000 * 1e18 + amounts[1]);

        pool.repayLiquidity(tokenId, loanData.liquidity/2, 1, addr1);

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        pool.repayLiquidity(tokenId, loanData.liquidity, 2, addr1);
    }

    /// @dev Loan debt increases as time passes
    function testRepayLiquidityBadDebtFuzzed(uint256 blockMult) public {
        blockMult = 100000000 + uint256(bound(blockMult, 1, type(uint16).max));
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData.BORROWED_INVARIANT, 0);
        assertEq(poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertGt(poolData.LP_INVARIANT, 0);
        assertGt(poolData.LP_TOKEN_BALANCE, 0);
        assertEq(poolData.LP_TOKEN_BORROWED, 0);
        assertEq(poolData.utilizationRate, 0);
        assertEq(poolData.accFeeIndex, 1e18);
        assertEq(poolData.currBlockNumber, 1);
        assertEq(poolData.LAST_BLOCK_NUMBER, 1);

        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData1 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT);
        assertGt(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertLt(poolData1.LP_INVARIANT, poolData.LP_INVARIANT);
        assertLt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
        assertGt(poolData1.LP_TOKEN_BORROWED, poolData.LP_TOKEN_BORROWED);
        assertGt(poolData1.utilizationRate, poolData.utilizationRate);
        assertEq(poolData1.accFeeIndex, poolData.accFeeIndex);
        assertEq(poolData1.currBlockNumber, 1);
        assertEq(poolData1.LAST_BLOCK_NUMBER, 1);

        vm.roll(blockMult);  // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData2 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData2.BORROWED_INVARIANT, poolData1.BORROWED_INVARIANT);
        assertGt(poolData2.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData2.LP_INVARIANT, poolData1.LP_INVARIANT);
        assertEq(poolData2.LP_TOKEN_BALANCE, poolData1.LP_TOKEN_BALANCE);
        assertEq(poolData2.LP_TOKEN_BORROWED, poolData1.LP_TOKEN_BORROWED);
        assertGt(poolData2.utilizationRate, poolData1.utilizationRate);
        assertGt(poolData2.accFeeIndex, poolData1.accFeeIndex);
        assertEq(poolData2.currBlockNumber, blockMult);
        assertEq(poolData2.LAST_BLOCK_NUMBER, 1);
        uint256 usdcBal = usdc.balanceOf(addr1);
        uint256 wethBal = weth.balanceOf(addr1);
        uint256 liquidityDebtGrowth = loanData.liquidity - liquidityBorrowed;

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.repayLiquidity(tokenId, loanData.liquidity/2, 1, addr1);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.repayLiquidity(tokenId, loanData.liquidity/2, 2, addr1);
    }

    /// @dev Loan debt increases as time passes
    function testRepayLiquidityBadDebt() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData.BORROWED_INVARIANT, 0);
        assertEq(poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertGt(poolData.LP_INVARIANT, 0);
        assertGt(poolData.LP_TOKEN_BALANCE, 0);
        assertEq(poolData.LP_TOKEN_BORROWED, 0);
        assertEq(poolData.utilizationRate, 0);
        assertEq(poolData.accFeeIndex, 1e18);
        assertEq(poolData.currBlockNumber, 1);
        assertEq(poolData.LAST_BLOCK_NUMBER, 1);

        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData1 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT);
        assertGt(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertLt(poolData1.LP_INVARIANT, poolData.LP_INVARIANT);
        assertLt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
        assertGt(poolData1.LP_TOKEN_BORROWED, poolData.LP_TOKEN_BORROWED);
        assertGt(poolData1.utilizationRate, poolData.utilizationRate);
        assertEq(poolData1.accFeeIndex, poolData.accFeeIndex);
        assertEq(poolData1.currBlockNumber, 1);
        assertEq(poolData1.LAST_BLOCK_NUMBER, 1);

        vm.roll(100000000);  // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData2 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData2.BORROWED_INVARIANT, poolData1.BORROWED_INVARIANT);
        assertGt(poolData2.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData2.LP_INVARIANT, poolData1.LP_INVARIANT);
        assertEq(poolData2.LP_TOKEN_BALANCE, poolData1.LP_TOKEN_BALANCE);
        assertEq(poolData2.LP_TOKEN_BORROWED, poolData1.LP_TOKEN_BORROWED);
        assertGt(poolData2.utilizationRate, poolData1.utilizationRate);
        assertGt(poolData2.accFeeIndex, poolData1.accFeeIndex);
        assertEq(poolData2.currBlockNumber, 100000000);
        assertEq(poolData2.LAST_BLOCK_NUMBER, 1);
        uint256 usdcBal = usdc.balanceOf(addr1);
        uint256 wethBal = weth.balanceOf(addr1);
        uint256 liquidityDebtGrowth = loanData.liquidity - liquidityBorrowed;

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.repayLiquidity(tokenId, loanData.liquidity/2, 1, addr1);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.repayLiquidity(tokenId, loanData.liquidity/2, 2, addr1);
    }

    /// @dev Interest on loan changes if rate params change
    function testBorrowChangeRateParams() public {
        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        vm.roll(100000000);  // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);
        vm.stopPrank();

        IGammaPool.LoanData memory loanData2 = viewer.loan(address(pool), tokenId);
        assertEq(loanData2.liquidity, loanData.liquidity);

        LogRateParams memory params = LogRateParams({ baseRate: 2 * 1e16, optimalUtilRate: 8 * 1e17,
            slope1: 75 * 1e16, slope2: 10 * 1e18});
        factory.setRateParams(address(pool), abi.encode(params), true);

        loanData2 = viewer.loan(address(pool), tokenId);
        assertGt(loanData2.liquidity, loanData.liquidity);

        params = LogRateParams({ baseRate: 2 * 1e16, optimalUtilRate: 8 * 1e17, slope1: 75 * 1e16, slope2: 10 * 1e18});
        factory.setRateParams(address(pool), abi.encode(params), false);

        loanData2 = viewer.loan(address(pool), tokenId);
        assertEq(loanData2.liquidity, loanData.liquidity);
    }

    /// @dev increase collateral without keeping ratio
    function testIncreaseCollateralIgnoreRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4) public {
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1 / 100000;
        ratio[1] = uint256(reserve1) * num2 / 100000;

        uint256 liquidity = GSMath.sqrt(ratio[0] * ratio[1]);
        lpTokens = liquidity * lpTokens / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));

        (uint256 liquidityBorrowed,uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        // increase collateral
        usdc.transfer(address(pool), uint256(num3) * 1e18);
        weth.transfer(address(pool), uint256(num4) * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertGe(loanData1.tokensHeld[0], loanData.tokensHeld[0]);
        assertGe(loanData1.tokensHeld[1], loanData.tokensHeld[1]);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        if(num3 == 0 && num4 == 0) {
            assertEq(strikePx1, strikePx);
        } else {
            assertNotEq(strikePx1, strikePx);
        }
    }

    /// @dev increase collateral and keep ratio the same
    function testIncreaseCollateralKeepRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4) public {
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1 / 100000;
        ratio[1] = uint256(reserve1) * num2 / 100000;

        uint256 cfmmInvariant = GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        uint256 liquidity = GSMath.sqrt(ratio[0] * ratio[1]);
        lpTokens = liquidity * lpTokens / cfmmInvariant;

        uint256 liquidityBorrowed;
        {
            uint256[] memory amounts;
            (liquidityBorrowed,  amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        // increase collateral
        usdc.transfer(address(pool), uint256(num3) * 1e18);
        weth.transfer(address(pool), uint256(num4) * 1e18);

        pool.increaseCollateral(tokenId, ratio);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertGe(loanData1.tokensHeld[0]/1e8, loanData.tokensHeld[0]/1e8);
        assertGe(loanData1.tokensHeld[1]/1e8, loanData.tokensHeld[1]/1e8);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        uint256 diff = strikePx > strikePx1 ? strikePx - strikePx1 : strikePx1 - strikePx;
        assertEq(diff/1e8, 0);
    }

    /// @dev increase collateral and change ratio to a new number
    function testIncreaseCollateralChangeRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4, uint8 num5, bool flip) public {
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));
        num3 = uint16(bound(num3, 10000, type(uint16).max));
        num4 = uint16(bound(num4, 10000, type(uint16).max));
        num5 = uint8(bound(num5, 2, type(uint8).max));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * num1 / 100000;
        ratio[1] = reserve1 * num2 / 100000;

        lpTokens = GSMath.sqrt(ratio[0] * ratio[1]) * lpTokens / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        uint256 liquidityBorrowed;
        {
            uint256[] memory amounts;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        // increase collateral
        usdc.transfer(address(pool), uint256(num3) * 1e18);
        weth.transfer(address(pool), uint256(num4) * 1e18);

        ratio[0] = ratio[0] * (flip ? 1 : num5);
        ratio[1] = ratio[1] * (flip ? num5 : 1);

        pool.increaseCollateral(tokenId, ratio);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertGe(((loanData1.tokensHeld[0] * reserve1 / reserve0) + loanData1.tokensHeld[1])/1e8,
            ((loanData.tokensHeld[0] * reserve1 / reserve0) + loanData.tokensHeld[1])/1e8);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];
        assertNotEq(strikePx1/1e6, strikePx/1e6);

        uint256 expectedStrike = ratio[1] * 1e18 / ratio[0];
        uint256 diff = expectedStrike > strikePx1 ? expectedStrike - strikePx1 : strikePx1 - expectedStrike;
        assertEq(diff/1e15, 0);
    }

    /// @dev increase collateral and change ratio to a number that causes a margin error
    function testIncreaseCollateralChangeRatioMarginError() public {
        (uint16 num1, uint16 num2, uint16 num3, uint16 num4, uint8 num5, bool flip) = (0, 49003, 0, 0, 71, true);
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));
        num3 = uint16(bound(num3, 1000, type(uint16).max));
        num4 = uint16(bound(num4, 1000, type(uint16).max));
        num5 = uint8(bound(num5, 2, type(uint8).max));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * num1 / 100000;
        ratio[1] = reserve1 * num2 / 100000;

        lpTokens = GSMath.sqrt(ratio[0] * ratio[1]) * lpTokens / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));

        (uint256 liquidityBorrowed,uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        // increase collateral
        usdc.transfer(address(pool), uint256(num3) * 1e18);
        weth.transfer(address(pool), uint256(num4) * 1e18);

        ratio[0] = ratio[0] * (flip ? 1 : num5);
        ratio[1] = ratio[1] * (flip ? num5 : 1);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.increaseCollateral(tokenId, ratio);
    }

    /// @dev Decrease collateral without keeping ratio
    function testDecreaseCollateralIgnoreRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4) public {
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));
        num3 = uint16(bound(num3, 0, 4000));
        num4 = uint16(bound(num4, 0, 4000));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2_000_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1 / 100000;
        ratio[1] = uint256(reserve1) * num2 / 100000;

        uint256 cfmmInvariant = GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        uint256 liquidity = GSMath.sqrt(ratio[0] * ratio[1]);
        lpTokens = liquidity * lpTokens / cfmmInvariant;

        uint256 liquidityBorrowed;
        {
            uint256[] memory amounts;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/100, ratio);
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        uint128[] memory amounts1 = new uint128[](2);
        amounts1[0] = uint128(num3) * 1e16;
        amounts1[1] = uint128(num4) * 1e16;
        pool.decreaseCollateral(tokenId, amounts1, addr1, new uint256[](0));

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertLe(loanData1.tokensHeld[0], loanData.tokensHeld[0]);
        assertLe(loanData1.tokensHeld[1], loanData.tokensHeld[1]);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        if(num3 == 0 && num4 == 0) {
            assertEq(strikePx1, strikePx);
        } else {
            assertNotEq(strikePx1, strikePx);
        }
    }

    /// @dev Decrease collateral and keep ratio the same
    function testDecreaseCollateralKeepRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4) public {
        num1 = uint16(bound(num1, 1000, 10000));
        num2 = uint16(bound(num2, 1000, 10000));
        num3 = uint16(bound(num3, 0, 1000));
        num4 = uint16(bound(num4, 0, 1000));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2_000_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1 / 100000;
        ratio[1] = uint256(reserve1) * num2 / 100000;

        uint256 cfmmInvariant = GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        uint256 liquidity = GSMath.sqrt(ratio[0] * ratio[1]);
        lpTokens = liquidity * lpTokens / cfmmInvariant;

        (uint256 liquidityBorrowed,uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        uint128[] memory amounts1 = new uint128[](2);
        amounts1[0] = uint128(num3) * 1e17;
        amounts1[1] = uint128(num4) * 1e17;
        pool.decreaseCollateral(tokenId, amounts1, addr1, ratio);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertLe(loanData1.tokensHeld[0]/1e8, loanData.tokensHeld[0]/1e8);
        assertLe(loanData1.tokensHeld[1]/1e8, loanData.tokensHeld[1]/1e8);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        uint256 diff = strikePx > strikePx1 ? strikePx - strikePx1 : strikePx1 - strikePx;
        assertEq(diff/1e10, 0);
    }

    /// @dev Decrease collateral and change ratio to a new number
    function testDecreaseCollateralChangeRatio(uint16 num1, uint16 num2, uint16 num3, uint16 num4, uint8 num5, bool flip) public {
        num1 = uint16(bound(num1, 1000, 10000));
        num2 = uint16(bound(num2, 1000, 10000));
        num3 = uint16(bound(num3, 0, 100));
        num4 = uint16(bound(num4, 0, 100));
        num5 = uint8(bound(num5, 2, 5));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2_000_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = reserve0 * num1 / 100000;
        ratio[1] = reserve1 * num2 / 100000;

        lpTokens = GSMath.sqrt(ratio[0] * ratio[1]) * lpTokens / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));

        (uint256 liquidityBorrowed,uint256[] memory amounts,uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);
        assertEq(loanData.tokensHeld[0], tokensHeld[0]);
        assertEq(loanData.tokensHeld[1], tokensHeld[1]);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        ratio[0] = ratio[0] * (flip ? 1 : num5);
        ratio[1] = ratio[1] * (flip ? num5 : 1);

        amounts[0] = weth.balanceOf(addr1);
        amounts[1] = usdc.balanceOf(addr1);
        uint128[] memory amounts1 = new uint128[](2);
        amounts1[0] = uint128(num3) * 1e18;
        amounts1[1] = uint128(num4) * 1e18;
        pool.decreaseCollateral(tokenId, amounts1, addr1, ratio);

        assertEq(amounts[0] + amounts1[0], weth.balanceOf(addr1));
        assertEq(amounts[1] + amounts1[1], usdc.balanceOf(addr1));

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertNotEq(((loanData1.tokensHeld[0] * reserve1 / reserve0) + loanData1.tokensHeld[1])/1e8,
            ((loanData.tokensHeld[0] * reserve1 / reserve0) + loanData.tokensHeld[1])/1e8);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];
        assertNotEq(strikePx1/1e6, strikePx/1e6);

        uint256 expectedStrike = ratio[1] * 1e18 / ratio[0];
        uint256 diff = expectedStrike > strikePx1 ? expectedStrike - strikePx1 : strikePx1 - expectedStrike;

        assertEq(diff/1e10, 0);
    }

    /// @dev Decrease collateral and keep ratio the same and cause Margin error
    function testDecreaseCollateralKeepRatioMarginError() public {
        (uint16 num1, uint16 num2, uint16 num3, uint16 num4) = (0, 45038, 133, 0);
        num1 = uint16(bound(num1, 1000, type(uint16).max));
        num2 = uint16(bound(num2, 1000, type(uint16).max));
        num3 = uint16(bound(num3, 0, 1000));
        num4 = uint16(bound(num4, 0, 1000));

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 2_000_000 * 1e18);
        weth.transfer(address(pool), 2_000_000 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = uint256(reserve0) * num1 / 100000;
        ratio[1] = uint256(reserve1) * num2 / 100000;

        uint256 liquidity = GSMath.sqrt(ratio[0] * ratio[1]);
        lpTokens = liquidity * lpTokens / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));

        uint256 liquidityBorrowed;
        {
            uint256[] memory amounts;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/10, ratio);
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        uint128[] memory amounts1 = new uint128[](2);
        amounts1[0] = uint128(num4) * 1e18;
        amounts1[1] = 45 * uint128(num3) * 1e21;
        strikePx = uint256(ratio[1]) * 1e18 / ratio[0];
        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.decreaseCollateral(tokenId, amounts1, addr1, ratio);
        loanData = viewer.loan(address(pool), tokenId);
        strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
    }

    function testRepayLiquidityWithLPFullToken0Sync() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        IERC20(cfmm).transfer(address(pool), lpTokens/4);

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        uint256 liquidityPaid;
        uint128[] memory tokensHeld;
        (liquidityPaid,tokensHeld) = pool.repayLiquidityWithLP(tokenId, 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);
        assertEq(tokensHeld[0],0);
        assertEq(tokensHeld[1],0);

        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquidityWithLPFullToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        IERC20(cfmm).transfer(address(pool), lpTokens/4);

        uint256 liquidityPaid;
        uint128[] memory tokensHeld;
        (liquidityPaid,tokensHeld) = pool.repayLiquidityWithLP(tokenId, 1, addr1);
        assertEq(liquidityPaid, loanData.liquidity);
        assertEq(tokensHeld[0],0);
        assertEq(tokensHeld[1],0);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquidityWithLPFullToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        IERC20(cfmm).transfer(address(pool), lpTokens/4);

        uint256 liquidityPaid;
        uint128[] memory tokensHeld;
        (liquidityPaid,tokensHeld) = pool.repayLiquidityWithLP(tokenId, 2, addr1);
        assertEq(liquidityPaid, loanData.liquidity);
        assertEq(tokensHeld[0],0);
        assertEq(tokensHeld[1],0);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertEq(loanData.tokensHeld[0],0);
        assertEq(loanData.tokensHeld[1],0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquidityWithLPHalfToken0() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 lpTokenDebt = loanData.liquidity * IERC20(cfmm).totalSupply() / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        IERC20(cfmm).transfer(address(pool), lpTokenDebt / 2);

        uint256 liquidityPaid;
        uint128[] memory tokensHeld;
        (liquidityPaid,tokensHeld) = pool.repayLiquidityWithLP(tokenId, 1, addr1);
        assertEq(liquidityPaid/1e3, (loanData.liquidity/2)/1e3);
        uint256 diff = tokensHeld[0] > loanData.tokensHeld[0]/2 ? tokensHeld[0] - loanData.tokensHeld[0]/2 : loanData.tokensHeld[0]/2 - tokensHeld[0];
        assertEq(diff/1e3,0);
        diff = tokensHeld[1] > loanData.tokensHeld[1]/2 ? tokensHeld[1] - loanData.tokensHeld[1]/2 : loanData.tokensHeld[1]/2 - tokensHeld[1];
        assertEq(diff/1e3,0);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity/1e3,(loanData.liquidity/2)/1e3);
        uint256 oldTokensHeld = loanData.tokensHeld[0]/2;
        diff = loanData1.tokensHeld[0] > oldTokensHeld ? loanData1.tokensHeld[0] - oldTokensHeld :
            oldTokensHeld - loanData1.tokensHeld[0];
        assertEq(diff/1e3,0);
        oldTokensHeld = loanData.tokensHeld[1]/2;
        diff = loanData1.tokensHeld[1] > oldTokensHeld ? loanData1.tokensHeld[1] - oldTokensHeld :
        oldTokensHeld - loanData1.tokensHeld[1];
        assertEq(diff/1e3,0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertGt(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquidityWithLPHalfToken1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        {
            (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 lpTokenDebt = loanData.liquidity * IERC20(cfmm).totalSupply() / GSMath.sqrt(uint256(reserve0) * uint256(reserve1));
        IERC20(cfmm).transfer(address(pool), lpTokenDebt / 2);

        uint256 liquidityPaid;
        uint128[] memory tokensHeld;
        (liquidityPaid,tokensHeld) = pool.repayLiquidityWithLP(tokenId, 2, addr1);
        assertEq(liquidityPaid/1e3, (loanData.liquidity/2)/1e3);
        uint256 diff = tokensHeld[0] > loanData.tokensHeld[0]/2 ? tokensHeld[0] - loanData.tokensHeld[0]/2 : loanData.tokensHeld[0]/2 - tokensHeld[0];
        assertEq(diff/1e3,0);
        diff = tokensHeld[1] > loanData.tokensHeld[1]/2 ? tokensHeld[1] - loanData.tokensHeld[1]/2 : loanData.tokensHeld[1]/2 - tokensHeld[1];
        assertEq(diff/1e3,0);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity/1e3,(loanData.liquidity/2)/1e3);
        uint256 oldTokensHeld = loanData.tokensHeld[0]/2;
        diff = loanData1.tokensHeld[0] > oldTokensHeld ? loanData1.tokensHeld[0] - oldTokensHeld :
        oldTokensHeld - loanData1.tokensHeld[0];
        assertEq(diff/1e3,0);
        oldTokensHeld = loanData.tokensHeld[1]/2;
        diff = loanData1.tokensHeld[1] > oldTokensHeld ? loanData1.tokensHeld[1] - oldTokensHeld :
        oldTokensHeld - loanData1.tokensHeld[1];
        assertEq(diff/1e3,0);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertGt(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioFullSync() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = loanData.tokensHeld[1];

        IERC20(cfmm).transfer(address(pool), 100);
        IGammaPool.PoolData memory poolData = pool.getPoolData();
        assertLt(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity, ratio);
        assertEq(liquidityPaid, loanData.liquidity);
        poolData = pool.getPoolData();
        assertEq(poolData.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);
        assertApproxEqRel(uint256(loanData.tokensHeld[1])*1e18/uint256(loanData.tokensHeld[0]),ratio[1]*1e18/ratio[0],6*1e16);
        assertEq(loanData.tokensHeld[0]/1e18,663);
        assertEq(loanData.tokensHeld[1]/1e18,627492);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioFull() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = loanData.tokensHeld[1];

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity, ratio);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);
        assertEq(loanData.tokensHeld[0]/1e18,663);
        assertEq(loanData.tokensHeld[1]/1e18,627492);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioHalf() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = loanData.tokensHeld[1];

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
        assertEq(liquidityPaid/1e6, (loanData.liquidity/2)/1e6);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity/1e6,liquidityPaid/1e6);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 strikePx1 = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(loanData.tokensHeld[0]/1e18,682);
        assertEq(loanData.tokensHeld[1]/1e18,662542);
        assertApproxEqRel(uint256(loanData.tokensHeld[1])*1e18/loanData.tokensHeld[0],ratio[1]*1e18/ratio[0],3*1e16);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioHalfNullRatio() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](0);

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
        assertEq(liquidityPaid/1e6, (loanData.liquidity/2)/1e6);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity/1e6,liquidityPaid/1e6);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        uint256 strikePx1 = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(loanData.tokensHeld[0]/1e18,682);
        assertEq(loanData.tokensHeld[1]/1e18,662542);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioHalfWrongRatio() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](3);

        uint256 strikePx1 = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
        assertEq(liquidityPaid/1e6, (loanData.liquidity/2)/1e6);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity/1e6,liquidityPaid/1e6);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);

        assertEq(loanData.tokensHeld[0]/1e18,682);
        assertEq(loanData.tokensHeld[1]/1e18,662542);
        assertApproxEqRel(uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], strikePx1, 3*1e16);
        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioHalfWrong1() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e3,price/1e3);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = 0;
        ratio[1] = 0;

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        assertApproxEqRel(strikePx1, strikePx, 3*1e16);
    }

    function testRepayLiquiditySetRatioHalfWrong2() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e3,price/1e3);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = 0;

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        assertApproxEqRel(strikePx1, strikePx, 3*1e16);
    }

    function testRepayLiquiditySetRatioHalfWrong3() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e3,price/1e3);

        uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(amountIn, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price1, 0);
        assertGt(price1,price);

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = 0;
        ratio[1] = loanData.tokensHeld[1];

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);

        uint256 strikePx1 = uint256(loanData1.tokensHeld[1]) * 1e18 / loanData1.tokensHeld[0];

        assertApproxEqRel(strikePx1, strikePx, 3*1e16);
    }

    function testRepayLiquiditySetRatioFullChange(uint8 num1, uint8 num2) public {
        num1 = uint8(bound(num1, 1, 10));
        num2 = uint8(bound(num2, 1, 10));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256[] memory amounts;
        {
            uint256 liquidityBorrowed;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        //uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(1_000_000 * 1e18, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {
            uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0]*num1;
        ratio[1] = loanData.tokensHeld[1]*num2;

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity, ratio);
        assertEq(liquidityPaid, loanData.liquidity);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity,0);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);
        strikePx = (ratio[1]*(10**18)/ratio[0]);
        strikePx = (strikePx*(10000) + strikePx*200)/10000;
        assertLe(uint256(loanData.tokensHeld[1])*(10**18)/uint256(loanData.tokensHeld[0]),strikePx);
        strikePx = (ratio[1]*(10**18)/ratio[0]);
        strikePx = (strikePx*(10000) - strikePx*200)/10000;
        assertGe(uint256(loanData.tokensHeld[1])*(10**18)/uint256(loanData.tokensHeld[0]),strikePx);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioHalfChange(uint8 num1, uint8 num2) public {
        num1 = uint8(bound(num1, 1, 3));
        num2 = uint8(bound(num2, 1, 3));
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256[] memory amounts;
        {
            uint256 liquidityBorrowed;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        sellTokenIn(1_000_000 * 1e18, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {
            uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0]*num1;
        ratio[1] = loanData.tokensHeld[1]*num2;

        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
        assertEq(liquidityPaid/1e6, (loanData.liquidity/2)/1e6);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity/1e6,liquidityPaid/1e6);
        assertGt(loanData.tokensHeld[0],0);
        assertGt(loanData.tokensHeld[1],0);
        strikePx = (ratio[1]*(10**18)/ratio[0]);
        strikePx = (strikePx*(10000) + strikePx*100)/10000;
        assertLe(uint256(loanData.tokensHeld[1])*(10**18)/uint256(loanData.tokensHeld[0]),strikePx);
        strikePx = (ratio[1]*(10**18)/ratio[0]);
        strikePx = (strikePx*(10000) - strikePx*100)/10000;
        assertGe(uint256(loanData.tokensHeld[1])*(10**18)/uint256(loanData.tokensHeld[0]),strikePx);

        uint256 usdcBal1 = usdc.balanceOf(addr1);
        uint256 wethBal1 = weth.balanceOf(addr1);
        assertEq(usdcBal1, usdcBal0);
        assertEq(wethBal1, wethBal0);

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatioRebalMargin() public {
        uint8 num1 = 45;
        uint8 num2 = 11;
        num1 = uint8(bound(num1, 1, 10));
        num2 = uint8(bound(num2, 1, 10));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256[] memory amounts;
        {
            uint256 liquidityBorrowed;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        //uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(1_000_000 * 1e18, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {
            uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0]*num1;
        ratio[1] = loanData.tokensHeld[1]*num2;

        vm.expectRevert(bytes4(keccak256("Margin()")));
        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
    }

    function testRepayLiquiditySetRatioHalfMargin() public {
        uint8 num1 = 45;
        uint8 num2 = 11;
        num1 = uint8(bound(num1, 1, 10));
        num2 = uint8(bound(num2, 1, 10));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256[] memory amounts;
        {uint256 liquidityBorrowed;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        vm.roll(100000000);  // After a while
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        //uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(1_000_000 * 1e18, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = loanData.tokensHeld[1];

        vm.expectRevert(bytes4(keccak256("Margin()")));
        (liquidityPaid,) = pool.repayLiquiditySetRatio(tokenId, loanData.liquidity/2, ratio);
    }

    // test undercollateralized closes that pay in full also
    function testRepayLiquiditySetRatioFullBadDebt() public {
        uint8 num1 = 45;
        uint8 num2 = 11;
        num1 = uint8(bound(num1, 1, 10));
        num2 = uint8(bound(num2, 1, 10));

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256[] memory amounts;
        {
            uint256 liquidityBorrowed;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }
        IPoolViewer viewer = IPoolViewer(pool.viewer());

        vm.roll(100000000);  // After a while
        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, 0);

        uint256 strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        assertEq(strikePx/1e9,price/1e9);

        //uint256 amountIn =  100 * 1_000_000 * 1e18;
        sellTokenIn(1_000_000 * 1e18, address(usdc), address(weth), addr1);
        uint256 usdcBal0 = usdc.balanceOf(addr1);
        uint256 wethBal0 = weth.balanceOf(addr1);

        (reserve0, reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        {uint256 price1 = uint256(reserve1) * (1e18) / reserve0;
            assertGt(price1, 0);
            assertGt(price1,price);
        }

        uint256 liquidityPaid;
        uint256[] memory ratio = new uint256[](2);
        ratio[0] = loanData.tokensHeld[0];
        ratio[1] = loanData.tokensHeld[1];

        vm.expectRevert(bytes4(keccak256("NotEnoughCollateral()")));
        pool.repayLiquiditySetRatio(tokenId, loanData.liquidity, ratio);
    }

    function calcDiff(uint256 num1, uint256 num2) internal view returns(uint256 diff) {
        diff = num1 > num2 ? num1 - num2 : num2 - num1;
    }

    function testOriginationFee() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lastCFMMInvariant = GSMath.sqrt(uint256(reserve0) * reserve1);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts, uint128[] memory tokensHeld) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertEq(tokensHeld[0], 200 * 1e18 + amounts[0]);
        assertEq(tokensHeld[1], 200_000 * 1e18 + amounts[1]);

        assertEq(liquidityBorrowed, poolData.LP_INVARIANT/8);

        vm.stopPrank();

        poolData = viewer.getLatestPoolData(address(pool));

        setPoolParams(address(pool), 10, 0, 10, 100, 100, 1, 250, 200, 1e18);// setting base origination fee to 10, disable dynamic part

        vm.startPrank(addr1);

        (uint256 liquidityBorrowed1, uint256[] memory amounts1,) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        uint256 fee = liquidityBorrowed * 10 / 10000;
        assertEq(calcDiff(liquidityBorrowed1, liquidityBorrowed + fee)/1e2, 0);
        assertEq(calcDiff(amounts1[0], amounts[0])/1e2,0);
        assertEq(calcDiff(amounts1[1], amounts[1])/1e2,0);

        vm.stopPrank();

        poolData = viewer.getLatestPoolData(address(pool));
        // 32768 => 2^15 = 2^(maxUtilRate - 24) => maxUtilRate = 39
        setPoolParams(address(pool), 10, 0, 10, 24, 100, 32768, 250, 200, 1e18);// setting base origination fee to 10, enable dynamic part from 24% to 39% utilRate

        vm.startPrank(addr1);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);
        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed2, uint256[] memory amounts2,) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        assertGt(calcDiff(liquidityBorrowed2, liquidityBorrowed + fee)/1e2, 0);
        assertEq(calcDiff(amounts2[0], amounts[0])/1e2,0);
        assertEq(calcDiff(amounts2[1], amounts[1])/1e2,0);

        fee = liquidityBorrowed * 2500 / 10000;
        assertEq(calcDiff(liquidityBorrowed2, liquidityBorrowed + fee)/1e2, 0);

        vm.stopPrank();
    }

    function testOriginationFeeLinear() public {
        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * (1e18) / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lastCFMMInvariant = GSMath.sqrt(uint256(reserve0) * reserve1);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        usdc.mint(addr1, 100 * 1_000_000 * 1e18);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        assertEq(liquidityBorrowed, poolData.LP_INVARIANT/8);

        vm.stopPrank();

        poolData = viewer.getLatestPoolData(address(pool));

        setPoolParams(address(pool), 10, 0, 10, 100, 100, 1, 250, 200, 1e18);// setting base origination fee to 10, disable dynamic part

        vm.startPrank(addr1);

        (uint256 liquidityBorrowed1, uint256[] memory amounts1,) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        uint256 fee = liquidityBorrowed * 10 / 10000;
        assertEq(calcDiff(liquidityBorrowed1, liquidityBorrowed + fee)/1e2, 0);
        assertEq(calcDiff(amounts1[0], amounts[0])/1e2,0);
        assertEq(calcDiff(amounts1[1], amounts[1])/1e2,0);

        vm.stopPrank();

        poolData = viewer.getLatestPoolData(address(pool));
        // 65535 => 2^16 - 1 = 2^(maxUtilRate - 35) - 1 => maxUtilRate = 51
        setPoolParams(address(pool), 0, 0, 10, 35, 20, 65535, 250, 200, 1e18);// setting base origination fee to 10, enable dynamic part from 24% to 39% utilRate

        vm.startPrank(addr1);

        poolData = viewer.getLatestPoolData(address(pool));
        usdc.transfer(address(pool), 200_000 * 1e18);
        weth.transfer(address(pool), 200 * 1e18);
        pool.increaseCollateral(tokenId, new uint256[](0));
        (uint256 liquidityBorrowed2, uint256[] memory amounts2,) = pool.borrowLiquidity(tokenId, lpTokens/8, new uint256[](0));

        assertGt(calcDiff(liquidityBorrowed2, liquidityBorrowed + fee)/1e2, 0);
        assertEq(calcDiff(amounts2[0], amounts[0])/1e2,0);
        assertEq(calcDiff(amounts2[1], amounts[1])/1e2,0);

        poolData = viewer.getLatestPoolData(address(pool));
        fee = liquidityBorrowed * 17 / 10000; // linear origination fee 17 basis points
        assertEq(calcDiff(liquidityBorrowed2, liquidityBorrowed + fee)/1e2, 0);

        vm.stopPrank();
    }

    /// @dev Loan debt increases as time passes
    function testEmaUtilRateUpdate() public {

        setPoolParams(address(pool), 10, 0, 10, 85, 100, 16384, 250, 200, 1e18);// setting base origination fee to 10, enable dynamic part from 24% to 39% utilRate

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData.BORROWED_INVARIANT, 0);
        assertEq(poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertGt(poolData.LP_INVARIANT, 0);
        assertGt(poolData.LP_TOKEN_BALANCE, 0);
        assertEq(poolData.LP_TOKEN_BORROWED, 0);
        assertEq(poolData.utilizationRate, 0);
        assertEq(poolData.accFeeIndex, 1e18);
        assertEq(poolData.currBlockNumber, 1);
        assertEq(poolData.LAST_BLOCK_NUMBER, 1);
        assertEq(poolData.emaUtilRate, 0);

        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData1 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT);
        assertGt(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertLt(poolData1.LP_INVARIANT, poolData.LP_INVARIANT);
        assertLt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
        assertGt(poolData1.LP_TOKEN_BORROWED, poolData.LP_TOKEN_BORROWED);
        assertGt(poolData1.utilizationRate, poolData.utilizationRate);
        assertEq(poolData1.accFeeIndex, poolData.accFeeIndex);
        assertEq(poolData1.currBlockNumber, 1);
        assertEq(poolData1.LAST_BLOCK_NUMBER, 1);

        assertGt(poolData1.emaUtilRate, 250000);
        assertLt(poolData1.emaUtilRate, 250200);
        vm.roll(1000000);  // After a while

        loanData = viewer.loan(address(pool), tokenId);
        assertGt(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData2 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData2.BORROWED_INVARIANT, poolData1.BORROWED_INVARIANT);
        assertGt(poolData2.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData2.LP_INVARIANT, poolData1.LP_INVARIANT);
        assertEq(poolData2.LP_TOKEN_BALANCE, poolData1.LP_TOKEN_BALANCE);
        assertEq(poolData2.LP_TOKEN_BORROWED, poolData1.LP_TOKEN_BORROWED);
        assertGt(poolData2.utilizationRate, poolData1.utilizationRate);
        assertGt(poolData2.accFeeIndex, poolData1.accFeeIndex);
        assertEq(poolData2.currBlockNumber, 1000000);
        assertEq(poolData2.LAST_BLOCK_NUMBER, 1);

        assertEq(IPoolViewer(pool.viewer()).calcDynamicOriginationFee(address(pool), 0), 10);

        uint256 usdcBal = usdc.balanceOf(addr1);
        uint256 wethBal = weth.balanceOf(addr1);
        uint256 liquidityDebtGrowth = loanData.liquidity - liquidityBorrowed;

        IGammaPool.PoolData memory poolData3 = viewer.getLatestPoolData(address(pool));
        assertGt(poolData3.emaUtilRate, 250000);
        assertLt(poolData3.emaUtilRate, 260000);

        pool.repayLiquidity(tokenId, loanData.liquidity, 1, addr1);

        loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, 0);
        assertEq(loanData.tokensHeld[0], 0);
        assertEq(loanData.tokensHeld[1], 0);
        assertGt((usdc.balanceOf(addr1) - usdcBal)/1e3, 0);
        assertGt((weth.balanceOf(addr1) - wethBal)/1e3, 0);

        poolData3 = viewer.getLatestPoolData(address(pool));
        assertGt(poolData3.emaUtilRate, 220000);
        assertLt(poolData3.emaUtilRate, 230000);

        usdc.transfer(address(pool), 10 * 130_000 * 1e18);
        weth.transfer(address(pool), 10 * 130 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/2, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/3, new uint256[](0));
        pool.borrowLiquidity(tokenId, lpTokens/10, new uint256[](0));

        poolData3 = viewer.getLatestPoolData(address(pool));
        assertGt(poolData3.utilizationRate, 93 * 1e16);
        assertLt(poolData3.utilizationRate, 94 * 1e16);

        assertEq(IPoolViewer(pool.viewer()).calcDynamicOriginationFee(address(pool), 0), 156);
    }

    /// @dev Loan debt increases as time passes
    function testEmaUtilRateBlocksUpdate() public {
        setPoolParams(address(pool), 10, 0, 10, 85, 100, 16384, 250, 200, 1e18);// setting base origination fee to 10, enable dynamic part from 24% to 39% utilRate

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);
        pool.increaseCollateral(tokenId, new uint256[](0));

        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData.BORROWED_INVARIANT, 0);
        assertEq(poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertGt(poolData.LP_INVARIANT, 0);
        assertGt(poolData.LP_TOKEN_BALANCE, 0);
        assertEq(poolData.LP_TOKEN_BORROWED, 0);
        assertEq(poolData.utilizationRate, 0);
        assertEq(poolData.accFeeIndex, 1e18);
        assertEq(poolData.currBlockNumber, 1);
        assertEq(poolData.LAST_BLOCK_NUMBER, 1);
        assertEq(poolData.emaUtilRate, 0);

        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);
        assertGt(loanData.tokensHeld[0], 0);
        assertGt(loanData.tokensHeld[1], 0);

        IGammaPool.PoolData memory poolData1 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT);
        assertGt(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertLt(poolData1.LP_INVARIANT, poolData.LP_INVARIANT);
        assertLt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
        assertGt(poolData1.LP_TOKEN_BORROWED, poolData.LP_TOKEN_BORROWED);
        assertGt(poolData1.utilizationRate, poolData.utilizationRate);
        assertEq(poolData1.accFeeIndex, poolData.accFeeIndex);
        assertEq(poolData1.currBlockNumber, 1);
        assertEq(poolData1.LAST_BLOCK_NUMBER, 1);

        assertGt(poolData1.emaUtilRate, 250000);
        assertLt(poolData1.emaUtilRate, 250200);

        assertEq(poolData1.emaUtilRate, poolData1.utilizationRate/1e12);

        vm.roll(2);
        usdc.transfer(address(pool), 130_000 * 1e18);
        weth.transfer(address(pool), 130 * 1e18);
        pool.increaseCollateral(tokenId, new uint256[](0));
        (liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens/4, new uint256[](0));

        IGammaPool.PoolData memory poolData2 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertLt(poolData2.emaUtilRate/1e4,poolData2.utilizationRate/1e16);

        vm.roll(51);
        IGammaPool.PoolData memory poolData3 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData3.utilizationRate/1e16,poolData2.utilizationRate/1e16);
        assertGt(poolData3.emaUtilRate/1e4,poolData2.emaUtilRate/1e4);
        assertLt(poolData3.emaUtilRate/1e4,poolData3.utilizationRate/1e16);

        pool.updatePool(0);

        IGammaPool.PoolData memory poolData4 = pool.getPoolData();
        assertEq(poolData3.emaUtilRate, poolData4.emaUtilRate);

        IGammaPool.PoolData memory poolData5 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData5.utilizationRate,poolData3.utilizationRate);
        assertGt(poolData5.emaUtilRate/1e4,poolData4.emaUtilRate/1e4);
        assertLt(poolData5.emaUtilRate/1e4,poolData5.utilizationRate/1e16);

        vm.roll(151);
        IGammaPool.PoolData memory poolData6 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData6.utilizationRate/1e16,poolData5.utilizationRate/1e16);
        assertGt(poolData6.emaUtilRate/1e4,poolData5.emaUtilRate/1e4);
        assertEq(poolData6.emaUtilRate,poolData5.utilizationRate/1e12);

        pool.updatePool(0);
        poolData1 = pool.getPoolData();
        assertEq(poolData1.emaUtilRate,poolData6.emaUtilRate);
        poolData2 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData2.utilizationRate,poolData6.utilizationRate);
        assertEq(poolData2.emaUtilRate,poolData1.emaUtilRate);
        assertEq(poolData1.emaUtilRate,poolData2.utilizationRate/1e12);

        vm.roll(152);
        pool.repayLiquidity(tokenId, lpTokens/4, 1, address(0));

        poolData3 = pool.getPoolData();
        poolData4 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData3.emaUtilRate, poolData4.emaUtilRate);
        assertGt(poolData4.emaUtilRate/1e4 - 20,poolData4.utilizationRate/1e16);

        vm.roll(253);

        poolData3 = pool.getPoolData();
        poolData4 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertGt(poolData3.emaUtilRate,poolData4.emaUtilRate);
        assertEq(poolData4.emaUtilRate,poolData4.utilizationRate/1e12);

        pool.updatePool(0);

        poolData3 = pool.getPoolData();
        assertEq(poolData3.emaUtilRate,poolData4.emaUtilRate);
        poolData4 = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
        assertEq(poolData4.emaUtilRate/10,poolData4.utilizationRate/1e13);
    }

    function testBorrowAndRebalanceExternally() public {
        setPoolParams(address(pool), 0, 10, 10, 100, 100, 1, 250, 200, 1e18);// setting external fees to 10 bps

        (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();

        uint256 price = uint256(reserve1) * 1e18 / reserve0;
        assertGt(price, 0);

        uint256 totalSupply = IERC20(cfmm).totalSupply();
        assertGt(totalSupply, 0);

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        address[] memory tokens = pool.tokens();
        TestExternalCallee2 callee = new TestExternalCallee2();

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 6_000 * 1e18);
        weth.transfer(address(pool), 6 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));

        (uint256 liquidityBorrowed, uint256[] memory amounts,) = pool.borrowLiquidity(tokenId, lpTokens/100, new uint256[](0));
        assertGt(liquidityBorrowed, 0);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        {
            uint256 tokenId2 = pool.createLoan(0);
            assertGt(tokenId2, 0);

            usdc.transfer(address(pool), 6_000 * 1e18);
            weth.transfer(address(pool), 6 * 1e18);

            pool.increaseCollateral(tokenId2, new uint256[](0));
            pool.borrowLiquidity(tokenId2, lpTokens/100, new uint256[](0));
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint128[] memory _amounts = new uint128[](2);

        uint256 lpAmount = lpTokens / 2;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount/2});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("WrongLPTokenBalance()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: 0, amount1: 0, lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));


        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: _amounts[0], amount1: 0, lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));


        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0] + loanData.tokensHeld[0]/2;
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: _amounts[0] - loanData.tokensHeld[0]/2, amount1: _amounts[1], lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0] * 2 + 1; // more tokens than exist in the platform
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
        cfmm: pool.cfmm(), token0: tokens[0], token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: _amounts[1], lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0] * 2;
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
            token1: tokens[1], amount0: loanData.tokensHeld[0] - 1, amount1: _amounts[1], lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("NotEnoughCollateral()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1] * 2;

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: _amounts[0], amount1: loanData.tokensHeld[1] - 1, lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("NotEnoughCollateral()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: _amounts[0]/2, amount1: _amounts[1]/2, lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));


        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: _amounts[0], amount1: _amounts[1], lpTokens: lpAmount/2});

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount/2 + 1e3);
        (uint256 loanLiquidity, uint128[] memory tokensHeld) = pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));
        assertGt(loanLiquidity, liquidityBorrowed);

        assertEq(GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]), GSMath.sqrt(uint256(tokensHeld[0])*tokensHeld[1]));

        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: _amounts[0], amount1: _amounts[1], lpTokens: lpAmount});

        // Send some lp tokens for partial liquidation
        (loanLiquidity, tokensHeld) = pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));
        assertGt(loanLiquidity, liquidityBorrowed);
        assertEq(GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]), GSMath.sqrt(uint256(tokensHeld[0])*tokensHeld[1]));


        lpAmount = lpTokens / 10;
        _amounts[0] = loanData.tokensHeld[0];
        _amounts[1] = loanData.tokensHeld[1];

        swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: _amounts[1], amount1: _amounts[0], lpTokens: lpAmount});

        vm.stopPrank();

        weth.mint(address(callee), 100_000 * 1e18);
        usdc.mint(address(callee), 100 * 1e18);

        vm.startPrank(addr1);
        // Send some lp tokens for partial liquidation
        (loanLiquidity, tokensHeld) = pool.rebalanceExternally(tokenId, _amounts, lpAmount, address(callee), abi.encode(swapData));
        assertGt(loanLiquidity, liquidityBorrowed);
        assertEq(GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]), GSMath.sqrt(uint256(tokensHeld[0])*tokensHeld[1]));

        vm.stopPrank();
    }

    function testBorrowAndRebalanceExternally2() public {
        setPoolParams(address(pool), 0, 10, 10, 100, 100, 1, 250, 200, 1e18);// setting external fees to 10 bps

        uint256 lpTokens = IERC20(cfmm).balanceOf(address(pool));
        assertGt(lpTokens, 0);

        address[] memory tokens = pool.tokens();
        TestExternalCallee2 callee = new TestExternalCallee2();

        vm.startPrank(addr1);
        uint256 tokenId = pool.createLoan(0);
        assertGt(tokenId, 0);

        usdc.transfer(address(pool), 6_000 * 1e18);
        weth.transfer(address(pool), 6 * 1e18);

        pool.increaseCollateral(tokenId, new uint256[](0));
        uint256 liquidityBorrowed;
        {
            uint256[] memory amounts;
            (liquidityBorrowed, amounts,) = pool.borrowLiquidity(tokenId, lpTokens/100, new uint256[](0));
            assertGt(liquidityBorrowed, 0);
            assertGt(amounts[0], 0);
            assertGt(amounts[1], 0);
        }

        uint256 tokenId2;
        {
            tokenId2 = pool.createLoan(0);
            assertGt(tokenId2, 0);

            usdc.transfer(address(pool), 6_000 * 1e18);
            weth.transfer(address(pool), 6 * 1e18);

            pool.increaseCollateral(tokenId2, new uint256[](0));
            pool.borrowLiquidity(tokenId2, lpTokens/100, new uint256[](0));
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool), tokenId);
        assertEq(loanData.liquidity, liquidityBorrowed);

        uint256 lpAmount = lpTokens / 2;
        lpAmount = lpTokens / 10;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool), cfmm: pool.cfmm(), token0: tokens[0],
        token1: tokens[1], amount0: loanData.tokensHeld[0], amount1: loanData.tokensHeld[1], lpTokens: lpAmount/2});

        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));

        // Send some lp tokens for partial liquidation
        GammaSwapLibrary.safeTransfer(cfmm, address(pool), lpAmount/2 + 1e3);
        (uint256 loanLiquidity, uint128[] memory tokensHeld) = pool.rebalanceExternally(tokenId, loanData.tokensHeld, lpAmount, address(callee), abi.encode(swapData));
        assertGt(loanLiquidity, liquidityBorrowed);

        assertEq(GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]), GSMath.sqrt(uint256(tokensHeld[0])*tokensHeld[1]));

        {
            IGammaPool.PoolData memory poolData1 = viewer.getLatestPoolData(address(pool));
            assertGt(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT);
        }

        pool.repayLiquidity(tokenId, loanLiquidity, 1, addr1);

        loanData = viewer.loan(address(pool), tokenId2);
        {
            IGammaPool.PoolData memory poolData1 = viewer.getLatestPoolData(address(pool));
            assertEq(loanData.liquidity, poolData1.BORROWED_INVARIANT);
        }

        vm.stopPrank();
    }
}
