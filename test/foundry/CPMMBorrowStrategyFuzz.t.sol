// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract CPMMBorrowStrategyFuzz is CPMMGammaSwapSetup {
    uint256 public usdcAmount = 2_500_000 / 2;
    uint256 public wethAmount = 1_250 / 2;

    function setUp() public {
        super.initCPMMGammaSwap(true);
    }

    function testEmptyPool() public {
        IPoolViewer viewer = IPoolViewer(IGammaPool(pool).viewer());
        IGammaPool.PoolData memory poolData = viewer.getLatestPoolData(address(pool));
        assertEq(poolData.lastPrice, 0);
        assertEq(viewer.canLiquidate(address(pool),1), false);

        IGammaPool.LoanData memory loanData = viewer.loan(address(pool),1);
        assertEq(loanData.liquidity, 0);
        assertEq(loanData.id, 0);

        IGammaPool.LoanData[] memory _loans = viewer.getLoans(address(pool), 0, 100, true);
        assertEq(_loans.length, 0);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        _loans = viewer.getLoansById(address(pool), tokenIds, true);
        assertEq(_loans.length, 3);
        assertEq(_loans[0].liquidity, 0);
        assertEq(_loans[0].id, 0);
        assertEq(_loans[1].liquidity, 0);
        assertEq(_loans[1].id, 0);
        assertEq(_loans[2].liquidity, 0);
        assertEq(_loans[2].id, 0);

        IGammaPool.RateData memory rateData = viewer.getLatestRates(address(pool));
        assertEq(rateData.accFeeIndex, 1e18);
    }

    function testIncreaseCollateral18x18(uint24 amount0, uint24 amount1, uint72 ratio0, uint72 ratio1) public {
        lockProtocol();
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);

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
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
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
            ratio: ratio,
            minCollateral: new uint128[](0)
        });

        tokensHeld = posMgr.increaseCollateral(params);

        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        uint256 strikePx = uint256(tokensHeld[1]) * 1e18 / tokensHeld[0];
        uint256 expectedStrikePx = ratio[1] * 1e18 / ratio[0];

        assertApproxEqAbs(strikePx, expectedStrikePx, 1e8);

        vm.stopPrank();
    }
    function testIncreaseCollateral18x6(uint24 amount0, uint8 amount1, uint256 ratio0, uint256 ratio1) public {
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);

        amount0 = amount0 / 10;
        amount1 = amount1 / 10;

        if(amount0 < 1) amount0 = 1;
        if(amount1 < 1) amount1 = 1;
        ratio0 = bound(ratio0, 1e18, 1e22);
        ratio1 = bound(ratio1, 1e4, 1e8);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(amount0)*1e18;
        amounts[1] = uint256(amount1)*1e6;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = ratio0;
        ratio[1] = ratio1;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm18x6, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        IPositionManager.AddCollateralParams memory params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint256 beforeWeth6Balance = IERC20(weth6).balanceOf(address(pool18x6));
        uint256 beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool18x6));

        uint128[] memory tokensHeld = posMgr.increaseCollateral(params);

        uint256 afterWeth6Balance = IERC20(weth6).balanceOf(address(pool18x6));
        uint256 afterUSDCBalance = IERC20(usdc).balanceOf(address(pool18x6));

        assertEq(tokensHeld[0], amounts[0]);
        assertEq(tokensHeld[1], amounts[1]);
        assertEq(tokensHeld[0], afterUSDCBalance - beforeUSDCBalance);
        assertEq(tokensHeld[1], afterWeth6Balance - beforeWeth6Balance);

        vm.stopPrank();

        vm.startPrank(addr2);

        tokenId = posMgr.createLoan(1, cfmm18x6, addr2, 0, type(uint256).max);
        assertGt(tokenId, 0);

        params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: ratio,
            minCollateral: new uint128[](0)
        });

        tokensHeld = posMgr.increaseCollateral(params);

        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        uint256 strikePx = uint256(tokensHeld[1]) * 1e18 / tokensHeld[0];
        uint256 expectedStrikePx = ratio[1] * 1e18 / ratio[0];

        assertApproxEqAbs(strikePx, expectedStrikePx, 1e12);    // 0.0001% delta

        vm.stopPrank();
    }
    function testIncreaseCollateral6x6(uint24 amount0, uint8 amount1, uint256 ratio0, uint256 ratio1) public {
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);

        if(amount0 < 1) amount0 = 1;
        if(amount1 < 1) amount1 = 1;
        ratio0 = bound(ratio0, 1e18, 1e20);
        ratio1 = bound(ratio1, 1e14, 1e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(amount0)*1e6;
        amounts[1] = uint256(amount1)*1e6;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = ratio0;
        ratio[1] = ratio1;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm6x6, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        IPositionManager.AddCollateralParams memory params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint256 beforeWeth6Balance = IERC20(weth6).balanceOf(address(pool6x6));
        uint256 beforeUSDC6Balance = IERC20(usdc6).balanceOf(address(pool6x6));

        uint128[] memory tokensHeld = posMgr.increaseCollateral(params);

        uint256 afterWeth6Balance = IERC20(weth6).balanceOf(address(pool6x6));
        uint256 afterUSDC6Balance = IERC20(usdc6).balanceOf(address(pool6x6));

        assertEq(tokensHeld[0], amounts[0]);
        assertEq(tokensHeld[1], amounts[1]);
        assertEq(tokensHeld[0], afterUSDC6Balance - beforeUSDC6Balance);
        assertEq(tokensHeld[1], afterWeth6Balance - beforeWeth6Balance);

        vm.stopPrank();

        vm.startPrank(addr2);

        tokenId = posMgr.createLoan(1, cfmm6x6, addr2, 0, type(uint256).max);
        assertGt(tokenId, 0);

        params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: ratio,
            minCollateral: new uint128[](0)
        });

        tokensHeld = posMgr.increaseCollateral(params);

        assertGt(tokensHeld[0], 0);
        assertGt(tokensHeld[1], 0);

        uint256 strikePx = uint256(tokensHeld[1]) * 1e14 / tokensHeld[0];
        uint256 expectedStrikePx = ratio[1] * 1e14 / ratio[0];

        assertApproxEqAbs(strikePx, expectedStrikePx, 1e14);

        vm.stopPrank();
    }

    function testDecreaseCollateral18x18(uint8 amount0, uint8 amount1, uint72 ratio0, uint72 ratio1, uint8 _addr) public {
        lockProtocol();
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);

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
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
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
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
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
            ratio: ratio,
            minCollateral: new uint128[](0)
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
    function testDecreaseCollateral18x6(uint8 amount0, uint8 amount1, uint256 ratio0, uint256 ratio1, uint8 _addr) public {
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);

        _addr = _addr == 0 ? 1 : _addr;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm18x6, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 400_000*1e18;
        amounts[1] = 200*1e6;

        IPositionManager.AddCollateralParams memory _params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint128[] memory tokensHeld = posMgr.increaseCollateral(_params);

        amount0 = amount0 / 2;
        amount1 = amount1 / 2;

        ratio0 = bound(ratio0, 1e18, 1e22);
        ratio1 = bound(ratio1, 1e4, 1e8);

        uint128[] memory _amounts = new uint128[](2);
        _amounts[0] = uint128(amount0)*1e18;
        _amounts[1] = uint128(amount1)*1e6;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = tokensHeld[0] - _amounts[0];
        ratio[1] = tokensHeld[1] - _amounts[1];

        IPositionManager.RemoveCollateralParams memory params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint256 beforeWethBalance = IERC20(weth6).balanceOf(address(pool18x6));
        uint256 beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool18x6));
        uint256 beforeWethBalanceAddr = IERC20(weth6).balanceOf(params.to);
        uint256 beforeUSDCBalanceAddr = IERC20(usdc).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(tokensHeld[0], ratio[0]);
        assertEq(tokensHeld[1], ratio[1]);
        assertEq(_amounts[0], beforeUSDCBalance - IERC20(usdc).balanceOf(address(pool18x6)));
        assertEq(_amounts[1], beforeWethBalance - IERC20(weth6).balanceOf(address(pool18x6)));
        assertEq(_amounts[0], IERC20(usdc).balanceOf(params.to) - beforeUSDCBalanceAddr);
        assertEq(_amounts[1], IERC20(weth6).balanceOf(params.to) - beforeWethBalanceAddr);

        _amounts[0] = tokensHeld[0] > _amounts[0] ? (tokensHeld[0] - _amounts[0]) / 2 : 0;
        _amounts[1] = tokensHeld[1] > _amounts[1] ? (tokensHeld[1] - _amounts[1]) / 2 : 0;

        ratio[0] = ratio0;
        ratio[1] = ratio1;

        params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: ratio,
            minCollateral: new uint128[](0)
        });

        beforeWethBalance = IERC20(weth6).balanceOf(address(pool18x6));
        beforeUSDCBalance = IERC20(usdc).balanceOf(address(pool18x6));
        beforeWethBalanceAddr = IERC20(weth6).balanceOf(params.to);
        beforeUSDCBalanceAddr = IERC20(usdc).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(beforeWethBalance > IERC20(weth6).balanceOf(address(pool18x6)) || beforeUSDCBalance > IERC20(usdc).balanceOf(address(pool18x6)), true);
        assertEq(_amounts[0], IERC20(usdc).balanceOf(params.to) - beforeUSDCBalanceAddr);
        assertEq(_amounts[1], IERC20(weth6).balanceOf(params.to) - beforeWethBalanceAddr);
        assertApproxEqAbs(uint256(tokensHeld[1]) * 1e18 / tokensHeld[0], ratio[1] * 1e18 / ratio[0], 1e12);

        vm.stopPrank();
    }
    function testDecreaseCollateral6x6(uint8 amount0, uint8 amount1, uint256 ratio0, uint256 ratio1, uint8 _addr) public {
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);

        _addr = _addr == 0 ? 1 : _addr;

        vm.startPrank(addr1);
        uint256 tokenId = posMgr.createLoan(1, cfmm6x6, addr1, 0, type(uint256).max);
        assertGt(tokenId, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 400_000*1e6;
        amounts[1] = 200*1e6;

        IPositionManager.AddCollateralParams memory _params = IPositionManager.AddCollateralParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: address(0),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint128[] memory tokensHeld = posMgr.increaseCollateral(_params);

        amount0 = amount0 / 2;
        amount1 = amount1 / 2;

        ratio0 = bound(ratio0, 1e18, 1e20);
        ratio1 = bound(ratio1, 1e18, 1e20);

        uint128[] memory _amounts = new uint128[](2);
        _amounts[0] = uint128(amount0)*1e6;
        _amounts[1] = uint128(amount1)*1e6;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = tokensHeld[0] - _amounts[0];
        ratio[1] = tokensHeld[1] - _amounts[1];

        IPositionManager.RemoveCollateralParams memory params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: new uint256[](0),
            minCollateral: new uint128[](0)
        });

        uint256 beforeWethBalance = IERC20(weth6).balanceOf(address(pool6x6));
        uint256 beforeUSDCBalance = IERC20(usdc6).balanceOf(address(pool6x6));
        uint256 beforeWethBalanceAddr = IERC20(weth6).balanceOf(params.to);
        uint256 beforeUSDCBalanceAddr = IERC20(usdc6).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(tokensHeld[0], ratio[0]);
        assertEq(tokensHeld[1], ratio[1]);
        assertEq(_amounts[0], beforeUSDCBalance - IERC20(usdc6).balanceOf(address(pool6x6)));
        assertEq(_amounts[1], beforeWethBalance - IERC20(weth6).balanceOf(address(pool6x6)));
        assertEq(_amounts[0], IERC20(usdc6).balanceOf(params.to) - beforeUSDCBalanceAddr);
        assertEq(_amounts[1], IERC20(weth6).balanceOf(params.to) - beforeWethBalanceAddr);

        _amounts[0] = tokensHeld[0] > _amounts[0] ? (tokensHeld[0] - _amounts[0]) / 2 : 0;
        _amounts[1] = tokensHeld[1] > _amounts[1] ? (tokensHeld[1] - _amounts[1]) / 2 : 0;

        ratio[0] = ratio0;
        ratio[1] = ratio1;

        params = IPositionManager.RemoveCollateralParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: vm.addr(_addr),
            tokenId: tokenId,
            deadline: type(uint256).max,
            amounts: _amounts,
            ratio: ratio,
            minCollateral: new uint128[](0)
        });

        beforeWethBalance = IERC20(weth6).balanceOf(address(pool6x6));
        beforeUSDCBalance = IERC20(usdc6).balanceOf(address(pool6x6));
        beforeWethBalanceAddr = IERC20(weth6).balanceOf(params.to);
        beforeUSDCBalanceAddr = IERC20(usdc6).balanceOf(params.to);

        tokensHeld = posMgr.decreaseCollateral(params);

        assertEq(beforeWethBalance > IERC20(weth6).balanceOf(address(pool6x6)) || beforeUSDCBalance > IERC20(usdc6).balanceOf(address(pool6x6)), true);
        assertEq(_amounts[0], IERC20(usdc6).balanceOf(params.to) - beforeUSDCBalanceAddr);
        assertEq(_amounts[1], IERC20(weth6).balanceOf(params.to) - beforeWethBalanceAddr);
        assertApproxEqAbs(uint256(tokensHeld[1]) * 1e12 / tokensHeld[0], ratio[1] * 1e12 / ratio[0], 1e14);

        vm.stopPrank();
    }

    function testBorrowLiquidity18x18(uint8 amount0, uint8 amount1, uint8 lpTokens, uint72 ratio0, uint72 ratio1) public {
        lockProtocol();
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

        uint8 _addr = 0;
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

        IGammaPool.LoanData memory loanData = pool.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);

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
        loanData = pool.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);
        assertApproxEqAbs(_amounts[0],amounts[0],1e2);
        assertApproxEqAbs(_amounts[1],amounts[1],1e2);

        if(ratio.length == 2) {
            assertApproxEqAbs(uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e8);
        }

        vm.stopPrank();
    }
    function testBorrowLiquidity18x6(uint8 amount0, uint8 amount1, uint8 lpTokens, uint72 ratio0, uint72 ratio1) public {
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        uint8 _addr = 0;
        if(amount0 == 0 || amount1 == 0) {
            if(amount1 < 10) amount1 = 10;
        } else {
            if(amount0 < 10) amount0 = 10;
            if(amount1 < 10) amount1 = 10;
        }
        if(lpTokens < 1) lpTokens = 1;
        if(ratio0 < 1) ratio0 = 1;
        if(ratio1 < 1) ratio1 = 1;

        if(ratio0 > ratio1) {
            if(ratio0 / ratio1 > 5) {
                ratio0 = 5 * ratio1;
            }
        } else if(ratio1 > ratio0) {
            if(ratio1 / ratio0 > 5) {
                ratio1 = 5 * ratio0;
            }
        }

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = uint256(amount0)*1e18;
        _amounts[1] = uint256(amount1)*1e6;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: _addr == 0 ? addr1 : vm.addr(_addr),
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e12,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();
        uint256 liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = liquidity * IERC20(address(usdc)).balanceOf(cfmm18x6) / poolData.lastCFMMInvariant;
        ratio[1] = liquidity * IERC20(address(weth6)).balanceOf(cfmm18x6) / poolData.lastCFMMInvariant;

        (uint256 tokenId, uint128[] memory tokensHeld, uint256 liquidityBorrowed, uint256[] memory amounts) =
            posMgr.createLoanBorrowAndRebalance(params);

        assertEq(params.to, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertApproxEqAbs(liquidityBorrowed, liquidity, 1e12);
        IGammaPool.LoanData memory loanData = pool18x6.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);
        assertApproxEqAbs(ratio[0],amounts[0],1e2);
        assertApproxEqAbs(ratio[1],amounts[1],1e2);

        vm.stopPrank();

        vm.startPrank(addr2);

        poolData = pool18x6.getPoolData();
        liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        if(ratio0 == ratio1) {
            ratio = new uint256[](0);
        } else {
            ratio[0] = IERC20(address(usdc)).balanceOf(cfmm18x6) * ratio0;
            ratio[1] = IERC20(address(weth6)).balanceOf(cfmm18x6) * ratio1;
        }

        params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr2,
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e12,
            ratio: ratio,
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth6)).balanceOf(cfmm18x6)*IERC20(address(usdc)).balanceOf(cfmm18x6)));

        _amounts[0] = liquidity * IERC20(address(usdc)).balanceOf(cfmm18x6) / poolData.lastCFMMInvariant;
        _amounts[1] = liquidity * IERC20(address(weth6)).balanceOf(cfmm18x6) / poolData.lastCFMMInvariant;

        (tokenId, tokensHeld, liquidityBorrowed, amounts) = posMgr.createLoanBorrowAndRebalance(params);

        assertEq(addr2, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertApproxEqAbs(liquidityBorrowed,liquidity, 1e12);loanData = pool.loan(tokenId);
        loanData = pool18x6.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);
        assertApproxEqAbs(_amounts[0],amounts[0],1e14);
        assertApproxEqAbs(_amounts[1],amounts[1],1e14);

        if(ratio.length == 2) {
            assertApproxEqAbs(uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e8);
        }

        vm.stopPrank();
    }
    function testBorrowLiquidity6x6(uint8 amount0, uint8 amount1, uint8 lpTokens, uint72 ratio0, uint72 ratio1) public {
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        uint8 _addr = 0;
        if(amount0 == 0 || amount1 == 0) {
            if(amount1 < 10) amount1 = 10;
        } else {
            if(amount0 < 10) amount0 = 10;
            if(amount1 < 10) amount1 = 10;
        }
        if(lpTokens < 1) lpTokens = 1;
        if(ratio0 < 1) ratio0 = 1;
        if(ratio1 < 1) ratio1 = 1;

        if(ratio0 > ratio1) {
            if(ratio0 / ratio1 > 5) {
                ratio0 = 5 * ratio1;
            }
        } else if(ratio1 > ratio0) {
            if(ratio1 / ratio0 > 5) {
                ratio1 = 5 * ratio0;
            }
        }

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = uint256(amount0)*1e6;
        _amounts[1] = uint256(amount1)*1e6;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: _addr == 0 ? addr1 : vm.addr(_addr),
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e6,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();
        uint256 liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = liquidity * IERC20(address(usdc6)).balanceOf(cfmm6x6) / poolData.lastCFMMInvariant;
        ratio[1] = liquidity * IERC20(address(weth6)).balanceOf(cfmm6x6) / poolData.lastCFMMInvariant;

        (uint256 tokenId, uint128[] memory tokensHeld, uint256 liquidityBorrowed, uint256[] memory amounts) =
            posMgr.createLoanBorrowAndRebalance(params);

        assertEq(params.to, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertApproxEqAbs(liquidityBorrowed, liquidity, 1e14);
        IGammaPool.LoanData memory loanData = pool6x6.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);
        assertApproxEqAbs(ratio[0],amounts[0],1e2);
        assertApproxEqAbs(ratio[1],amounts[1],1e2);

        vm.stopPrank();

        vm.startPrank(addr2);

        poolData = pool6x6.getPoolData();
        liquidity = params.lpTokens * poolData.lastCFMMInvariant / poolData.lastCFMMTotalSupply;

        if(ratio0 == ratio1) {
            ratio = new uint256[](0);
        } else {
            ratio[0] = IERC20(address(usdc6)).balanceOf(cfmm6x6) * ratio0;
            ratio[1] = IERC20(address(weth6)).balanceOf(cfmm6x6) * ratio1;
        }

        params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr2,
            refId: 0,
            amounts: _amounts,
            lpTokens: uint256(lpTokens)*1e6,
            ratio: ratio,
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        poolData.lastCFMMInvariant = uint128(GSMath.sqrt(IERC20(address(weth6)).balanceOf(cfmm6x6)*IERC20(address(usdc6)).balanceOf(cfmm6x6)));

        _amounts[0] = liquidity * IERC20(address(usdc6)).balanceOf(cfmm6x6) / poolData.lastCFMMInvariant;
        _amounts[1] = liquidity * IERC20(address(weth6)).balanceOf(cfmm6x6) / poolData.lastCFMMInvariant;

        (tokenId, tokensHeld, liquidityBorrowed, amounts) = posMgr.createLoanBorrowAndRebalance(params);

        assertEq(addr2, posMgr.ownerOf(tokenId));
        assertGt(liquidityBorrowed,0);
        assertApproxEqAbs(liquidityBorrowed,liquidity, 1e14);
        loanData = pool6x6.loan(tokenId);
        assertEq(tokensHeld[0],loanData.tokensHeld[0]);
        assertEq(tokensHeld[1],loanData.tokensHeld[1]);
        assertApproxEqAbs(_amounts[0],amounts[0],1e14);
        assertApproxEqAbs(_amounts[1],amounts[1],1e14);

        if(ratio.length == 2) {
            assertApproxEqAbs(uint256(loanData.tokensHeld[1]) * 1e18 / loanData.tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e14);
        }

        vm.stopPrank();
    }

    function testRebalanceCollateral18x18(uint72 ratio0, uint72 ratio1, bool useRatio, bool side, bool buy) public {
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth), usdcAmount*1e18, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool, cfmm, addr2);

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
            IPositionManager.RebalanceCollateralParams memory params2 = IPositionManager.RebalanceCollateralParams({
                protocolId: 1,
                cfmm: cfmm,
                tokenId: tokenId,
                deltas: deltas,
                ratio: ratio,
                minCollateral: new uint128[](2),
                deadline: type(uint256).max
            });

            tokensHeld = posMgr.rebalanceCollateral(params2);

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
    function testRebalanceCollateral18x6(uint72 ratio0, uint72 ratio1, bool useRatio, bool side, bool buy) public {
        lockProtocol();
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), usdcAmount*1e18, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        if(ratio0 < 1e4) ratio0 = 1e4;
        if(ratio1 < 1e4) ratio1 = 1e4;
        if(ratio0 > 1e12) ratio0 = 1e12;
        if(ratio1 > 1e12) ratio1 = 1e12;

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
        _amounts[0] = 10*2000*1e18;
        _amounts[1] = 10*1*1e6;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm18x6,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: 100*1e12,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool18x6.getPoolData();
        (uint256 tokenId, uint128[] memory tokensHeld,,) = posMgr.createLoanBorrowAndRebalance(params);
        IGammaPool.LoanData memory loanData = pool18x6.loan(tokenId);

        tokensHeld = loanData.tokensHeld;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = IERC20(address(usdc)).balanceOf(cfmm18x6);
        ratio[1] = IERC20(address(weth6)).balanceOf(cfmm18x6);
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
                cfmm: cfmm18x6,
                tokenId: tokenId,
                deltas: deltas,
                ratio: ratio,
                minCollateral: new uint128[](2),
                deadline: type(uint256).max
            });

            tokensHeld = posMgr.rebalanceCollateral(params);

            IGammaPool.LoanData memory loanData1 = pool18x6.loan(tokenId);
            assertEq(loanData1.tokensHeld[0], tokensHeld[0]);
            assertEq(loanData1.tokensHeld[1], tokensHeld[1]);

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
                    if(-deltas[0] < 1e18) {
                        assertGe(tokensHeld[1],loanData.tokensHeld[1]);
                    } else {
                        assertGt(tokensHeld[1],loanData.tokensHeld[1]);
                    }
                } else if(deltas[1] < 0) {
                    if(-deltas[1] < 1e18) {
                        assertGe(tokensHeld[0],loanData.tokensHeld[0]);
                    } else {
                        assertGt(tokensHeld[0],loanData.tokensHeld[0]);
                    }
                    assertEq(tokensHeld[1],loanData.tokensHeld[1] - uint256(-deltas[1]));
                }
            }
        }
    }

    function testRebalanceCollateral6x18(uint72 ratio0, uint72 ratio1, bool useRatio, bool side, bool buy) public {
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), usdcAmount*1e6, wethAmount*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool6x18, cfmm6x18, addr2);

        if(ratio0 < 1e4) ratio0 = 1e4;
        if(ratio1 < 1e4) ratio1 = 1e4;
        if(ratio0 > 1e12) ratio0 = 1e12;
        if(ratio1 > 1e12) ratio1 = 1e12;

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
        _amounts[0] = 10*2000*1e6;
        _amounts[1] = 10*1*1e18;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
        protocolId: 1,
        cfmm: cfmm6x18,
        to: addr1,
        refId: 0,
        amounts: _amounts,
        lpTokens: 100*1e12,
        ratio: new uint256[](0),
        minBorrowed: new uint256[](2),
        minCollateral: new uint128[](2),
        deadline: type(uint256).max,
        maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool6x18.getPoolData();
        (uint256 tokenId, uint128[] memory tokensHeld,,) = posMgr.createLoanBorrowAndRebalance(params);
        IGammaPool.LoanData memory loanData = pool6x18.loan(tokenId);

        tokensHeld = loanData.tokensHeld;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = IERC20(address(usdc6)).balanceOf(cfmm6x18);
        ratio[1] = IERC20(address(weth)).balanceOf(cfmm6x18);
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
            cfmm: cfmm6x18,
            tokenId: tokenId,
            deltas: deltas,
            ratio: ratio,
            minCollateral: new uint128[](2),
            deadline: type(uint256).max
            });

            tokensHeld = posMgr.rebalanceCollateral(params);

            IGammaPool.LoanData memory loanData1 = pool6x18.loan(tokenId);
            assertEq(loanData1.tokensHeld[0], tokensHeld[0]);
            assertEq(loanData1.tokensHeld[1], tokensHeld[1]);

            if(ratio.length > 0) {
                assertApproxEqRel(uint256(tokensHeld[1]) * 1e6 / tokensHeld[0], uint256(ratio[1]) * 1e6 / ratio[0], 1e12);
            } else {
                if(deltas[0] > 0) {
                    assertEq(tokensHeld[0],loanData.tokensHeld[0] + uint256(deltas[0]));
                    assertLt(tokensHeld[1],loanData.tokensHeld[1]);
                } else if(deltas[1] > 0) {
                    assertLt(tokensHeld[0],loanData.tokensHeld[0]);
                    assertEq(tokensHeld[1],loanData.tokensHeld[1] + uint256(deltas[1]));
                } else if(deltas[0] < 0) {
                    assertEq(tokensHeld[0],loanData.tokensHeld[0] - uint256(-deltas[0]));
                    if(-deltas[0] < 1e18) {
                        assertGe(tokensHeld[1],loanData.tokensHeld[1]);
                    } else {
                        assertGt(tokensHeld[1],loanData.tokensHeld[1]);
                    }
                } else if(deltas[1] < 0) {
                    if(-deltas[1] < 1e18) {
                        assertGe(tokensHeld[0],loanData.tokensHeld[0]);
                    } else {
                        assertGt(tokensHeld[0],loanData.tokensHeld[0]);
                    }
                    assertEq(tokensHeld[1],loanData.tokensHeld[1] - uint256(-deltas[1]));
                }
            }
        }
    }

    function testRebalanceCollateral6x6(uint96 ratio0, uint96 ratio1, bool useRatio, bool side, bool buy) public {
        lockProtocol();
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), usdcAmount*1e6, wethAmount*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        if(ratio0 < 1e18) ratio0 = 1e18;
        if(ratio1 < 1e18) ratio1 = 1e18;
        if(ratio0 > 1e22) ratio0 = 1e22;
        if(ratio1 > 1e22) ratio1 = 1e22;

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
        _amounts[0] = 10*2000*1e6;
        _amounts[1] = 10*1*1e6;

        vm.startPrank(addr1);

        IPositionManager.CreateLoanBorrowAndRebalanceParams memory params = IPositionManager.CreateLoanBorrowAndRebalanceParams({
            protocolId: 1,
            cfmm: cfmm6x6,
            to: addr1,
            refId: 0,
            amounts: _amounts,
            lpTokens: 100*1e6,
            ratio: new uint256[](0),
            minBorrowed: new uint256[](2),
            minCollateral: new uint128[](2),
            deadline: type(uint256).max,
            maxBorrowed: type(uint256).max
        });

        IGammaPool.PoolData memory poolData = pool6x6.getPoolData();
        (uint256 tokenId, uint128[] memory tokensHeld,,) = posMgr.createLoanBorrowAndRebalance(params);
        IGammaPool.LoanData memory loanData = pool6x6.loan(tokenId);

        tokensHeld = loanData.tokensHeld;

        uint256[] memory ratio = new uint256[](2);
        ratio[0] = IERC20(address(usdc6)).balanceOf(cfmm6x6);
        ratio[1] = IERC20(address(weth6)).balanceOf(cfmm6x6);
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
                cfmm: cfmm6x6,
                tokenId: tokenId,
                deltas: deltas,
                ratio: ratio,
                minCollateral: new uint128[](2),
                deadline: type(uint256).max
            });

            tokensHeld = posMgr.rebalanceCollateral(params);

            if(ratio.length > 0) {
                assertApproxEqAbs(uint256(tokensHeld[1]) * 1e18 / tokensHeld[0], uint256(ratio[1]) * 1e18 / ratio[0], 1e12);
            } else {
                if(deltas[0] > 0) {
                    assertEq(tokensHeld[0],loanData.tokensHeld[0] + uint256(deltas[0]));
                    assertLe(tokensHeld[1],loanData.tokensHeld[1]);
                } else if(deltas[1] > 0) {
                    assertLe(tokensHeld[0],loanData.tokensHeld[0]);
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
