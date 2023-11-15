// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../../contracts/test/TestERC20.sol";

contract TokensSetup is Test {

    TestERC20 public weth;
    TestERC20 public usdc;
    TestERC20 public usdt;

    TestERC20 public usdc6;
    TestERC20 public weth6;

    address public addr1;
    address public addr2;

    function initTokens(uint256 amount, bool use6decimals) public {
        usdc = new TestERC20("USDC", "USDC",18);
        weth = new TestERC20("Wrapped Ethereum", "WETH", 18);
        usdt = new TestERC20("Tether", "USDT", 18);

        if(use6decimals) {
            weth6 = TestERC20(createToken2("Wrapped Ethereum6", "WETH6",6, address(usdc), true)); // 18x6 = usdc/weth6
            usdc6 = TestERC20(createToken2("USDC6", "USDC6",6, address(weth), false)); // 6x18 = usdc6/weth, 6x6 = weth6/usdc6
        } else {
            weth6 = new TestERC20("Wrapped Ethereum6", "WETH6",6);
            usdc6 = new TestERC20("USDC6", "USDC6",6);
        }

        addr1 = vm.addr(5);
        usdc.mint(addr1, amount);
        weth.mint(addr1, amount);
        usdt.mint(addr1, amount);
        usdc6.mint(addr1, amount);
        weth6.mint(addr1, amount);

        addr2 = vm.addr(6);
        usdc.mint(addr2, amount);
        weth.mint(addr2, amount);
        usdt.mint(addr2, amount);
        usdc6.mint(addr2, amount);
        weth6.mint(addr2, amount);
    }

    function createToken2(string memory name, string memory symbol, uint8 decimals, address prevToken, bool high) private returns(address) {
        address lo = vm.addr(1000);
        uint256 num1 = uint256(type(uint160).max) - 1000;
        address hi = vm.addr(uint160(num1));
        while(true) {
            address tok = address(new TestERC20(name, symbol, decimals));
            if(tok >= lo || tok <= hi) {
                continue;
            }
            if(high) {
                if(tok > prevToken) {
                    return tok;
                }
            } else {
                if(tok < prevToken) {
                    return tok;
                }
            }
        }
        return address(0);
    }

}