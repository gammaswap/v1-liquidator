// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMLiquidationStrategyFuzz is CPMMGammaSwapSetup {

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

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: _cfmm,
            to: addr1,
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
        bool chng = changePrice(tradeAmtPerc, side);

        vm.startPrank(addr3);

        //address to = vm.addr(toNum);
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

        uint256 internalCollateral = calcCollateralPostTrade(deltas, loanData.tokensHeld, reserves);

        uint256 expLiqReward = GSMath.min(internalCollateral,loanData.liquidity) * 25 / 10000;
        uint256 expLpReward = expLiqReward * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        uint256 lpTokenReduction = loanData.liquidity * loanData.lastCFMMTotalSupply / loanData.lastCFMMInvariant;
        expLpReward = expLpReward > 1000 ? expLpReward - 1000 : 0;
        uint256 beforeCFMMBalance = IERC20(cfmm).balanceOf(addr3);

        if(loanData.liquidity > collateral * 990 / 1000) {
            pool.liquidate(_tokenId);
            uint256 lpReward = IERC20(cfmm).balanceOf(addr3) - beforeCFMMBalance;
            assertGt(IERC20(cfmm).balanceOf(addr3),beforeCFMMBalance);
            assertApproxEqAbs(lpReward,expLpReward,1e14);

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

    /// @dev See {BaseRebalanceStrategy-_calcDeltasForMaxLP}.
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

    function calcCollateralPostTrade(int256[] memory deltas, uint128[] memory tokensHeld, uint128[] memory reserves) internal virtual view returns(uint256 collateral) {
        if(deltas[0] > 0) {
            collateral = mathLib.calcCollateralPostTrade(uint256(deltas[0]), tokensHeld[0], tokensHeld[1], reserves[0], reserves[1], 997, 1000);
        } else if(deltas[1] > 0) {
            collateral = mathLib.calcCollateralPostTrade(uint256(deltas[1]), tokensHeld[1], tokensHeld[0], reserves[1], reserves[0], 997, 1000);
        } else {
            collateral = GSMath.sqrt(uint256(tokensHeld[0]) * tokensHeld[1]);
        }
    }
}
