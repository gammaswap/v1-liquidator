// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/test/strategies/external/TestExternalCallee2.sol";
import "@gammaswap/v1-core/contracts/observer/AbstractCollateralManager.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract VaultLongStrategyTest is CPMMGammaSwapSetup {

    TestCollateralManager collateralManager;

    function setUp() public {
        IS_VAULT = true;
        super.initCPMMGammaSwap(false);
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);

        collateralManager = new TestCollateralManager(address(factory), 1);
        ILoanObserverStore(factory).setLoanObserver(1, address(collateralManager), type(uint16).max, 3, true, true);
        ILoanObserverStore(factory).setPoolObserved(1, address(pool));
        ILoanObserverStore(factory).allowToBeObserved(1, address(owner), true);

        ILoanObserverStore(factory).setLoanObserver(2, address(0), 10, 1, true, false);
        ILoanObserverStore(factory).setPoolObserved(2, address(pool));
    }

    // do the same thing but rebalancing
    function testBorrowReservedLPTokensMultipleLoans() public {
        uint256 lpTokenBalance = IERC20(cfmm).balanceOf(address(pool));
        uint256 lpTokens = 1e18;

        uint256 _tokenId = VaultGammaPool(address(pool)).createLoan(0);

        uint256 tokenId = VaultGammaPool(address(pool)).createLoan(1);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokens, true);

        (uint256 reservedBorrowedInvariant, uint256 reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokens);
        assertEq(reservedBorrowedInvariant,0);
        IVaultPoolViewer.VaultPoolData memory vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData0.poolData.BORROWED_INVARIANT, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BALANCE, lpTokenBalance);
        assertEq(vaultPoolData0.reservedLPTokens, lpTokens);
        assertEq(vaultPoolData0.reservedBorrowedInvariant, 0);

        uint256 liquidityBorrowed0;
        uint256[] memory ratio = new uint256[](2);

        vm.expectRevert(bytes4(keccak256("Margin()")));
        pool.borrowLiquidity(_tokenId, lpTokens, ratio);

        usdc.transfer(address(pool), 1000 * 1e18);
        weth.transfer(address(pool), 1 * 1e18);
        pool.increaseCollateral(_tokenId, new uint256[](0));

        (liquidityBorrowed0,,) = pool.borrowLiquidity(_tokenId, lpTokens, ratio);

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory _loanData0 = viewer.loan(address(pool), _tokenId);
        assertEq(_loanData0.liquidity, liquidityBorrowed0);
        assertGt(_loanData0.tokensHeld[0], 0);
        assertGt(_loanData0.tokensHeld[1], 0);

        vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData0.poolData.BORROWED_INVARIANT, _loanData0.liquidity);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED, lpTokens);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BALANCE, lpTokenBalance - lpTokens);
        assertEq(vaultPoolData0.reservedLPTokens, lpTokens);
        assertEq(vaultPoolData0.reservedBorrowedInvariant, 0);

        liquidityBorrowed0 = lpTokenBalance - lpTokens;
        vm.expectRevert(bytes4(keccak256("ExcessiveBorrowing()")));
        pool.borrowLiquidity(_tokenId, liquidityBorrowed0, new uint256[](0));

        vm.expectRevert(bytes4(keccak256("MaxUtilizationRate()")));
        pool.borrowLiquidity(_tokenId, liquidityBorrowed0 * 9801 / 10000, new uint256[](0));

        // charge rate
        vm.roll(block.number + 1000);

        pool.updatePool(_tokenId);

        IGammaPool.LoanData memory _loanData1 = viewer.loan(address(pool), _tokenId);
        assertGt(_loanData1.liquidity, _loanData0.liquidity);
        assertEq(_loanData1.tokensHeld[0], _loanData1.tokensHeld[0]);
        assertEq(_loanData1.tokensHeld[1], _loanData1.tokensHeld[1]);

        vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData0.poolData.BORROWED_INVARIANT, _loanData1.liquidity);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED, lpTokens);
        assertGt(vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BALANCE, lpTokenBalance - lpTokens);
        assertEq(vaultPoolData0.reservedLPTokens, lpTokens);
        assertEq(vaultPoolData0.reservedBorrowedInvariant, 0);

        {
            (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
            ratio[0] = uint256(reserve0) * 3 / 100000;
            ratio[1] = uint256(reserve1) * 2 / 100000;

            (liquidityBorrowed0,,) = pool.borrowLiquidity(tokenId, lpTokens, ratio);
        }

        IGammaPool.LoanData memory loanData0 = viewer.loan(address(pool), tokenId);
        assertEq(loanData0.liquidity, liquidityBorrowed0);
        assertGt(loanData0.tokensHeld[0], 0);
        assertGt(loanData0.tokensHeld[1], 0);

        IVaultPoolViewer.VaultPoolData memory vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqRel(vaultPoolData1.reservedBorrowedInvariant, _loanData1.liquidity, 5e12);
        assertApproxEqRel(vaultPoolData1.poolData.BORROWED_INVARIANT, loanData0.liquidity + _loanData1.liquidity, 1e12);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens * 2);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens * 2, 3e12);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens * 2, 3e12);
        assertGt(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        liquidityBorrowed0 = _loanData1.liquidity;

        // charge rate
        vm.roll(block.number + 1000);

        pool.updatePool(tokenId);
        pool.updatePool(_tokenId);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, loanData0.liquidity);
        assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        _loanData1 = viewer.loan(address(pool), _tokenId);
        assertGt(_loanData1.liquidity, liquidityBorrowed0);
        assertEq(_loanData1.tokensHeld[0], _loanData0.tokensHeld[0]);
        assertEq(_loanData1.tokensHeld[1], _loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, _loanData0.liquidity);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, loanData1.liquidity + _loanData1.liquidity);
        liquidityBorrowed0 = lpTokens * 2;
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, liquidityBorrowed0);
        assertGt(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, liquidityBorrowed0);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity/2, 1, addr1);

        loanData0 = loanData1;

        loanData1 = viewer.loan(address(pool), tokenId);
        assertApproxEqRel(loanData1.liquidity, loanData0.liquidity/2, 2e15);
        assertEq(loanData1.tokensHeld[0] + 1, loanData0.tokensHeld[0]/2);
        assertEq(loanData1.tokensHeld[1] + 1, loanData0.tokensHeld[1]/2);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqRel(vaultPoolData1.reservedBorrowedInvariant, loanData1.liquidity, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.BORROWED_INVARIANT, loanData1.liquidity + _loanData1.liquidity, 2e15);
        lpTokens = lpTokens + lpTokens / 2;
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens, 2e15);

        _loanData0 = _loanData1;
        liquidityBorrowed0 = _loanData1.liquidity;

        pool.repayLiquidity(_tokenId, _loanData1.liquidity/2, 1, addr1);

        _loanData1 = viewer.loan(address(pool), _tokenId);
        assertApproxEqAbs(_loanData1.liquidity, liquidityBorrowed0/2, 1e16);
        assertEq(_loanData1.tokensHeld[0], _loanData0.tokensHeld[0] / 2);
        assertEq(_loanData1.tokensHeld[1], _loanData0.tokensHeld[1] / 2);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqRel(vaultPoolData1.reservedBorrowedInvariant, loanData1.liquidity, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.BORROWED_INVARIANT, loanData1.liquidity + _loanData1.liquidity, 2e15);
        lpTokens = 1e18;
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens, 2e15);

        _loanData0 = _loanData1;
        loanData0 = loanData1;

        // charge rate
        vm.roll(block.number + 1000);

        pool.updatePool(tokenId);
        pool.updatePool(_tokenId);

        loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, loanData0.liquidity);
        assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        _loanData1 = viewer.loan(address(pool), _tokenId);
        assertGt(_loanData1.liquidity, _loanData0.liquidity);
        assertEq(_loanData1.tokensHeld[0], _loanData0.tokensHeld[0]);
        assertEq(_loanData1.tokensHeld[1], _loanData0.tokensHeld[1]);

        weth.transfer(address(pool), 1e18);
        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity, 2, addr1);

        loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, 0);
        assertEq(loanData1.tokensHeld[0], 0);
        assertEq(loanData1.tokensHeld[1], 0);

        _loanData1 = viewer.loan(address(pool), _tokenId);
        assertApproxEqRel(_loanData1.liquidity, _loanData0.liquidity, 1e14);
        assertGt(_loanData1.liquidity, _loanData0.liquidity);
        assertEq(_loanData1.tokensHeld[0], _loanData0.tokensHeld[0]);
        assertEq(_loanData1.tokensHeld[1], _loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, 0);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, _loanData1.liquidity);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, 5e17);
        lpTokens = (vaultPoolData1.poolData.BORROWED_INVARIANT * vaultPoolData1.poolData.lastCFMMTotalSupply +
            (vaultPoolData1.poolData.lastCFMMInvariant - 1)) / vaultPoolData1.poolData.lastCFMMInvariant;
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        lpTokens = lpTokenBalance - 5e17;
        assertGt(vaultPoolData1.poolData.LP_TOKEN_BALANCE, lpTokens);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, lpTokens, 1e12);
    }

    // do the same thing but rebalancing
    function testBorrowReservedLPTokensRatio() public {
        uint256 lpTokenBalance = IERC20(cfmm).balanceOf(address(pool));
        uint256 lpTokens = 1e18;

        uint256 tokenId = VaultGammaPool(address(pool)).createLoan(1);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokens, true);

        (uint256 reservedBorrowedInvariant, uint256 reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokens);
        assertEq(reservedBorrowedInvariant,0);
        IVaultPoolViewer.VaultPoolData memory vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData0.poolData.BORROWED_INVARIANT, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BALANCE, lpTokenBalance);
        assertEq(vaultPoolData0.reservedLPTokens, lpTokens);
        assertEq(vaultPoolData0.reservedBorrowedInvariant, 0);

        vm.expectRevert(bytes4(keccak256("ExcessiveBorrowing()")));
        pool.borrowLiquidity(tokenId, lpTokenBalance, new uint256[](0));

        vm.expectRevert(bytes4(keccak256("MaxUtilizationRate()")));
        pool.borrowLiquidity(tokenId, lpTokenBalance * 9801 / 10000, new uint256[](0));

        console.log("======cfmm total data start========");
        console.log("cfmmTotalSupply:",vaultPoolData0.poolData.lastCFMMTotalSupply);
        console.log("cfmmTotalInvari:",vaultPoolData0.poolData.lastCFMMInvariant);
        console.log("======cfmm total data end========");

        uint256[] memory ratio = new uint256[](2);
        uint256 liquidityBorrowed;
        {
            (uint128 reserve0, uint128 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
            ratio[0] = uint256(reserve0) * 3 / 100000;
            ratio[1] = uint256(reserve1) * 2 / 100000;

            (liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens, ratio);
        }

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData0 = viewer.loan(address(pool), tokenId);
        assertEq(loanData0.liquidity, liquidityBorrowed);
        assertGt(loanData0.tokensHeld[0], 0);
        assertGt(loanData0.tokensHeld[1], 0);
        {
            uint256 expStrikePx = ratio[1] * (10**18) / ratio[0];
            uint256 strikePx = uint256(loanData0.tokensHeld[1]) * (10**18) / uint256(loanData0.tokensHeld[0]);
            assertApproxEqRel(strikePx, expStrikePx, 1e14);
        }

        IVaultPoolViewer.VaultPoolData memory vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens, 1e12);
        assertLt(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        console.log("======cfmm total data start 1========");
        console.log("cfmmTotalSupply:",vaultPoolData1.poolData.lastCFMMTotalSupply);
        console.log("cfmmTotalInvari:",vaultPoolData1.poolData.lastCFMMInvariant);
        console.log("======cfmm total data end 1========");

        // charge rate
        vm.roll(block.number + 10000);

        pool.updatePool(tokenId);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, liquidityBorrowed);
        assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens);
        console.log("lpTokens:",lpTokens);
        console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertLt(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity/2, 1, addr1);
        console.log("loanData1.liquidity/2:",(loanData1.liquidity/2));

        loanData1 = viewer.loan(address(pool), tokenId);
        console.log("  liquidityBorrowed/2:",(liquidityBorrowed/2));
        assertApproxEqRel(loanData1.liquidity, liquidityBorrowed/2, 2e15);
        //assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        //assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqRel(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed/2, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed/2, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens/2, 2e15);
        //console.log("lpTokens:",lpTokens);
        //console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        //console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens/2, 2e15);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens/2, 2e15);

        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity, 2, addr1);

        loanData1 = viewer.loan(address(pool), tokenId);
        assertApproxEqAbs(loanData1.liquidity, 0, 1e16);
        assertEq(loanData1.tokensHeld[0], 0);
        assertEq(loanData1.tokensHeld[1], 0);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqAbs(vaultPoolData1.reservedBorrowedInvariant, 0, 1e16);
        assertApproxEqAbs(vaultPoolData1.poolData.BORROWED_INVARIANT, 0, 1e16);
        assertApproxEqAbs(vaultPoolData1.poolData.LP_TOKEN_BORROWED, 0, 1e16);
        //console.log("lpTokens:",lpTokens);
        //console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        //console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertApproxEqAbs(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0, 1e16);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE, 1e12);
    }

    function testBorrowReservedLPTokens() public {
        uint256 lpTokenBalance = IERC20(cfmm).balanceOf(address(pool));
        uint256 lpTokens = 1e18;

        uint256 tokenId = VaultGammaPool(address(pool)).createLoan(1);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokens, true);

        (uint256 reservedBorrowedInvariant, uint256 reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokens);
        assertEq(reservedBorrowedInvariant,0);
        IVaultPoolViewer.VaultPoolData memory vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData0.poolData.BORROWED_INVARIANT, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertEq(vaultPoolData0.poolData.LP_TOKEN_BALANCE, lpTokenBalance);
        assertEq(vaultPoolData0.reservedLPTokens, lpTokens);
        assertEq(vaultPoolData0.reservedBorrowedInvariant, 0);

        vm.expectRevert(bytes4(keccak256("ExcessiveBorrowing()")));
        pool.borrowLiquidity(tokenId, lpTokenBalance, new uint256[](0));

        vm.expectRevert(bytes4(keccak256("MaxUtilizationRate()")));
        pool.borrowLiquidity(tokenId, lpTokenBalance * 9801 / 10000, new uint256[](0));

        console.log("======cfmm total data start========");
        console.log("cfmmTotalSupply:",vaultPoolData0.poolData.lastCFMMTotalSupply);
        console.log("cfmmTotalInvari:",vaultPoolData0.poolData.lastCFMMInvariant);
        console.log("======cfmm total data end========");
        (uint256 liquidityBorrowed,,) = pool.borrowLiquidity(tokenId, lpTokens, new uint256[](0));

        IPoolViewer viewer = IPoolViewer(pool.viewer());

        IGammaPool.LoanData memory loanData0 = viewer.loan(address(pool), tokenId);
        assertEq(loanData0.liquidity, liquidityBorrowed);
        assertGt(loanData0.tokensHeld[0], 0);
        assertGt(loanData0.tokensHeld[1], 0);

        IVaultPoolViewer.VaultPoolData memory vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        // charge rate
        vm.roll(block.number + 10000);

        pool.updatePool(tokenId);

        IGammaPool.LoanData memory loanData1 = viewer.loan(address(pool), tokenId);
        assertEq(loanData1.liquidity, liquidityBorrowed);
        assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertEq(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens);
        console.log("lpTokens:",lpTokens);
        console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens);
        assertEq(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens);

        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity/2, 1, addr1);

        loanData1 = viewer.loan(address(pool), tokenId);
        assertApproxEqRel(loanData1.liquidity, liquidityBorrowed/2, 1e12);
        //assertEq(loanData1.tokensHeld[0], loanData0.tokensHeld[0]);
        //assertEq(loanData1.tokensHeld[1], loanData0.tokensHeld[1]);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqRel(vaultPoolData1.reservedBorrowedInvariant, liquidityBorrowed/2, 1e12);
        assertApproxEqRel(vaultPoolData1.poolData.BORROWED_INVARIANT, liquidityBorrowed/2, 1e12);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED, lpTokens/2, 1e12);
        //console.log("lpTokens:",lpTokens);
        //console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        //console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, lpTokens/2, 1e12);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE - lpTokens/2, 1e12);

        //borrow and repay
        pool.repayLiquidity(tokenId, loanData1.liquidity, 2, addr1);

        loanData1 = viewer.loan(address(pool), tokenId);
        assertApproxEqAbs(loanData1.liquidity, 0, 11e3);
        assertEq(loanData1.tokensHeld[0], 0);
        assertEq(loanData1.tokensHeld[1], 0);

        vaultPoolData1 = IVaultPoolViewer(pool.viewer()).getLatestVaultPoolData(address(pool));
        assertEq(vaultPoolData1.reservedLPTokens, 0);
        assertApproxEqAbs(vaultPoolData1.reservedBorrowedInvariant, 0, 11e3);
        assertApproxEqAbs(vaultPoolData1.poolData.BORROWED_INVARIANT, 0, 11e3);
        assertApproxEqAbs(vaultPoolData1.poolData.LP_TOKEN_BORROWED, 0, 11e3);
        //console.log("lpTokens:",lpTokens);
        //console.log("LP_TOKEN_BORROWED:",vaultPoolData1.poolData.LP_TOKEN_BORROWED);
        //console.log("LP_TOKEN_BORROWED_PLUS_INTEREST:",vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertApproxEqAbs(vaultPoolData1.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST, 0, 11e3);
        assertApproxEqRel(vaultPoolData1.poolData.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE, 1e12);
    }

    function testReserveLPTokensFuzz(uint256 lpTokenAmount, uint256 freeLpTokens) public {
        uint256 lpTokenBalance = IERC20(cfmm).balanceOf(address(pool));
        lpTokenAmount = bound(lpTokenAmount, 0, lpTokenBalance * 98 / 100 - 1);
        freeLpTokens = bound(freeLpTokens, 0, lpTokenBalance);

        uint256 tokenId = VaultGammaPool(address(pool)).createLoan(1);

        IVaultPoolViewer.VaultPoolData memory vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getVaultPoolData(address(pool));

        IGammaPool.PoolData memory poolData0 = pool.getPoolData();
        assertEq(poolData0.BORROWED_INVARIANT, 0);
        assertEq(poolData0.LP_TOKEN_BORROWED, 0);
        assertEq(poolData0.LP_TOKEN_BORROWED_PLUS_INTEREST, 0);
        assertGt(poolData0.LP_TOKEN_BALANCE, 0);
        assertGt(poolData0.LP_INVARIANT, 0);
        assertEq(poolData0.LP_TOKEN_BALANCE, lpTokenBalance);

        assertEq(poolData0.BORROWED_INVARIANT, vaultPoolData0.poolData.BORROWED_INVARIANT);
        assertEq(poolData0.LP_TOKEN_BORROWED, vaultPoolData0.poolData.LP_TOKEN_BORROWED);
        assertEq(poolData0.LP_TOKEN_BORROWED_PLUS_INTEREST, vaultPoolData0.poolData.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData0.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE);
        assertEq(poolData0.LP_INVARIANT, vaultPoolData0.poolData.LP_INVARIANT);
        assertEq(poolData0.LP_TOKEN_BALANCE, vaultPoolData0.poolData.LP_TOKEN_BALANCE);

        (uint256 reservedBorrowedInvariant1, uint256 reservedLPTokens1) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens1,0);
        assertEq(reservedBorrowedInvariant1,0);
        assertEq(reservedLPTokens1,vaultPoolData0.reservedLPTokens);
        assertEq(reservedBorrowedInvariant1,vaultPoolData0.reservedBorrowedInvariant);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, true);

        (reservedBorrowedInvariant1, reservedLPTokens1) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens1,lpTokenAmount);
        assertEq(reservedBorrowedInvariant1,0);

        IGammaPool.PoolData memory poolData1 = pool.getPoolData();
        if(lpTokenAmount > 0) {
            assertGt(poolData1.LP_TOKEN_BALANCE, reservedLPTokens1);
        }
        assertEq(poolData1.LP_TOKEN_BALANCE, poolData0.LP_TOKEN_BALANCE);
        assertEq(poolData1.LP_INVARIANT, poolData0.LP_INVARIANT);
        assertEq(poolData1.LP_TOKEN_BORROWED, poolData0.LP_TOKEN_BORROWED);
        assertEq(poolData1.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData0.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData1.BORROWED_INVARIANT, poolData0.BORROWED_INVARIANT);

        vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getVaultPoolData(address(pool));
        assertEq(reservedLPTokens1,vaultPoolData0.reservedLPTokens);
        assertEq(reservedBorrowedInvariant1,vaultPoolData0.reservedBorrowedInvariant);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, freeLpTokens, false);

        (uint256 reservedBorrowedInvariant2, uint256 reservedLPTokens2) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens2,reservedLPTokens1 > freeLpTokens ? reservedLPTokens1 - freeLpTokens : 0);
        assertEq(reservedBorrowedInvariant2,0);

        IGammaPool.PoolData memory poolData2 = pool.getPoolData();
        if(lpTokenAmount > 0) {
            assertGt(poolData2.LP_TOKEN_BALANCE, reservedLPTokens2);
        }
        assertEq(poolData2.LP_TOKEN_BALANCE, poolData0.LP_TOKEN_BALANCE);
        assertEq(poolData2.LP_INVARIANT, poolData0.LP_INVARIANT);
        assertEq(poolData2.LP_TOKEN_BORROWED, poolData0.LP_TOKEN_BORROWED);
        assertEq(poolData2.LP_TOKEN_BORROWED_PLUS_INTEREST, poolData0.LP_TOKEN_BORROWED_PLUS_INTEREST);
        assertEq(poolData2.BORROWED_INVARIANT, poolData0.BORROWED_INVARIANT);

        vaultPoolData0 = IVaultPoolViewer(pool.viewer()).getVaultPoolData(address(pool));
        assertEq(reservedLPTokens2,vaultPoolData0.reservedLPTokens);
        assertEq(reservedBorrowedInvariant2,vaultPoolData0.reservedBorrowedInvariant);
    }

    function testReserveLPTokens() public {
        uint256 lpTokenBalance = IERC20(cfmm).balanceOf(address(pool));
        uint256 lpTokenAmount = 1e18;

        uint256 tokenId = VaultGammaPool(address(pool)).createLoan(2);

        vm.expectRevert(bytes4(keccak256("InvalidRefType()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, true);

        vm.expectRevert(bytes4(keccak256("InvalidRefType()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, false);

        tokenId = VaultGammaPool(address(pool)).createLoan(0);

        vm.expectRevert(bytes4(keccak256("InvalidRefType()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, true);

        vm.expectRevert(bytes4(keccak256("InvalidRefType()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, false);

        tokenId = VaultGammaPool(address(pool)).createLoan(1);

        vm.expectRevert(bytes4(keccak256("ExcessiveLPTokensReserved()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenBalance, true);

        vm.expectRevert(bytes4(keccak256("MaxUtilizationRate()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenBalance * 981 / 1000, true);

        (uint256 reservedBorrowedInvariant, uint256 reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,0);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, false);

        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,0);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, true);

        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, true);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount*2);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount*2, true);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount*4);
        assertEq(reservedBorrowedInvariant,0);

        vm.expectRevert(bytes4(keccak256("MaxUtilizationRate()")));
        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenBalance*98/100, true);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount*3);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount*2, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount/2, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount/2);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount/2, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,0);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount/3, true);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenAmount/3);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenAmount/3 + 1, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,0);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, lpTokenBalance * 98 / 100, true);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,lpTokenBalance * 98 / 100);
        assertEq(reservedBorrowedInvariant,0);

        VaultGammaPool(address(pool)).reserveLPTokens(tokenId, reservedLPTokens, false);
        (reservedBorrowedInvariant, reservedLPTokens) = VaultGammaPool(address(pool)).getReservedBalances();
        assertEq(reservedLPTokens,0);
        assertEq(reservedBorrowedInvariant,0);
    }
}

contract TestCollateralManager is AbstractCollateralManager {

    constructor(address _factory, uint16 _refId) AbstractCollateralManager(_factory, _refId) {
    }

    /// @inheritdoc AbstractLoanObserver
    function _validate(address gammaPool) internal override virtual view returns(bool) {
        return true;
    }

    /// @inheritdoc AbstractLoanObserver
    function _getCollateral(address _gammaPool, uint256 _tokenId) internal override virtual view returns(uint256 collateral) {
        IGammaPool.LoanData memory loanData = IGammaPool(_gammaPool).loan(_tokenId);
        collateral = 2*loanData.liquidity;
    }
        /// @inheritdoc AbstractLoanObserver
    function _onLoanUpdate(address gammaPool, uint256 tokenId, LoanObserved memory loan) internal override virtual {
    }

    /// @inheritdoc AbstractCollateralManager
    function _liquidateCollateral(address gammaPool, uint256 tokenId, uint256 amount, address to) internal override virtual returns(uint256 collateral) {
    }
}

