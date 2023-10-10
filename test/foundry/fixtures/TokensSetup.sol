// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../../contracts/test/TestERC20.sol";

contract TokensSetup is Test {

    TestERC20 public weth;
    TestERC20 public usdc;
    TestERC20 public usdt;

    address public addr1;
    address public addr2;

    function initTokens(uint256 amount) public {
        usdc = new TestERC20("USDC", "USDC");
        weth = new TestERC20("Wrapped Ethereum", "WETH");
        usdt = new TestERC20("Tether", "USDT");

        addr1 = vm.addr(5);
        usdc.mint(addr1, amount);
        weth.mint(addr1, amount);
        usdt.mint(addr1, amount);

        addr2 = vm.addr(6);
        usdc.mint(addr2, amount);
        weth.mint(addr2, amount);
        usdt.mint(addr2, amount);
    }
}