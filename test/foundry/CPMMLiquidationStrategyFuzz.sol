// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMLiquidationStrategyFuzz is CPMMGammaSwapSetup {

    error ZeroTokensHeld();
    error ZeroReserves();
    error ZeroFees();

    uint256 _tokenId;
    address addr3;

    function setUp() public {
        super.initCPMMGammaSwap(true);

        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        addr3 = vm.addr(123);

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 25, 10);// setting ltv threshold to 1%, liqFee to 25bps

        _tokenId = openLoan(cfmm);
    }

    function openLoan(address _cfmm) internal returns(uint256 tokenId) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[1] = 15*1e18;

        vm.startPrank(addr2);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: _cfmm,
            to: addr2,
            refId: 0,
            amounts: _amounts,
            lpTokens: 35*1e17,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        (tokenId,,,) = posMgr.createLoanBorrowAndRebalance(params);
        vm.stopPrank();
    }

    function changePrice(uint8 tradeAmtPerc, bool side) internal returns(bool chng){
        vm.startPrank(addr1);
        address tokenIn = side ? address(weth) : address(usdc);
        address tokenOut = side ? address(usdc) : address(weth);
        uint256 tokenAmt = IERC20(tokenIn).balanceOf(addr1) * tradeAmtPerc / 300;

        chng = tokenAmt > 0;

        if(chng) sellTokenIn(tokenAmt, tokenIn, tokenOut, addr1);
        vm.stopPrank();
    }

    function testLiquidate18x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side);

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
            //assertEq(refund, IERC20(cfmm).balanceOf(addr3) - beforeCFMMBalance); // TODO: remove subtraction of 1000 from refund in strategy. It's already covered in excessInvariant part.
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

    //function testLiquidateWithLP18x18(uint8 tradeAmtPerc, bool side, uint8 blocks) public {
    function testLiquidateWithLP18x18() public {
        uint8 tradeAmtPerc = 44;// 244;
        bool side = true;//false;
        uint8 blocks = 251;//130;/**/
        blocks = blocks == 0 ? 1 : blocks;
        changePrice(tradeAmtPerc, side);

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
            //expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        }
        //uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenPay = GSMath.min(expLiqReward,loanData.liquidity) * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        //expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;

        uint256 beforeWethBalance = IERC20(address(weth)).balanceOf(addr1);
        uint256 beforeUsdcBalance = IERC20(address(usdc)).balanceOf(addr1);

        if(loanData.liquidity > collateral * 990 / 1000) {
            console.log("here1");
            uint256 beforeCfmmBalance = IERC20(cfmm).balanceOf(addr1);
            lpTokenPay = lpTokenPay + lpTokenPay / 100000;
            console.log(lpTokenPay);
            IERC20(cfmm).transfer(address(pool), lpTokenPay);
            (uint256 loanLiquidity, uint256[] memory refund) = pool.liquidateWithLP(_tokenId);
            assertEq(loanLiquidity, loanData.liquidity);
            //uint256 lpReward = IERC20(cfmm).balanceOf(addr1) - beforeCFMMBalance;
            //assertGt(IERC20(cfmm).balanceOf(addr1),beforeCFMMBalance);
            //assertApproxEqAbs(lpReward,expLpReward,1e14);

            assertEq(refund[0], IERC20(address(weth)).balanceOf(addr1) - beforeWethBalance);
            assertEq(refund[1], IERC20(address(usdc)).balanceOf(addr1) - beforeUsdcBalance);
            assertGt(IERC20(address(weth)).balanceOf(addr1),beforeWethBalance);
            assertGt(IERC20(address(usdc)).balanceOf(addr1),beforeUsdcBalance);


            IGammaPool.PoolData memory poolData1 = pool.getPoolData();

            loanLiquidity = GSMath.sqrt(refund[0]*refund[1]) * poolData1.lastCFMMTotalSupply / poolData1.lastCFMMInvariant;
            //assertGt(IERC20(cfmm).balanceOf(addr1) + loanLiquidity,beforeCfmmBalance); // TODO: does not match because
            // we don't actually do the swap to make it match but it's value as a CFMM LP is higher. Must check this is true

            assertEq(poolData1.BORROWED_INVARIANT, poolData.BORROWED_INVARIANT - loanData.liquidity);
            assertGt(poolData1.LP_TOKEN_BALANCE, poolData.LP_TOKEN_BALANCE);
            assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData.LP_TOKEN_BORROWED_PLUS_INTEREST - lpTokenReduction);

            IGammaPool.LoanData memory loanData1 = pool.getLoanData(_tokenId);
            assertEq(loanData1.liquidity, 0);
        } else {
            console.log("here2");
            vm.expectRevert(bytes4(keccak256("HasMargin()")));
            pool.liquidateWithLP(_tokenId);
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
