// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/test/strategies/external/TestExternalCallee2.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

enum PAIR {
    PAIR18x18,
    PAIR18x6,
    PAIR6x18,
    PAIR6x6
}

contract CPMMLiquidationStrategyFuzz is CPMMGammaSwapSetup {

    error ZeroTokensHeld();
    error ZeroReserves();
    error ZeroFees();

    uint256 _tokenId;
    address addr3;

    TestExternalCallee2 callee;

    function setUp() public {
        super.initCPMMGammaSwap(true);

        addr3 = vm.addr(123);

        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 25, 10, 1e18);// setting ltv threshold to 1%, liqFee to 25bps
        factory.setPoolParams(address(pool6x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e6);// setting ltv threshold to 1%, liqFee to 25bps
        factory.setPoolParams(address(pool18x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting ltv threshold to 1%, liqFee to 25bps
        factory.setPoolParams(address(pool6x18), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting ltv threshold to 1%, liqFee to 25bps

        callee = new TestExternalCallee2();
    }

    function openLoan(address _cfmm) internal returns(uint256 tokenId) {
        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        if (_cfmm == cfmm) {
            depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
            depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
            depositLiquidityInPoolFromCFMM(pool, _cfmm, addr2);
        } else if (_cfmm == cfmm18x6) {
            depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
            depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);
            depositLiquidityInPoolFromCFMM(pool18x6, _cfmm, addr2);
        } else if (_cfmm == cfmm6x18) {
            depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr1);
            depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr2);
            depositLiquidityInPoolFromCFMM(pool6x18, _cfmm, addr2);
        } else if (_cfmm == cfmm6x6) {
            depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
            depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);
            depositLiquidityInPoolFromCFMM(pool6x6, _cfmm, addr2);
        }

        uint256[] memory _amounts = new uint256[](2);
        if (_cfmm == cfmm) {
            _amounts[1] = 15*1e18;
        } else if (_cfmm == cfmm18x6) {
            _amounts[0] = 15*1e18;
        } else if (_cfmm == cfmm6x18 || _cfmm == cfmm6x6) {
            _amounts[0] = 15*1e6;
        }

        vm.startPrank(addr2);

        uint256 lpTokens = _cfmm == cfmm ? 35*1e17 : _cfmm == cfmm6x6 ? 35*1e5 : 35*1e11;

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: _cfmm,
            to: addr2,
            refId: 0,
            amounts: _amounts,
            lpTokens: lpTokens,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        (tokenId,,,) = posMgr.createLoanBorrowAndRebalance(params);
        vm.stopPrank();
    }

    function changePrice(uint8 tradeAmtPerc, bool side, PAIR tokenPair) internal returns(bool chng){
        vm.startPrank(addr1);
        address tokenIn;
        address tokenOut;
        if (tokenPair == PAIR.PAIR18x18) {
            tokenIn = side ? address(weth) : address(usdc);
            tokenOut = side ? address(usdc) : address(weth);
        } else if (tokenPair == PAIR.PAIR18x6) {
            tokenIn = side ? address(weth6) : address(usdc);
            tokenOut = side ? address(usdc) : address(weth6);
        } else if (tokenPair == PAIR.PAIR6x18) {
            tokenIn = side ? address(weth) : address(usdc6);
            tokenOut = side ? address(usdc6) : address(weth);
        } else if (tokenPair == PAIR.PAIR6x6) {
            tokenIn = side ? address(weth6) : address(usdc6);
            tokenOut = side ? address(usdc6) : address(weth6);
        }
        uint256 tokenAmt = IERC20(tokenIn).balanceOf(addr1) * tradeAmtPerc / 300;
        if (tokenIn == address(weth6) || tokenIn == address(usdc6)) {
            tokenAmt /= 1e12;
        }
        chng = tokenAmt > 0;

        if(chng) sellTokenIn(tokenAmt, tokenIn, tokenOut, addr1);
        vm.stopPrank();
    }

    function testLiquidate18x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x18);

        vm.startPrank(addr3);

        IGammaPool.LoanData memory loanData = pool.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint128[] memory reserves = new uint128[](2);
        reserves[0] = uint128(IERC20(address(weth)).balanceOf(cfmm));
        reserves[1] = uint128(IERC20(address(usdc)).balanceOf(cfmm));

        int256[] memory deltas;
        deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 18);

        (uint256 internalCollateral,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

        uint256 expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;
        uint256 beforeCFMMBalance = IERC20(cfmm).balanceOf(addr3);

        if(loanData.liquidity > collateral * 990 / 1000) {
            (uint256 loanLiquidity, uint256 refund) = pool.liquidate(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);
            assertEq(refund, IERC20(cfmm).balanceOf(addr3) - beforeCFMMBalance);
            refund = IERC20(cfmm).balanceOf(addr3) - beforeCFMMBalance;
            assertGt(IERC20(cfmm).balanceOf(addr3),beforeCFMMBalance);
            assertApproxEqAbs(refund,expLpReward,1e14);

            IGammaPool.PoolData memory poolData1 = pool.getPoolData();

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool.liquidate(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidate18x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm18x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x6);
        vm.startPrank(addr3);

        IGammaPool.LoanData memory loanData = pool18x6.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool18x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool18x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint128[] memory reserves = new uint128[](2);
        reserves[0] = uint128(IERC20(address(usdc)).balanceOf(cfmm18x6));
        reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm18x6));

        int256[] memory deltas;
        deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 6);

        (uint256 internalCollateral,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

        uint256 expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;
        uint256 beforeCFMMBalance = IERC20(cfmm18x6).balanceOf(addr3);

        if(loanData.liquidity > collateral * 990 / 1000) {
            (uint256 loanLiquidity, uint256 refund) = pool18x6.liquidate(_tokenId);
            assertLe(refund, IERC20(cfmm18x6).balanceOf(addr3) - beforeCFMMBalance);
            assertEq(loanLiquidity, loanData.liquidity);
            refund = IERC20(cfmm18x6).balanceOf(addr3) - beforeCFMMBalance;
            assertGt(IERC20(cfmm18x6).balanceOf(addr3), beforeCFMMBalance);
            assertApproxEqAbs(refund, expLpReward, 1e14);

            IGammaPool.PoolData memory poolData1 = pool18x6.getPoolData();

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool18x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool18x6.liquidate(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidate6x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x18);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x18);
        vm.startPrank(addr3);

        IGammaPool.LoanData memory loanData = pool6x18.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool6x18.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x18.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x18.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint128[] memory reserves = new uint128[](2);
        reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x18));
        reserves[1] = uint128(IERC20(address(weth)).balanceOf(cfmm6x18));

        int256[] memory deltas;
        deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 18);

        (uint256 internalCollateral,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

        uint256 expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;
        uint256 beforeCFMMBalance = IERC20(cfmm6x18).balanceOf(addr3);

        if(loanData.liquidity > collateral * 990 / 1000) {
            (uint256 loanLiquidity, uint256 refund) = pool6x18.liquidate(_tokenId);
            assertLe(refund, IERC20(cfmm6x18).balanceOf(addr3) - beforeCFMMBalance);
            assertEq(loanLiquidity, loanData.liquidity);
            refund = IERC20(cfmm6x18).balanceOf(addr3) - beforeCFMMBalance;
            assertGt(IERC20(cfmm6x18).balanceOf(addr3), beforeCFMMBalance);
            assertApproxEqAbs(refund, expLpReward, 1e14);

            IGammaPool.PoolData memory poolData1 = pool6x18.getPoolData();

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool6x18.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x18.liquidate(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidate6x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x6);
        vm.startPrank(addr3);

        IGammaPool.LoanData memory loanData = pool6x6.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool6x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint128[] memory reserves = new uint128[](2);
        reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x6));
        reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm6x6));

        int256[] memory deltas;
        deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 6);

        (uint256 internalCollateral,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

        uint256 expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;
        uint256 beforeCFMMBalance = IERC20(cfmm6x6).balanceOf(addr3);

        if(loanData.liquidity > collateral * 990 / 1000) {
            (uint256 loanLiquidity, uint256 refund) = pool6x6.liquidate(_tokenId);
            assertLe(refund, IERC20(cfmm6x6).balanceOf(addr3) - beforeCFMMBalance);
            assertEq(loanLiquidity, loanData.liquidity);
            refund = IERC20(cfmm6x6).balanceOf(addr3) - beforeCFMMBalance;
            assertGt(IERC20(cfmm6x6).balanceOf(addr3), beforeCFMMBalance);
            assertApproxEqAbs(refund, expLpReward, 1e14);

            IGammaPool.PoolData memory poolData1 = pool6x6.getPoolData();

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool6x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x6.liquidate(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidateWithLP18x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x18);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(weth)).balanceOf(cfmm));
            reserves[1] = uint128(IERC20(address(usdc)).balanceOf(cfmm));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 18);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        uint256 beforeWethBalance = IERC20(address(weth)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc)).balanceOf(addr1);

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm).balanceOf(addr1);
            lpTokenPay = lpTokenPay + lpTokenPay / 100000;
            IERC20(cfmm).transfer(address(pool), lpTokenPay);
            (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateWithLP(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);

            assertEq(refund[0], IERC20(address(weth)).balanceOf(addr1) - beforeWethBalance);
            assertEq(refund[1], IERC20(address(usdc)).balanceOf(addr1) - beforeUsdcBalance);
            assertGt(IERC20(address(weth)).balanceOf(addr1),beforeWethBalance);
            assertGt(IERC20(address(usdc)).balanceOf(addr1),beforeUsdcBalance);

            IGammaPool.PoolData memory poolData1 = pool.getPoolData();

            tokensHeld[0] = uint128(refund[0]);
            tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(tokensHeld, poolData1.CFMM_RESERVES, 18, 18);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool.liquidateWithLP(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidateWithLP18x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm18x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x6);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool18x6.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool18x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool18x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc)).balanceOf(cfmm18x6));
            reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm18x6));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 6);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);
            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        uint256 beforeWethBalance = IERC20(address(weth6)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc)).balanceOf(addr1);

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm18x6).balanceOf(addr1);
            lpTokenPay = lpTokenPay + lpTokenPay / 100000;
            IERC20(cfmm18x6).transfer(address(pool18x6), lpTokenPay);
            (uint256 loanLiquidity, uint256[] memory refund) = pool18x6.liquidateWithLP(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth6)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool18x6.getPoolData();

            tokensHeld[0] = uint128(refund[0]);
            tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(tokensHeld, poolData1.CFMM_RESERVES, 18, 6);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm18x6).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool18x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool18x6.liquidateWithLP(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidateWithLP6x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x18);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x18);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool6x18.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool6x18.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x18.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x18.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x18));
            reserves[1] = uint128(IERC20(address(weth)).balanceOf(cfmm6x18));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 18);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);
            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        uint256 beforeWethBalance = IERC20(address(weth)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc6)).balanceOf(addr1);

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm6x18).balanceOf(addr1);
            lpTokenPay = lpTokenPay + lpTokenPay / 100000;
            IERC20(cfmm6x18).transfer(address(pool6x18), lpTokenPay);
            (uint256 loanLiquidity, uint256[] memory refund) = pool6x18.liquidateWithLP(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc6)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool6x18.getPoolData();

            tokensHeld[0] = uint128(refund[0]);
            tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(tokensHeld, poolData1.CFMM_RESERVES, 6, 18);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm6x18).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool6x18.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x18.liquidateWithLP(_tokenId);
        }

        vm.stopPrank();
    }

    function testLiquidateWithLP6x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x6);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool6x6.loan(_tokenId);
        uint128[] memory tokensHeld = loanData.tokensHeld;

        vm.roll(uint256(blocks)*1_000_000);

        pool6x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();

        tokensHeld = loanData.tokensHeld;
        uint256 collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x6));
            reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm6x6));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 6);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);
            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        uint256 beforeWethBalance = IERC20(address(weth6)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc6)).balanceOf(addr1);

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm6x6).balanceOf(addr1);
            lpTokenPay = lpTokenPay + lpTokenPay / 100000;
            IERC20(cfmm6x6).transfer(address(pool6x6), lpTokenPay);
            (uint256 loanLiquidity, uint256[] memory refund) = pool6x6.liquidateWithLP(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc6)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth6)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool6x6.getPoolData();

            tokensHeld[0] = uint128(refund[0]);
            tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(tokensHeld, poolData1.CFMM_RESERVES, 6, 6);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm6x6).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool6x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x6.liquidateWithLP(_tokenId);
        }

        vm.stopPrank();
    }

    function testExternalLiquidation18x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x18);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool.loan(_tokenId);

        vm.roll(uint256(blocks)*1_000_000);

        pool.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(weth)).balanceOf(cfmm));
            reserves[1] = uint128(IERC20(address(usdc)).balanceOf(cfmm));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 18);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        IERC20(address(weth)).transfer(address(callee), 10);

        IERC20(address(weth)).transfer(address(pool), 10);
        IERC20(address(usdc)).transfer(address(pool), 100);

        uint256 beforeWethBalance = IERC20(address(weth)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc)).balanceOf(addr1);

        lpTokenPay = lpTokenPay + lpTokenPay / 100000;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool),
            cfmm: address(cfmm), token0: address(weth), token1: address(usdc), amount0: 110, amount1: 100, lpTokens: lpTokenPay});

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm).balanceOf(addr1);
            IERC20(cfmm).transfer(address(pool), lpTokenPay);

            loanData.tokensHeld[0] = 100;
            loanData.tokensHeld[1] = 100;

            (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateExternally(_tokenId, loanData.tokensHeld, lpTokenPay, address(callee), abi.encode(swapData));
            assertEq(loanLiquidity, loanData.liquidity);

            assertEq(refund[0], IERC20(address(weth)).balanceOf(addr1) - beforeWethBalance);
            assertEq(refund[1], IERC20(address(usdc)).balanceOf(addr1) - beforeUsdcBalance);
            assertGt(IERC20(address(weth)).balanceOf(addr1),beforeWethBalance);
            assertGt(IERC20(address(usdc)).balanceOf(addr1),beforeUsdcBalance);

            IGammaPool.PoolData memory poolData1 = pool.getPoolData();

            loanData.tokensHeld[0] = uint128(refund[0]);
            loanData.tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, poolData1.CFMM_RESERVES, 18, 18);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            assertEq(poolData1.TOKEN_BALANCE[0], IERC20(address(weth)).balanceOf(address(pool)));
            assertEq(poolData1.TOKEN_BALANCE[1], IERC20(address(usdc)).balanceOf(address(pool)));
            assertEq(poolData1.LP_TOKEN_BALANCE, IERC20(cfmm).balanceOf(address(pool)));
            IGammaPool.LoanData memory loanData1 = pool.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool.liquidateExternally(_tokenId, new uint128[](2), 0, address(callee), abi.encode(swapData));
        }

        vm.stopPrank();
    }

    function testExternalLiquidation18x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm18x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR18x6);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool18x6.loan(_tokenId);

        vm.roll(uint256(blocks)*1_000_000);

        pool18x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool18x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc)).balanceOf(cfmm18x6));
            reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm18x6));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 18, 6);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        IERC20(address(weth6)).transfer(address(callee), 10);

        IERC20(address(weth6)).transfer(address(pool18x6), 10);
        IERC20(address(usdc)).transfer(address(pool18x6), 100);

        uint256 beforeWethBalance = IERC20(address(weth6)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc)).balanceOf(addr1);

        lpTokenPay = lpTokenPay + lpTokenPay / 100000;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool18x6),
            cfmm: address(cfmm18x6), token0: address(usdc), token1: address(weth6), amount0: 100, amount1: 110, lpTokens: lpTokenPay});

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm18x6).balanceOf(addr1);
            IERC20(cfmm18x6).transfer(address(pool18x6), lpTokenPay);

            loanData.tokensHeld[0] = 100;
            loanData.tokensHeld[1] = 100;

            (uint256 loanLiquidity, uint256[] memory refund) = pool18x6.liquidateExternally(_tokenId, loanData.tokensHeld, lpTokenPay, address(callee), abi.encode(swapData));
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth6)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool18x6.getPoolData();

            loanData.tokensHeld[0] = uint128(refund[0]);
            loanData.tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, poolData1.CFMM_RESERVES, 18, 6);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm18x6).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            assertEq(poolData1.TOKEN_BALANCE[0], IERC20(address(usdc)).balanceOf(address(pool18x6)));
            assertEq(poolData1.TOKEN_BALANCE[1], IERC20(address(weth6)).balanceOf(address(pool18x6)));
            assertEq(poolData1.LP_TOKEN_BALANCE, IERC20(cfmm18x6).balanceOf(address(pool18x6)));
            IGammaPool.LoanData memory loanData1 = pool18x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool18x6.liquidateExternally(_tokenId, new uint128[](2), 0, address(callee), abi.encode(swapData));
        }

        vm.stopPrank();
    }

    function testExternalLiquidation6x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x18);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x18);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool6x18.loan(_tokenId);

        vm.roll(uint256(blocks)*1_000_000);

        pool6x18.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x18.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x18.getPoolData();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x18));
            reserves[1] = uint128(IERC20(address(weth)).balanceOf(cfmm6x18));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 18);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        IERC20(address(weth)).transfer(address(callee), 10);

        IERC20(address(usdc6)).transfer(address(pool6x18), 100);
        IERC20(address(weth)).transfer(address(pool6x18), 10);

        uint256 beforeUsdcBalance = IERC20(address(usdc6)).balanceOf(addr1);
        uint256 beforeWethBalance = IERC20(address(weth)).balanceOf(addr1);

        lpTokenPay = lpTokenPay + lpTokenPay / 100000;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool6x18),
            cfmm: address(cfmm6x18), token0: address(usdc6), token1: address(weth), amount0: 100, amount1: 110, lpTokens: lpTokenPay});

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm6x18).balanceOf(addr1);
            IERC20(cfmm6x18).transfer(address(pool6x18), lpTokenPay);

            loanData.tokensHeld[0] = 100;
            loanData.tokensHeld[1] = 100;

            (uint256 loanLiquidity, uint256[] memory refund) = pool6x18.liquidateExternally(_tokenId, loanData.tokensHeld, lpTokenPay, address(callee), abi.encode(swapData));
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc6)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool6x18.getPoolData();

            loanData.tokensHeld[0] = uint128(refund[0]);
            loanData.tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, poolData1.CFMM_RESERVES, 6, 18);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm6x18).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            assertEq(poolData1.TOKEN_BALANCE[0], IERC20(address(usdc6)).balanceOf(address(pool6x18)));
            assertEq(poolData1.TOKEN_BALANCE[1], IERC20(address(weth)).balanceOf(address(pool6x18)));
            assertEq(poolData1.LP_TOKEN_BALANCE, IERC20(cfmm6x18).balanceOf(address(pool6x18)));
            IGammaPool.LoanData memory loanData1 = pool6x18.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x18.liquidateExternally(_tokenId, new uint128[](2), 0, address(callee), abi.encode(swapData));
        }

        vm.stopPrank();
    }

    function testExternalLiquidation6x6(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        _tokenId = openLoan(cfmm6x6);

        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side, PAIR.PAIR6x6);

        vm.startPrank(addr1);

        IGammaPool.LoanData memory loanData = pool6x6.loan(_tokenId);

        vm.roll(uint256(blocks)*1_000_000);

        pool6x6.updatePool(_tokenId); // update loan and pool information to latest values

        loanData = pool6x6.getLoanData(_tokenId);

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();

        uint256 collateral = GSMath.sqrt(uint256(loanData.tokensHeld[0]) * loanData.tokensHeld[1]);

        uint256 expLiqReward;
        {
            uint128[] memory reserves = new uint128[](2);
            reserves[0] = uint128(IERC20(address(usdc6)).balanceOf(cfmm6x6));
            reserves[1] = uint128(IERC20(address(weth6)).balanceOf(cfmm6x6));

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, reserves, 6, 6);

            uint256[] memory _tokensHeld = new uint256[](2);
            uint256 internalCollateral;
            (internalCollateral, _tokensHeld[0], _tokensHeld[1]) = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

            expLiqReward = internalCollateral;
        }
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;

        IERC20(address(weth6)).transfer(address(callee), 10);

        IERC20(address(weth6)).transfer(address(pool6x6), 10);
        IERC20(address(usdc6)).transfer(address(pool6x6), 100);

        uint256 beforeWethBalance = IERC20(address(weth6)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc6)).balanceOf(addr1);

        lpTokenPay = lpTokenPay + lpTokenPay / 100000;

        TestExternalCallee2.SwapData memory swapData = TestExternalCallee2.SwapData({ strategy: address(pool6x6),
            cfmm: address(cfmm6x6), token0: address(usdc6), token1: address(weth6), amount0: 100, amount1: 110, lpTokens: lpTokenPay});

        if(loanData.liquidity > collateral * 990 / 1000) {
            uint256 beforeCfmmBalance = IERC20(cfmm6x6).balanceOf(addr1);
            IERC20(cfmm6x6).transfer(address(pool6x6), lpTokenPay);

            loanData.tokensHeld[0] = 100;
            loanData.tokensHeld[1] = 100;

            (uint256 loanLiquidity, uint256[] memory refund) = pool6x6.liquidateExternally(_tokenId, loanData.tokensHeld, lpTokenPay, address(callee), abi.encode(swapData));
            assertEq(loanLiquidity, loanData.liquidity);

            assertGt(refund[0], 0);
            assertGt(refund[1], 0);
            assertEq(refund[0], IERC20(address(usdc6)).balanceOf(addr1) - beforeUsdcBalance);
            assertEq(refund[1], IERC20(address(weth6)).balanceOf(addr1) - beforeWethBalance);

            IGammaPool.PoolData memory poolData1 = pool6x6.getPoolData();

            loanData.tokensHeld[0] = uint128(refund[0]);
            loanData.tokensHeld[1] = uint128(refund[1]);

            int256[] memory deltas;
            deltas = calcDeltasForMaxLP(loanData.tokensHeld, poolData1.CFMM_RESERVES, 6, 6);
            (lpTokenPay,,) = calcCollateralPostTrade(deltas, loanData.tokensHeld, poolData1.CFMM_RESERVES);
            loanLiquidity = lpTokenPay * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            assertGt(IERC20(cfmm6x6).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance);

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            assertEq(poolData1.TOKEN_BALANCE[0], IERC20(address(usdc6)).balanceOf(address(pool6x6)));
            assertEq(poolData1.TOKEN_BALANCE[1], IERC20(address(weth6)).balanceOf(address(pool6x6)));
            assertEq(poolData1.LP_TOKEN_BALANCE, IERC20(cfmm6x6).balanceOf(address(pool6x6)));
            IGammaPool.LoanData memory loanData1 = pool6x6.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool6x6.liquidateExternally(_tokenId, new uint128[](2), 0, address(callee), abi.encode(swapData));
        }

        vm.stopPrank();
    }

    function calcDeltasForMaxLP(uint128[] memory tokensHeld, uint128[] memory reserves, uint8 decimals0, uint8 decimals1) internal virtual view returns(int256[] memory deltas) {
        // we only buy, therefore when desiredRatio > loanRatio, invert reserves, collaterals, and desiredRatio
        deltas = new int256[](2);

        uint256 leftVal = uint256(reserves[0]) * uint256(tokensHeld[1]);
        uint256 rightVal = uint256(reserves[1]) * uint256(tokensHeld[0]);

        if(leftVal > rightVal) {
            deltas = mathLib.calcDeltasForMaxLP(tokensHeld[0], tokensHeld[1], reserves[0], reserves[1], 997, 1000, decimals0);
            (deltas[0], deltas[1]) = (deltas[1], 0); // swap result, 1st root (index 0) is the only feasible trade
        } else if(leftVal < rightVal) {
            deltas = mathLib.calcDeltasForMaxLP(tokensHeld[1], tokensHeld[0], reserves[1], reserves[0], 997, 1000, decimals1);
            (deltas[0], deltas[1]) = (0, deltas[1]); // swap result, 1st root (index 0) is the only feasible trade
        }
    }

    function calcCollateralPostTrade(int256[] memory deltas, uint128[] memory tokensHeld, uint128[] memory reserves)
        internal virtual view returns(uint256 collateral, uint256 tokensHeld0, uint256 tokensHeld1) {
        if(deltas[0] > 0) {
            (collateral, tokensHeld0, tokensHeld1) = _calcCollateralPostTrade(uint256(deltas[0]), tokensHeld[0], tokensHeld[1], reserves[0], reserves[1], 997, 1000);
        } else if(deltas[1] > 0) {
            (collateral, tokensHeld1, tokensHeld0) = _calcCollateralPostTrade(uint256(deltas[1]), tokensHeld[1], tokensHeld[0], reserves[1], reserves[0], 997, 1000);
        } else {
            collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);
            (tokensHeld0, tokensHeld1) = (tokensHeld[0], tokensHeld[1]);
        }
    }

    function _calcCollateralPostTrade(uint256 delta, uint256 tokensHeld0, uint256 tokensHeld1, uint256 reserve0, uint256 reserve1,
        uint256 fee1, uint256 fee2) internal virtual view returns(uint256, uint256, uint256) {
        if(tokensHeld0 == 0 || tokensHeld1 == 0) revert ZeroTokensHeld();
        if(reserve0 == 0 || reserve1 == 0) revert ZeroReserves();
        if(fee1 == 0 || fee2 == 0) revert ZeroFees();

        uint256 soldToken = reserve1 * delta * fee2 / ((reserve0 - delta) * fee1);
        require(soldToken <= tokensHeld1, "SOLD_TOKEN_GT_TOKENS_HELD1");

        tokensHeld1 -= soldToken;
        tokensHeld0 += delta;
        uint256 collateral = GSMath.sqrt(tokensHeld0 * tokensHeld1);
        return(collateral, tokensHeld0, tokensHeld1);
    }
}
