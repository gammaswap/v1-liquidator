// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract UniswapSetup is Test {

    IUniswapV2Factory public uniFactory;
    IUniswapV2Router02 public uniRouter;
    IUniswapV2Pair public uniPair;

    function initUniswap(address owner, address weth) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);
        bytes memory factoryArgs = abi.encode(owner);
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/UniswapV2Factory.json"), factoryArgs);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factoryAddress, weth);
        bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/UniswapV2Router02.json"), routerArgs);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }

        uniFactory = IUniswapV2Factory(factoryAddress);
        uniRouter = IUniswapV2Router02(routerAddress);
    }

    function createPair(address token0, address token1) public returns(address) {
        return uniFactory.createPair(token0, token1);
    }

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1, address to) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB, liquidity) = uniRouter.addLiquidity(token0, token1, amount0, amount1, 0, 0, to, type(uint256).max);
    }

    function removeLiquidity(address token0, address token1, uint liquidity) external returns (uint256 amount0, uint256 amount1) {
        return uniRouter.removeLiquidity(token0, token1, liquidity, 0, 0, msg.sender, type(uint256).max);
    }

    function buyTokenOut(uint256 amountOut, address tokenIn, address tokenOut) public returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return uniRouter.swapTokensForExactTokens(amountOut, type(uint256).max, path, msg.sender, type(uint256).max);
    }

    function sellTokenIn(uint256 amountIn, address tokenIn, address tokenOut, address to) public returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return uniRouter.swapExactTokensForTokens(amountIn, 0, path, to, type(uint256).max);
    }
}
