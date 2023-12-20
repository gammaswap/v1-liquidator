// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMRepayStrategyFuzz is CPMMGammaSwapSetup {

    uint256 _tokenId;
    uint256 _tokenId18x6;
    uint256 _tokenId6x18;
    uint256 _tokenId6x6;

    function setUp() public {
        super.initCPMMGammaSwap(true);

        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        _tokenId = openLoan(cfmm, 18, 18);

        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        _tokenId18x6 = openLoan(cfmm18x6, 18, 6);

        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool6x18, cfmm6x18, addr2);

        _tokenId6x18 = openLoan(cfmm6x18, 6, 18);

        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        _tokenId6x6 = openLoan(cfmm6x6, 6, 6);
    }

    function openLoan(address _cfmm, uint8 _decimals0, uint8 _decimals1) internal returns(uint256 tokenId) {
        uint256[] memory _amounts = new uint256[](2);
        _amounts[1] = 100*(10**_decimals1);

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: _cfmm,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: 35*(10**((_decimals0 + _decimals1) / 2)) / 10,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        (tokenId,,,) = posMgr.createLoanBorrowAndRebalance(params);
        vm.stopPrank();
    }

    function changePrice(uint8 tradeAmtPerc, bool side, address _pool) internal returns(bool chng){
        vm.startPrank(addr1);
        address[] memory tokens = IGammaPool(_pool).tokens();
        address tokenIn = side ? tokens[0] : tokens[1];
        address tokenOut = side ? tokens[1] : tokens[0];
        uint256 tokenAmt = IERC20(tokenIn).balanceOf(addr1) * tradeAmtPerc / 300;

        chng = tokenAmt > 0;

        if(chng) sellTokenIn(tokenAmt, tokenIn, tokenOut, addr1);
        vm.stopPrank();
    }

    function changePrice2(uint8 tradeAmtPerc, bool side, address _pool) internal returns(bool chng){
        vm.startPrank(addr1);
        address[] memory tokens = IGammaPool(_pool).tokens();
        address tokenIn = side ? tokens[0] : tokens[1];
        address tokenOut = side ? tokens[1] : tokens[0];
        uint256 tokenAmt = IERC20(tokenIn).balanceOf(IGammaPool(_pool).cfmm()) * tradeAmtPerc / 600;

        chng = tokenAmt > 0;

        if(chng) sellTokenIn(tokenAmt, tokenIn, tokenOut, addr1);
        vm.stopPrank();
    }

    function testRepayLiquidity18x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, bool collateralId, uint8 toNum) public {
        if(toNum == 0) toNum = 1;

        bool chng = changePrice(tradeAmtPerc, side, address(pool));

        vm.startPrank(addr1);

        address to = vm.addr(toNum);

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool.viewer()).loan(address(pool), _tokenId);
        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm,
            tokenId: _tokenId,
            liquidity: payLiquidity,
            isRatio: false,
            ratio: new uint256[](0),
            collateralId: collateralId ? 2 : 1,
            to: to,
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1000) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(to);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(to);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));

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

    function testRepayLiquidity18x6(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, bool collateralId, uint8 toNum) public {
        if(toNum == 0) toNum = 1;

        bool chng = changePrice(tradeAmtPerc, side, address(pool18x6));

        vm.startPrank(addr1);

        address to = vm.addr(toNum);

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool18x6.viewer()).loan(address(pool18x6), _tokenId18x6);
        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            tokenId: _tokenId18x6,
            liquidity: payLiquidity,
            isRatio: false,
            ratio: new uint256[](0),
            collateralId: collateralId ? 2 : 1,
            to: to,
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth6)).balanceOf(to);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(to);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool18x6.viewer()).getLatestPoolData(address(pool18x6));

            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            IGammaPool.PoolData memory poolData = pool18x6.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);
            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e8);
            assertLe(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]));

            if(chng) {
                if(collateralId) { // collatearlId is token that will be exhausted while paying liquidity
                    assertGt(IERC20(address(usdc)).balanceOf(to), usdcBalancePrev);
                    assertGe(IERC20(address(weth6)).balanceOf(to), wethBalancePrev); // exhaust token1
                } else {
                    assertGe(IERC20(address(usdc)).balanceOf(to), usdcBalancePrev); // exhaust token0
                    assertGt(IERC20(address(weth6)).balanceOf(to), wethBalancePrev);
                }
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquidity6x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, bool collateralId, uint8 toNum) public {
        if(toNum == 0) toNum = 1;

        bool chng = changePrice(tradeAmtPerc, side, address(pool6x18));

        vm.startPrank(addr1);

        address to = vm.addr(toNum);

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x18.viewer()).loan(address(pool6x18), _tokenId6x18);
        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm6x18,
            tokenId: _tokenId6x18,
            liquidity: payLiquidity,
            isRatio: false,
            ratio: new uint256[](0),
            collateralId: collateralId ? 2 : 1,
            to: to,
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(to);
            uint256 usdcBalancePrev = IERC20(address(usdc6)).balanceOf(to);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool6x18.viewer()).getLatestPoolData(address(pool6x18));

            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            IGammaPool.PoolData memory poolData = pool6x18.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);
            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e8);
            assertLe(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]));

            if(chng) {
                if(collateralId) { // collatearlId is token that will be exhausted while paying liquidity
                    assertGt(IERC20(address(usdc6)).balanceOf(to), usdcBalancePrev);
                    assertGe(IERC20(address(weth)).balanceOf(to), wethBalancePrev); // exhaust token1
                } else {
                    assertGe(IERC20(address(usdc6)).balanceOf(to), usdcBalancePrev); // exhaust token0
                    assertGt(IERC20(address(weth)).balanceOf(to), wethBalancePrev);
                }
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquidity6x6(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, bool collateralId, uint8 toNum) public {
        if(toNum == 0) toNum = 1;

        bool chng = changePrice(tradeAmtPerc, side, address(pool6x6));

        vm.startPrank(addr1);

        address to = vm.addr(toNum);

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x6.viewer()).loan(address(pool6x6), _tokenId6x6);
        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            tokenId: _tokenId6x6,
            liquidity: payLiquidity,
            isRatio: false,
            ratio: new uint256[](0),
            collateralId: collateralId ? 2 : 1,
            to: to,
            deadline: type(uint256).max,
            minRepaid: new uint256[](2)
        });

        if(payLiquidity == 0) {
            vm.expectRevert(bytes4(keccak256("ZeroRepayLiquidity()")));
            posMgr.repayLiquidity(params);
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e6) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth6)).balanceOf(to);
            uint256 usdcBalancePrev = IERC20(address(usdc6)).balanceOf(to);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool6x6.viewer()).getLatestPoolData(address(pool6x6));

            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            IGammaPool.PoolData memory poolData = pool6x6.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);
            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e8);
            assertLe(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]));

            if(chng) {
                if(collateralId) { // collatearlId is token that will be exhausted while paying liquidity
                    assertGt(IERC20(address(usdc6)).balanceOf(to), usdcBalancePrev);
                    assertGe(IERC20(address(weth6)).balanceOf(to), wethBalancePrev); // exhaust token1
                } else {
                    assertGe(IERC20(address(usdc6)).balanceOf(to), usdcBalancePrev); // exhaust token0
                    assertGt(IERC20(address(weth6)).balanceOf(to), wethBalancePrev);
                }
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatio18x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, uint72 ratio0, uint72 ratio1) public {
        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 25, 10, 1e18);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side, address(pool));

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

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool.viewer()).loan(address(pool), _tokenId);

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
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e18) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(addr1);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(addr1);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));
            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            loanData = pool.loan(_tokenId);

            IGammaPool.PoolData memory poolData = pool.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqAbs(liquidityPaid, payLiquidity, 1e6);
            assertApproxEqAbs(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e6);

            assertApproxEqRel(strikePx, uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], 1e16); // max 1% error
            if(chng) {
                assertEq(IERC20(address(weth)).balanceOf(addr1), wethBalancePrev);
                assertEq(IERC20(address(usdc)).balanceOf(addr1), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatio18x6(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, uint72 ratio0, uint72 ratio1) public {
        factory.setPoolParams(address(pool18x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting origination fees to zero

        bool chng = changePrice2(tradeAmtPerc, side, address(pool18x6));

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

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool18x6.viewer()).loan(address(pool18x6), _tokenId18x6);

        uint256 strikePx;
        uint256[] memory ratio;
        if(ratio1 == ratio0) {
            ratio = new uint256[](0);
            strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        } else {
            ratio = new uint256[](2);
            ratio[1] = uint256(IERC20(address(weth6)).balanceOf(cfmm18x6)) * uint256(ratio1);
            ratio[0] = uint256(IERC20(address(usdc)).balanceOf(cfmm18x6)) * uint256(ratio0);
            strikePx = uint256(ratio[1]) * 1e18 / ratio[0];
        }

        vm.startPrank(addr1);

        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            tokenId: _tokenId18x6,
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
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth6)).balanceOf(addr1);
            uint256 usdcBalancePrev = IERC20(address(usdc)).balanceOf(addr1);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool18x6.viewer()).getLatestPoolData(address(pool18x6));
            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            loanData = pool18x6.loan(_tokenId18x6);

            IGammaPool.PoolData memory poolData = pool18x6.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqRel(liquidityPaid, payLiquidity, 1e16);
            assertApproxEqRel(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e16);

            assertApproxEqRel(strikePx, uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], 125*1e14);
            if(chng) {
                assertEq(IERC20(address(weth6)).balanceOf(addr1), wethBalancePrev);
                assertEq(IERC20(address(usdc)).balanceOf(addr1), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatio6x18(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, uint72 ratio0, uint72 ratio1) public {
        factory.setPoolParams(address(pool6x18), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting origination fees to zero

        bool chng = changePrice2(tradeAmtPerc, side, address(pool6x18));

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

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x18.viewer()).loan(address(pool6x18), _tokenId6x18);

        uint256 strikePx;
        uint256[] memory ratio;
        if(ratio1 == ratio0) {
            ratio = new uint256[](0);
            strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        } else {
            ratio = new uint256[](2);
            ratio[1] = uint256(IERC20(address(weth)).balanceOf(cfmm6x18)) * uint256(ratio1);
            ratio[0] = uint256(IERC20(address(usdc6)).balanceOf(cfmm6x18)) * uint256(ratio0);
            strikePx = uint256(ratio[1]) * 1e18 / ratio[0];
        }

        vm.startPrank(addr1);

        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm6x18,
            tokenId: _tokenId6x18,
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
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth)).balanceOf(addr1);
            uint256 usdcBalancePrev = IERC20(address(usdc6)).balanceOf(addr1);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool6x18.viewer()).getLatestPoolData(address(pool6x18));
            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            loanData = pool6x18.loan(_tokenId6x18);

            IGammaPool.PoolData memory poolData = pool6x18.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqRel(liquidityPaid, payLiquidity, 1e16);
            assertApproxEqRel(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e16);

            assertApproxEqRel(strikePx, uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], 1e16);
            if(chng) {
                assertEq(IERC20(address(weth)).balanceOf(addr1), wethBalancePrev);
                assertEq(IERC20(address(usdc6)).balanceOf(addr1), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquiditySetRatio6x6(uint8 tradeAmtPerc, bool side, uint8 payLiquidityPerc, uint72 ratio0, uint72 ratio1) public {
        factory.setPoolParams(address(pool6x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e6);// setting origination fees to zero

        bool chng = changePrice2(tradeAmtPerc, side, address(pool6x6));

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

        vm.roll(100);

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x6.viewer()).loan(address(pool6x6), _tokenId6x6);

        uint256 strikePx;
        uint256[] memory ratio;
        if(ratio1 == ratio0) {
            ratio = new uint256[](0);
            strikePx = uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0];
        } else {
            ratio = new uint256[](2);
            ratio[1] = uint256(IERC20(address(weth6)).balanceOf(cfmm6x6)) * uint256(ratio1);
            ratio[0] = uint256(IERC20(address(usdc6)).balanceOf(cfmm6x6)) * uint256(ratio0);
            strikePx = uint256(ratio[1]) * 1e18 / ratio[0];
        }

        vm.startPrank(addr1);

        uint256 payLiquidity = GSMath.min(loanData.liquidity * payLiquidityPerc / 250, loanData.liquidity);

        IPositionManager.RepayLiquidityParams memory params = IPositionManager.RepayLiquidityParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            tokenId: _tokenId6x6,
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
        } else if(loanData.liquidity > payLiquidity && loanData.liquidity - payLiquidity <= 1e6) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidity(params);
        } else {
            uint256 wethBalancePrev = IERC20(address(weth6)).balanceOf(addr1);
            uint256 usdcBalancePrev = IERC20(address(usdc6)).balanceOf(addr1);

            IGammaPool.PoolData memory prevPoolData = IPoolViewer(pool6x6.viewer()).getLatestPoolData(address(pool6x6));
            (uint256 liquidityPaid, uint256[] memory amounts) = posMgr.repayLiquidity(params);

            loanData = pool6x6.loan(_tokenId6x6);

            IGammaPool.PoolData memory poolData = pool6x6.getPoolData();
            assertEq(poolData.BORROWED_INVARIANT, prevPoolData.BORROWED_INVARIANT - liquidityPaid);
            assertGt(poolData.LP_TOKEN_BALANCE, prevPoolData.LP_TOKEN_BALANCE);

            assertApproxEqRel(liquidityPaid, payLiquidity, 1e16);
            assertApproxEqRel(liquidityPaid, GSMath.sqrt(amounts[0] * amounts[1]), 1e16);

            assertApproxEqRel(strikePx, uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], 1e16);
            if(chng) {
                assertEq(IERC20(address(weth6)).balanceOf(addr1), wethBalancePrev);
                assertEq(IERC20(address(usdc6)).balanceOf(addr1), usdcBalancePrev);
            }
        }

        vm.stopPrank();
    }

    function testRepayLiquidityWithLP18x18(uint8 tradeAmtPerc, bool side, uint8 lpTokenPerc, uint8 collateralId, uint8 toNum) public {
        collateralId = uint8(bound(collateralId, 0, 2));

        factory.setPoolParams(address(pool), 0, 0, 10, 100, 100, 1, 25, 10, 1e18);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side, address(pool));

        vm.roll(100);

        IGammaPool.PoolData memory poolData = IPoolViewer(pool.viewer()).getLatestPoolData(address(pool));

        IGammaPool.LoanData memory loanData = IPoolViewer(pool.viewer()).loan(address(pool), _tokenId);

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth)).balanceOf(cfmm)*IERC20(address(usdc)).balanceOf(cfmm)));
        poolData.lastCFMMTotalSupply = IERC20(cfmm).totalSupply();

        uint256 lpTokenDebt = loanData.liquidity * poolData.lastCFMMTotalSupply / poolData.lastCFMMInvariant;

        uint256 lpTokenPay = GSMath.min(uint256(lpTokenPerc) * lpTokenDebt / 250, lpTokenDebt);

        lpTokenPay = lpTokenPay == 0 ? 0 : lpTokenPay + 1000;

        uint256 expLiquidityPay = GSMath.min(lpTokenPay * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply, loanData.liquidity);

        IPositionManager.RepayLiquidityWithLPParams memory params = IPositionManager.RepayLiquidityWithLPParams({
            protocolId: 1,
            cfmm: cfmm,
            tokenId: _tokenId,
            lpTokens: lpTokenPay,
            collateralId: collateralId,
            to: toNum == 0 ? address(0) : vm.addr(toNum),
            deadline: type(uint256).max,
            minCollateral: new uint128[](2)
        });

        vm.startPrank(addr1);

        if(lpTokenPay == 0) {
            vm.expectRevert(bytes4(keccak256("NotEnoughLPDeposit()")));
            posMgr.repayLiquidityWithLP(params);
        } else if(loanData.liquidity > expLiquidityPay && loanData.liquidity - expLiquidityPay <= 1e18) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidityWithLP(params);
        } else {

            lpTokenDebt = loanData.liquidity;

            poolData.TOKEN_BALANCE[0] = uint128(IERC20(address(weth)).balanceOf(params.to)); // prev weth balance at user
            poolData.TOKEN_BALANCE[1] = uint128(IERC20(address(usdc)).balanceOf(params.to)); // prev usdc balance at user

            (uint256 liquidityPaid, uint128[] memory tokensHeld) = posMgr.repayLiquidityWithLP(params);
            assertApproxEqAbs(liquidityPaid, expLiquidityPay, 1e3);

            if(params.to != address(0)) {
                uint128[] memory tokensHeldPart = new uint128[](2);
                tokensHeldPart[0] = uint128(GSMath.min(loanData.tokensHeld[0] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[0])));
                tokensHeldPart[1] = uint128(GSMath.min(loanData.tokensHeld[1] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[1])));
                assertApproxEqAbs(tokensHeld[0], loanData.tokensHeld[0] - tokensHeldPart[0], 1e1);
                assertApproxEqAbs(tokensHeld[1], loanData.tokensHeld[1] - tokensHeldPart[1], 1e1);

                if(collateralId > 0) {
                    if(collateralId == 1) {
                        assertGe(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                        assertGt(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    } else {
                        assertGt(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                        assertGe(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    }
                } else {
                    assertGt(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    assertGt(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    assertApproxEqAbs(tokensHeldPart[0], IERC20(address(weth)).balanceOf(params.to) - poolData.TOKEN_BALANCE[0],1e6);
                    assertApproxEqAbs(tokensHeldPart[1], IERC20(address(usdc)).balanceOf(params.to) - poolData.TOKEN_BALANCE[1],1e6);
                }
            }

            loanData = pool.loan(_tokenId);

            assertEq(loanData.liquidity, lpTokenDebt - liquidityPaid);
        }

        vm.stopPrank();
    }

    function testRepayLiquidityWithLP18x6(uint8 tradeAmtPerc, bool side, uint8 lpTokenPerc, uint8 collateralId, uint8 toNum) public {
        collateralId = uint8(bound(collateralId, 0, 2));

        factory.setPoolParams(address(pool18x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side, address(pool18x6));

        vm.roll(100);

        IGammaPool.PoolData memory poolData = IPoolViewer(pool18x6.viewer()).getLatestPoolData(address(pool18x6));

        IGammaPool.LoanData memory loanData = IPoolViewer(pool18x6.viewer()).loan(address(pool18x6), _tokenId18x6);

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth6)).balanceOf(cfmm18x6)*IERC20(address(usdc)).balanceOf(cfmm18x6)));
        poolData.lastCFMMTotalSupply = IERC20(cfmm18x6).totalSupply();

        uint256 lpTokenDebt = loanData.liquidity * poolData.lastCFMMTotalSupply / poolData.lastCFMMInvariant;

        uint256 lpTokenPay = GSMath.min(uint256(lpTokenPerc) * lpTokenDebt / 250, lpTokenDebt);

        lpTokenPay = lpTokenPay == 0 ? 0 : lpTokenPay + 1000;

        uint256 expLiquidityPay = GSMath.min(lpTokenPay * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply, loanData.liquidity);

        IPositionManager.RepayLiquidityWithLPParams memory params = IPositionManager.RepayLiquidityWithLPParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            tokenId: _tokenId18x6,
            lpTokens: lpTokenPay,
            collateralId: collateralId,
            to: toNum == 0 ? address(0) : vm.addr(toNum),
            deadline: type(uint256).max,
            minCollateral: new uint128[](2)
        });

        vm.startPrank(addr1);

        if(lpTokenPay == 0) {
            vm.expectRevert(bytes4(keccak256("NotEnoughLPDeposit()")));
            posMgr.repayLiquidityWithLP(params);
        } else if(loanData.liquidity > expLiquidityPay && loanData.liquidity - expLiquidityPay <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidityWithLP(params);
        } else {

            lpTokenDebt = loanData.liquidity;

            poolData.TOKEN_BALANCE[1] = uint128(IERC20(address(weth6)).balanceOf(params.to)); // prev weth6 balance at user
            poolData.TOKEN_BALANCE[0] = uint128(IERC20(address(usdc)).balanceOf(params.to)); // prev usdc balance at user

            (uint256 liquidityPaid, uint128[] memory tokensHeld) = posMgr.repayLiquidityWithLP(params);
            assertApproxEqAbs(liquidityPaid, expLiquidityPay, 1e3);

            if(params.to != address(0)) {
                uint128[] memory tokensHeldPart = new uint128[](2);
                tokensHeldPart[0] = uint128(GSMath.min(loanData.tokensHeld[0] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[0])));
                tokensHeldPart[1] = uint128(GSMath.min(loanData.tokensHeld[1] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[1])));
                assertApproxEqAbs(tokensHeld[0], loanData.tokensHeld[0] - tokensHeldPart[0], 1e1);
                assertApproxEqAbs(tokensHeld[1], loanData.tokensHeld[1] - tokensHeldPart[1], 1e1);

                if(collateralId > 0) {
                    if(collateralId == 1) {
                        assertGt(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGe(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    } else {
                        assertGe(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGt(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    }
                } else {
                    assertGt(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    assertGt(IERC20(address(usdc)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    assertApproxEqAbs(tokensHeldPart[1], IERC20(address(weth6)).balanceOf(params.to) - poolData.TOKEN_BALANCE[1],1e6);
                    assertApproxEqAbs(tokensHeldPart[0], IERC20(address(usdc)).balanceOf(params.to) - poolData.TOKEN_BALANCE[0],1e6);
                }
            }

            loanData = pool18x6.loan(_tokenId18x6);

            assertEq(loanData.liquidity, lpTokenDebt - liquidityPaid);
        }

        vm.stopPrank();
    }

    function testRepayLiquidityWithLP6x18(uint8 tradeAmtPerc, bool side, uint8 lpTokenPerc, uint8 collateralId, uint8 toNum) public {
        collateralId = uint8(bound(collateralId, 0, 2));

        factory.setPoolParams(address(pool6x18), 0, 0, 10, 100, 100, 1, 25, 10, 1e12);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side, address(pool6x18));

        vm.roll(100);

        IGammaPool.PoolData memory poolData = IPoolViewer(pool6x18.viewer()).getLatestPoolData(address(pool6x18));

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x18.viewer()).loan(address(pool6x18), _tokenId6x18);

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth)).balanceOf(cfmm6x18)*IERC20(address(usdc6)).balanceOf(cfmm6x18)));
        poolData.lastCFMMTotalSupply = IERC20(cfmm6x18).totalSupply();

        uint256 lpTokenDebt = loanData.liquidity * poolData.lastCFMMTotalSupply / poolData.lastCFMMInvariant;

        uint256 lpTokenPay = GSMath.min(uint256(lpTokenPerc) * lpTokenDebt / 250, lpTokenDebt);

        lpTokenPay = lpTokenPay == 0 ? 0 : lpTokenPay + 1000;

        uint256 expLiquidityPay = GSMath.min(lpTokenPay * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply, loanData.liquidity);

        IPositionManager.RepayLiquidityWithLPParams memory params = IPositionManager.RepayLiquidityWithLPParams({
            protocolId: 1,
            cfmm: cfmm6x18,
            tokenId: _tokenId6x18,
            lpTokens: lpTokenPay,
            collateralId: collateralId,
            to: toNum == 0 ? address(0) : vm.addr(toNum),
            deadline: type(uint256).max,
            minCollateral: new uint128[](2)
        });

        vm.startPrank(addr1);

        if(lpTokenPay == 0) {
            vm.expectRevert(bytes4(keccak256("NotEnoughLPDeposit()")));
            posMgr.repayLiquidityWithLP(params);
        } else if(loanData.liquidity > expLiquidityPay && loanData.liquidity - expLiquidityPay <= 1e12) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidityWithLP(params);
        } else {

            lpTokenDebt = loanData.liquidity;

            poolData.TOKEN_BALANCE[1] = uint128(IERC20(address(weth)).balanceOf(params.to)); // prev weth balance at user
            poolData.TOKEN_BALANCE[0] = uint128(IERC20(address(usdc6)).balanceOf(params.to)); // prev usdc6 balance at user

            (uint256 liquidityPaid, uint128[] memory tokensHeld) = posMgr.repayLiquidityWithLP(params);
            assertApproxEqAbs(liquidityPaid, expLiquidityPay, 1e3);

            if(params.to != address(0)) {
                uint128[] memory tokensHeldPart = new uint128[](2);
                tokensHeldPart[0] = uint128(GSMath.min(loanData.tokensHeld[0] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[0])));
                tokensHeldPart[1] = uint128(GSMath.min(loanData.tokensHeld[1] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[1])));
                assertApproxEqAbs(tokensHeld[0], loanData.tokensHeld[0] - tokensHeldPart[0], 1e1);
                assertApproxEqAbs(tokensHeld[1], loanData.tokensHeld[1] - tokensHeldPart[1], 1e1);

                if(collateralId > 0) {
                    if(collateralId == 1) {
                        assertGt(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGe(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    } else {
                        assertGe(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGt(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    }
                } else {
                    assertGt(IERC20(address(weth)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    assertGt(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    assertApproxEqAbs(tokensHeldPart[1], IERC20(address(weth)).balanceOf(params.to) - poolData.TOKEN_BALANCE[1],1e6);
                    assertApproxEqAbs(tokensHeldPart[0], IERC20(address(usdc6)).balanceOf(params.to) - poolData.TOKEN_BALANCE[0],1e6);
                }
            }

            loanData = pool6x18.loan(_tokenId6x18);

            assertEq(loanData.liquidity, lpTokenDebt - liquidityPaid);
        }

        vm.stopPrank();
    }

    function testRepayLiquidityWithLP6x6(uint8 tradeAmtPerc, bool side, uint8 lpTokenPerc, uint8 collateralId, uint8 toNum) public {
        collateralId = uint8(bound(collateralId, 0, 2));

        factory.setPoolParams(address(pool6x6), 0, 0, 10, 100, 100, 1, 25, 10, 1e6);// setting origination fees to zero

        bool chng = changePrice(tradeAmtPerc, side, address(pool6x6));

        vm.roll(100);

        IGammaPool.PoolData memory poolData = IPoolViewer(pool6x6.viewer()).getLatestPoolData(address(pool6x6));

        IGammaPool.LoanData memory loanData = IPoolViewer(pool6x6.viewer()).loan(address(pool6x6), _tokenId6x6);

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth6)).balanceOf(cfmm6x6)*IERC20(address(usdc6)).balanceOf(cfmm6x6)));
        poolData.lastCFMMTotalSupply = IERC20(cfmm6x6).totalSupply();

        uint256 lpTokenDebt = loanData.liquidity * poolData.lastCFMMTotalSupply / poolData.lastCFMMInvariant;

        uint256 lpTokenPay = GSMath.min(uint256(lpTokenPerc) * lpTokenDebt / 250, lpTokenDebt);

        lpTokenPay = lpTokenPay == 0 ? 0 : lpTokenPay + 1000;

        uint256 expLiquidityPay = GSMath.min(lpTokenPay * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply, loanData.liquidity);

        IPositionManager.RepayLiquidityWithLPParams memory params = IPositionManager.RepayLiquidityWithLPParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            tokenId: _tokenId6x6,
            lpTokens: lpTokenPay,
            collateralId: collateralId,
            to: toNum == 0 ? address(0) : vm.addr(toNum),
            deadline: type(uint256).max,
            minCollateral: new uint128[](2)
        });

        vm.startPrank(addr1);

        if(lpTokenPay == 0) {
            vm.expectRevert(bytes4(keccak256("NotEnoughLPDeposit()")));
            posMgr.repayLiquidityWithLP(params);
        } else if(loanData.liquidity > expLiquidityPay && loanData.liquidity - expLiquidityPay <= 1e6) {
            vm.expectRevert(bytes4(keccak256("MinBorrow()")));
            posMgr.repayLiquidityWithLP(params);
        } else {

            lpTokenDebt = loanData.liquidity;

            poolData.TOKEN_BALANCE[1] = uint128(IERC20(address(weth6)).balanceOf(params.to)); // prev weth6 balance at user
            poolData.TOKEN_BALANCE[0] = uint128(IERC20(address(usdc6)).balanceOf(params.to)); // prev usdc6 balance at user

            (uint256 liquidityPaid, uint128[] memory tokensHeld) = posMgr.repayLiquidityWithLP(params);
            assertApproxEqAbs(liquidityPaid, expLiquidityPay, 1e3);

            if(params.to != address(0)) {
                uint128[] memory tokensHeldPart = new uint128[](2);
                tokensHeldPart[0] = uint128(GSMath.min(loanData.tokensHeld[0] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[0])));
                tokensHeldPart[1] = uint128(GSMath.min(loanData.tokensHeld[1] * expLiquidityPay / lpTokenDebt, uint256(loanData.tokensHeld[1])));
                assertApproxEqAbs(tokensHeld[0], loanData.tokensHeld[0] - tokensHeldPart[0], 1e1);
                assertApproxEqAbs(tokensHeld[1], loanData.tokensHeld[1] - tokensHeldPart[1], 1e1);

                if(collateralId > 0) {
                    if(collateralId == 1) {
                        assertGt(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGe(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    } else {
                        assertGe(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                        assertGt(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    }
                } else {
                    assertGt(IERC20(address(weth6)).balanceOf(params.to), poolData.TOKEN_BALANCE[1]);
                    assertGt(IERC20(address(usdc6)).balanceOf(params.to), poolData.TOKEN_BALANCE[0]);
                    assertApproxEqAbs(tokensHeldPart[1], IERC20(address(weth6)).balanceOf(params.to) - poolData.TOKEN_BALANCE[1],1e6);
                    assertApproxEqAbs(tokensHeldPart[0], IERC20(address(usdc6)).balanceOf(params.to) - poolData.TOKEN_BALANCE[0],1e6);
                }
            }

            loanData = pool6x6.loan(_tokenId6x6);

            assertEq(loanData.liquidity, lpTokenDebt - liquidityPaid);
        }

        vm.stopPrank();
    }
}
