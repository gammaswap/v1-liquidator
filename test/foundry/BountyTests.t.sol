// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";

contract BountyTests is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap(false);
    }

    function testCFMMFeeOverflow() public {
        //Step 1: Make the current reserves invariant 1e18 and update the cfmm fee index
        depositLiquidityInCFMM(addr2, 1e18, 1e18);
        depositLiquidityInPool(addr2);
        vm.startPrank(addr2);
        (uint256 accFeeIndex,uint256 lastCFMMFeeIndex,) = pool.getRates();
        assertEq(accFeeIndex, 1e18); // before attack accFeeIndex is 1e18
        assertEq(lastCFMMFeeIndex, 1e18); // before attack accFeeIndex is 1e18
        console.log("The accFeeIndex before the attack is:", accFeeIndex);
        uint256 cfmmSupply = IERC20(cfmm).totalSupply();
        uint256 lastCFMMInvariant = 18446744073709551616; //type(uint64).max + 1
        uint256 prevCFMMInvariant = 1e18;
        lastCFMMFeeIndex = lastCFMMInvariant * cfmmSupply * 1e18 / (prevCFMMInvariant * cfmmSupply);
        assertEq(lastCFMMFeeIndex, 18446744073709551616);
        pool.sync();

        (,lastCFMMInvariant,) = pool.getLatestCFMMBalances();
        assertEq(lastCFMMInvariant,1e18);

        vm.roll(2);
        pool.sync(); //Update lastBlockNumber to the current one so blockDiff == 0

        //Step 2: Make the current reserves invariant type(uint64).max + 1
        //(reserves1 + x) * reserves0 = 18446744073709551616 ** 2; x = 339282366920938463463
        uint256 amountNeeded = uint256((18446744073709551616 ** 2)) / 1e18 - 1e18 + 5; // +5 to cause overflow otherwise it rounds down
        usdc.transfer(cfmm, amountNeeded);
        pool.sync(); //Overflow

        (,lastCFMMInvariant,) = pool.getLatestCFMMBalances();
        assertEq(lastCFMMInvariant,18446744073709551616);// latestCFMMInvariant = type(uint64).max + 1

        (accFeeIndex, lastCFMMFeeIndex,) = pool.getRates();
        assertEq(lastCFMMFeeIndex, 0); // lastCFMMFeeIndex overflowed and was casted to zero
        assertEq(accFeeIndex, 1e18);
        vm.roll(3); //Wait 1 block so the accFeeIndex gets updated
        pool.sync();
        (accFeeIndex, lastCFMMFeeIndex,) = pool.getRates();
        assertEq(lastCFMMFeeIndex, 1e18); // lastCFMMFeeIndex is reset to 1e18
        assertEq(accFeeIndex, 1e18); // accFeeIndex is still equal to 1e18, funds are safe
        console.log("The accFeeIndex after the attack is :", accFeeIndex);
        vm.stopPrank();
    }
}
