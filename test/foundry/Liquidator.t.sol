// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./fixtures/CPMMGammaSwapSetup.sol";

contract LiquidatorTest is CPMMGammaSwapSetup {

    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(addr1, 2*1e24, 2*1e21);
        depositLiquidityInCFMM(addr2, 2*1e24, 2*1e21);
        depositLiquidityInPool(addr2);
    }

}
