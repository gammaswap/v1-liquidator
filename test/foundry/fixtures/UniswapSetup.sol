// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapFactory.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapRouter02.sol";

contract UniswapSetup is Test {

    IDeltaSwapFactory public uniFactory;
    IDeltaSwapRouter02 public uniRouter;
    IDeltaSwapPair public uniPair;

    bytes32 public cfmmHash;
    address public cfmmFactory;

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

        uniFactory = IDeltaSwapFactory(factoryAddress);
        uniRouter = IDeltaSwapRouter02(routerAddress);

        cfmmHash = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'; // UniV2Pair init_code_hash
        cfmmFactory = address(0);
    }

    function initDeltaSwap(address owner, address weth, address gsFactory) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);
        bytes memory factoryArgs = abi.encode(owner, owner, gsFactory);
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/DeltaSwapFactory.json"), factoryArgs);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factoryAddress, weth);
        bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/DeltaSwapRouter02.json"), routerArgs);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }

        uniFactory = IDeltaSwapFactory(factoryAddress);
        uniRouter = IDeltaSwapRouter02(routerAddress);
        uniFactory.setGSProtocolId(1);

        cfmmHash = hex'a82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658'; // DeltaSwapPair init_code_hash
        cfmmFactory = address(uniFactory);
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
