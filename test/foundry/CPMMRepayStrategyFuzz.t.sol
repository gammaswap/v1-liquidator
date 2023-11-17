// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMRepayStrategyFuzz is CPMMGammaSwapSetup {

    uint256 _tokenId;

    function setUp() public {
        super.initCPMMGammaSwap(true);

        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        _tokenId = openLoan(cfmm);
    }

    function openLoan(address _cfmm) internal returns(uint256 tokenId) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[1] = 100*1e18;

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

    function testRepayLiquidity18x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, bool collateralId, uint8 toNum) public {
        if(toNum == 0) toNum = 1;

        bool chng = changePrice(tradeAmtPerc, side);

        vm.startPrank(addr1);

        address to = vm.addr(toNum); //TODO:, check this zero
        IGammaPool.LoanData memory loanData = pool.loan(_tokenId);
        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm,
            tokenId: _tokenId,
            liquidity: payLiquidity,
            isRatio: false,
            ratio: new uint256[](0),
            collateralId: collateralId ? 2 : 1, // TODO, check this zero
            to: to,
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(to);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(to);

            IGammaPool.PoolData memory prevPoolData = pool.getPoolData();

            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            IGammaPool.PoolData memory poolData = pool.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e6);
            assertApproxEqAbs(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e6);

            if(chng) {
                assertGt(IERC20(address(weth)).balanceOf(to), wethBalancePrev);
                assertGt(IERC20(address(usdc)).balanceOf(to), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatio18x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, uint72 ratio0, uint72 ratio1) public {
        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 25, 10);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side);

        if(ratio0 < 1e4) ratio0 = 1e4;
        if(ratio1 < 1e4) ratio1 = 1e4;

        if(ratio1 > ratio0) {
            if(ratio1 / ratio0 > 2) {
                ratio1 = 2 * ratio0;
            }
        } else if(ratio0 > ratio1) {
            if(ratio0 / ratio1 > 2) {
                ratio0 = 2 * ratio1;
            }
        }

        IGammaPool.LoanData memory loanData = pool.loan(_tokenId);

        uint256 strikePx;
        uint256[] memory ratio;
        if(ratio1 == ratio0) {
            ratio = new uint256[](0);
            strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        } else {
            ratio = new uint256[](2);
            ratio[0] = uint256(IERC20(address(weth)).balanceOf(cfmm)) * uint256(ratio0);
            ratio[1] = uint256(IERC20(address(usdc)).balanceOf(cfmm)) * uint256(ratio1);
            strikePx = uint256(ratio[1]) * 1e18 / ratio[0];
        }

        vm.startPrank(addr1);

        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm,
            tokenId: _tokenId,
            liquidity: payLiquidity,
            isRatio: true,
            ratio: ratio,
            collateralId: 0,
            to: address(0),
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(addr1);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(addr1);

            IGammaPool.PoolData memory prevPoolData = pool.getPoolData();
            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            loanData = pool.loan(_tokenId);

            IGammaPool.PoolData memory poolData = pool.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e6);
            assertApproxEqAbs(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e6);

            liquidityPaid = strikePx * 100 / 10000;
            assertApproxEqAbs(strikePx, uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], liquidityPaid);
            if(chng) {
                assertEq(IERC20(address(weth)).balanceOf(addr1), wethBalancePrev);
                assertEq(IERC20(address(usdc)).balanceOf(addr1), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }
}
