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
}
