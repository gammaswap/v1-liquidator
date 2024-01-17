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
    TestERC20 public weth8;

    address public addr1;
    address public addr2;

    function initTokens(uint256 amount, bool use6decimals) public {
        usdc = new TestERC20("USDC", "USDC");
        weth = new TestERC20("Wrapped Ethereum", "WETH");
        usdt = new TestERC20("Tether", "USDT");
        weth6 = new TestERC20("Wrapped Ethereum6", "WETH6");
        usdc6 = new TestERC20("USDC6", "USDC6");
        weth8 = new TestERC20("Wrapped Ethereum8", "WETH8");

        if(use6decimals) {
            address[] memory tokens = new address[](6);
            tokens[0] = address(usdc);
            tokens[1] = address(weth);
            tokens[2] = address(usdt);
            tokens[3] = address(weth6);
            tokens[4] = address(usdc6);
            tokens[5] = address(weth8);
            tokens = quickSort(tokens);

            // 18x18 = weth/usdc
            // 18x6 = weth/usdc6
            // 6x18 = weth6/usdc
            // 6x6 = weth6/usdc6
            // 8x6 = weth8/usdc6
            // 8x18 = weth8/usdc

            // usdc6 < weth < usdc < weth6 < weth8
            usdc6 = TestERC20(tokens[0]);
            weth = TestERC20(tokens[1]);
            usdc = TestERC20(tokens[2]);
            weth6 = TestERC20(tokens[3]);
            usdt = TestERC20(tokens[4]);
            weth8 = TestERC20(tokens[5]);
            weth.setMetaData("Wrapped Ethereum", "WETH", 18);
            weth6.setMetaData("Wrapped Ethereum6", "WETH6", 6);
            weth8.setMetaData("Wrapped Ethereum8", "WETH8", 8);
            usdc6.setMetaData("USDC6", "USDC6", 6);
            usdt.setMetaData("USDT", "USDT", 18);
            usdc.setMetaData("USDC", "USDC", 18);
        }

        addr1 = vm.addr(5);
        usdc.mint(addr1, amount);
        weth.mint(addr1, amount);
        usdt.mint(addr1, amount);
        weth6.mint(addr1, amount);
        usdc6.mint(addr1, amount);
        weth8.mint(addr1, amount);

        addr2 = vm.addr(6);
        usdc.mint(addr2, amount);
        weth.mint(addr2, amount);
        usdt.mint(addr2, amount);
        weth6.mint(addr2, amount);
        usdc6.mint(addr2, amount);
        weth8.mint(addr2, amount);
    }

    function sort(address[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if(i == j) return;
        address pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            sort(arr, left, j);
        if (i < right)
            sort(arr, i, right);
    }

    // Helper function to start the sorting
    function quickSort(address[] memory arr) public pure returns (address[] memory) {
        sort(arr, 0, int(arr.length - 1));
        return arr;
    }
}