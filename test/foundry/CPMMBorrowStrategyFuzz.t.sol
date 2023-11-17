// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMBorrowStrategyFuzz is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap(true);

        uint256 usdcAmount = 2_500_000 / 2;
        uint256 wethAmount = 1_250 / 2;

        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);
    }

    function testIncreaseCollateral18x18(uint24 amount0, uint24 amount1, uint72 ratio0, uint72 ratio1) public {
        amount0 = amount0 / 10;
        amount1 = amount1 / 10;

        if(amount0 < 1) amount0 = 1;
        if(amount1 < 1) amount1 = 1;
        if(ratio0 < 1e18) ratio0 = 1e18;
        if(ratio1 < 1e18) ratio1 = 1e18;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(amount0)*1e18;
        amounts[1] = uint256(amount1)*1e18;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = ratio0;
        ratio[1] = ratio1;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        IPositionManager.AddCollateralParams memory params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0)
        });

        uint256 beforeWethBalance = IERC20(weth).balanceOf(address(pool));
        uint256 beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool));

        uint128[] memory tokensHeld = posMgr.increaseCollateral(params);

        uint256 afterWethBalance = IERC20(weth).balanceOf(address(pool));
        uint256 afterUSDCBalance = IERC20(usdc).balanceOf(address(pool));

        assertEq(tokensHeld[0], amounts[0]);
        assertEq(tokensHeld[1], amounts[1]);
        assertEq(tokensHeld[0], afterWethBalance - beforeWethBalance);
        assertEq(tokensHeld[1], afterUSDCBalance - beforeUSDCBalance);

        vm.stopPrank();

        vm.startPrank(addr2);

        tokenId = posMgr.createLoan(1, cfmm, addr2, 0, type(uint256).max);
        assertGt(tokenId, 0);

        params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: ratio
        });

        tokensHeld = posMgr.increaseCollateral(params);

        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        uint256 strikePx = uint256(tokensHeld[1]) * 1e18 / tokensHeld[0];
        uint256 expectedStrikePx = ratio[1] * 1e18 / ratio[0];

        assertApproxEqAbs(strikePx, expectedStrikePx, 1e8);

        vm.stopPrank();
    }

    function testDecreaseCollateral18x18(uint8 amount0, uint8 amount1, uint72 ratio0, uint72 ratio1, uint8 _addr) public {
        _addr = _addr == 0 ? 1 : _addr;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 200*1e18;
        amounts[1] = 400_000*1e18;

        IPositionManager.AddCollateralParams memory _params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0)
        });

        uint128[] memory tokensHeld = posMgr.increaseCollateral(_params);

        amount0 = amount0 / 2;
        amount1 = amount1 / 2;

        if(ratio0 < 1e18) ratio0 = 1e18;
        if(ratio1 < 1e18) ratio1 = 1e18;

        uint128[] memory _amounts = new uint128[](2);
        _amounts[0] = uint128(amount0)*1e18;
        _amounts[1] = uint128(amount1)*1e18;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = tokensHeld[0] - _amounts[0];
        ratio[1] = tokensHeld[1] - _amounts[1];

        IPositionManager.RemoveCollateralParams memory params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: new uint256[](0)
        });

        uint256 beforeWethBalance = IERC20(weth).balanceOf(address(pool));
        uint256 beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool));
        uint256 beforeWethBalanceAddr = IERC20(weth).balanceOf(params.to);
        uint256 beforeUSDCBalanceAddr = IERC20(usdc).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(tokensHeld[0], ratio[0]);
        assertEq(tokensHeld[1], ratio[1]);
        assertEq(_amounts[0], beforeWethBalance - IERC20(weth).balanceOf(address(pool)));
        assertEq(_amounts[1], beforeUSDCBalance - IERC20(usdc).balanceOf(address(pool)));
        assertEq(_amounts[0], IERC20(weth).balanceOf(params.to) - beforeWethBalanceAddr);
        assertEq(_amounts[1], IERC20(usdc).balanceOf(params.to) - beforeUSDCBalanceAddr);

        _amounts[0] = tokensHeld[0] > _amounts[0] ? (tokensHeld[0] - _amounts[0]) / 2 : 0;
        _amounts[1] = tokensHeld[1] > _amounts[1] ? (tokensHeld[1] - _amounts[1]) / 2 : 0;

        ratio[0] = ratio0;
        ratio[1] = ratio1;

        params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: ratio
        });

        beforeWethBalance = IERC20(weth).balanceOf(address(pool));
        beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool));
        beforeWethBalanceAddr = IERC20(weth).balanceOf(params.to);
        beforeUSDCBalanceAddr = IERC20(usdc).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(beforeWethBalance > IERC20(weth).balanceOf(address(pool)) || beforeUSDCBalance > IERC20(usdc).balanceOf(address(pool)), true);
        assertEq(_amounts[0], IERC20(weth).balanceOf(params.to) - beforeWethBalanceAddr);
        assertEq(_amounts[1], IERC20(usdc).balanceOf(params.to) - beforeUSDCBalanceAddr);

        assertApproxEqAbs(uint256(tokensHeld[1]) * 1e18 / tokensHeld[0], ratio[1] * 1e18 / ratio[0], 1e8);

        vm.stopPrank();
    }

    function testBorrowLiquidity18x18(uint8 amount0, uint8 amount1, uint8 lpTokens, uint72 ratio0, uint72 ratio1, uint8 _addr) public {
        if(amount0 == 0 || amount1 == 0) {
            if(amount0 < 10) amount0 = 10;
        } else {
            if(amount0 < 10) amount0 = 10;
            if(amount1 < 10) amount1 = 10;
        }
        if(lpTokens < 1) lpTokens = 1;
        if(ratio0 < 1) ratio0 = 1;
        if(ratio1 < 1) ratio1 = 1;

        if(ratio1 > ratio0) {
            if(ratio1 / ratio0 > 5) {
                ratio1 = 5 * ratio0;
            }
        } else if(ratio0 > ratio1) {
            if(ratio0 / ratio1 > 5) {
                ratio0 = 5 * ratio1;
            }
        }

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = uint256(amount0)*1e18;
        _amounts[1] = uint256(amount1)*1e18;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: _addr == 0 ? addr1 : vm.addr(_addr),
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e18,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool.getPoolData();
        uint256 liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = liquidity * IERC20(address(weth)).balanceOf(cfmm) / poolData.lastCFMMInvariant;
        ratio[1] = liquidity * IERC20(address(usdc)).balanceOf(cfmm) / poolData.lastCFMMInvariant;

        (uint256 tokenId, uint128[] memory tokensHeld, uint256 liquidityBorrowed, uint256[] memory amounts) =
            posMgr.createLoanBorrowAndRebalance(params);

        assertEq(params.to, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertEq(liquidityBorrowed,liquidity);
        assertEq(tokensHeld[0],_amounts[0]);
        assertEq(tokensHeld[1],_amounts[1]);
        assertApproxEqAbs(ratio[0],amounts[0],1e2);
        assertApproxEqAbs(ratio[1],amounts[1],1e2);

        vm.stopPrank();

        vm.startPrank(addr2);

        poolData = pool.getPoolData();
        liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        if(ratio0 == ratio1) {
            ratio = new uint256[](0);
        } else {
            ratio[0] = IERC20(address(weth)).balanceOf(cfmm) * ratio0;
            ratio[1] = IERC20(address(usdc)).balanceOf(cfmm) * ratio1;
        }

        params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr2,
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e18,
            ratio: ratio,
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth)).balanceOf(cfmm)*IERC20(address(usdc)).balanceOf(cfmm)));

        _amounts[0] = liquidity * IERC20(address(weth)).balanceOf(cfmm) / poolData.lastCFMMInvariant;
        _amounts[1] = liquidity * IERC20(address(usdc)).balanceOf(cfmm) / poolData.lastCFMMInvariant;

        (tokenId, tokensHeld, liquidityBorrowed, amounts) = posMgr.createLoanBorrowAndRebalance(params);

        assertEq(addr2, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertEq(liquidityBorrowed,liquidity);
        assertEq(tokensHeld[0],params.amounts[0]);
        assertEq(tokensHeld[1],params.amounts[1]);
        assertApproxEqAbs(_amounts[0],amounts[0],1e2);
        assertApproxEqAbs(_amounts[1],amounts[1],1e2);

        if(ratio.length == 2) {
            IGammaPool.LoanData memory loanData = pool.loan(tokenId);
            assertApproxEqAbs(uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e6);
        }

        vm.stopPrank();
    }

    function testRebalanceCollateral18x18(uint72 ratio0, uint72 ratio1, bool useRatio, bool side, bool buy) public {
        if(ratio0 < 1e4) ratio0 = 1e4;
        if(ratio1 < 1e4) ratio1 = 1e4;

        if(ratio1 > ratio0) {
            if(ratio1 / ratio0 > 10) {
                ratio1 = 10 * ratio0;
            }
        } else if(ratio0 > ratio1) {
            if(ratio0 / ratio1 > 10) {
                ratio0 = 10 * ratio1;
            }
        }

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 10*1*1e18;
        _amounts[1] = 10*2000*1e18;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: 100*1e18,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool.getPoolData();

        (uint256 tokenId, uint128[] memory tokensHeld,,) = posMgr.createLoanBorrowAndRebalance(params);

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);

        tokensHeld = loanData.tokensHeld;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = IERC20(address(weth)).balanceOf(cfmm);
        ratio[1] = IERC20(address(usdc)).balanceOf(cfmm);
        int256[] memory deltas = new int256[](2);
        if(useRatio && ratio0 != ratio1) {
            deltas = new int256[](0);
            ratio[0] = ratio[0] * ratio0;
            ratio[1] = ratio[1] * ratio1;
        } else {
            deltas = new int256[](2);
            if(side) {
                if(!buy) {
                    deltas[0] = -int256(GSMath.min(tokensHeld[0],ratio0)/4);
                } else {
                    if(uint256(ratio0) * ratio[1] / ratio[0] > tokensHeld[1] / 4) {
                        deltas[0] = int256(uint256(tokensHeld[0]) / 4);
                    } else {
                        deltas[0] = int256(uint256(ratio0) / 4);
                    }
                }
            } else {
                if(!buy) {
                    deltas[1] = -int256(GSMath.min(tokensHeld[1],ratio1)/4);
                } else {
                    if(uint256(ratio1) * ratio[0] / ratio[1] > tokensHeld[0] / 4) {
                        deltas[1] = int256(uint256(tokensHeld[1]) / 4);
                    } else {
                        deltas[1] = int256(uint256(ratio1) / 4);
                    }
                }
            }
            ratio = new uint256[](0);
            if(deltas[0] == 0 && deltas[1] == 0) {
                deltas = new int256[](0);
            }
        }

        if(ratio.length > 0 || deltas.length > 0) {
            IPositionManager.RebalanceCollateralParams memory params = IPositionManager.RebalanceCollateralParams({
                protocolId: 1,
                cfmm: cfmm,
                tokenId: tokenId,
                deltas: deltas,
                ratio: ratio,
                minCollateral: new uint128[](2),
                deadline: type(uint256).max
            });

            tokensHeld = posMgr.rebalanceCollateral(params);

            if(ratio.length > 0) {
                assertApproxEqAbs(uint256(tokensHeld[1]) * 1e18 / tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e6);
            } else {
                if(deltas[0] > 0) {
                    assertEq(tokensHeld[0],loanData.tokensHeld[0] + uint256(deltas[0]));
                    assertLt(tokensHeld[1],loanData.tokensHeld[1]);
                } else if(deltas[1] > 0) {
                    assertLt(tokensHeld[0],loanData.tokensHeld[0]);
                    assertEq(tokensHeld[1],loanData.tokensHeld[1] + uint256(deltas[1]));
                } else if(deltas[0] < 0) {
                    assertEq(tokensHeld[0],loanData.tokensHeld[0] - uint256(-deltas[0]));
                    assertGt(tokensHeld[1],loanData.tokensHeld[1]);
                } else if(deltas[1] < 0) {
                    assertGt(tokensHeld[0],loanData.tokensHeld[0]);
                    assertEq(tokensHeld[1],loanData.tokensHeld[1] - uint256(-deltas[1]));
                }
            }
        }
    }
}
