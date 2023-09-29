<p align="center">
    <a href="https://gammaswap.com" target="_blank" rel="noopener noreferrer">
        <img width="100" src="https://app.gammaswap.com/logo.svg" alt="Gammaswap logo">
    </a>
</p>

<p align="center">
  <a href="https://github.com/gammaswap/v1-liquidator/actions/workflows/main.yml">
    <img src="https://github.com/gammaswap/v1-liquidator/actions/workflows/main.yml/badge.svg?branch=main" alt="Compile/Test/Publish">
  </a>
</p>

<h1 align="center">V1-Liquidator</h1>

## Description
This is the repository for the liquidation bot smart contract for the GammaSwap V1 protocol. The tests for the
CPMM implementation of GammaSwap pools that use the UniswapV2 AMM are also found here.

## Steps to Run GammaSwap Tests Locally

1. Run `yarn` to install GammaSwap dependencies
2. Run `yarn test` to run hardhat tests
3. Run `yarn fuzz` to run foundry tests (Need foundry binaries installed locally)
