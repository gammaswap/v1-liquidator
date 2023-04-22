// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "./interfaces/ILiquidator.sol";

/// @title Liquidator Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Helps liquidation of loans in GammaPools
contract Liquidator is ILiquidator {

    constructor(){
    }

    /// @dev See {ILiquidator-canLiquidate}.
    function canLiquidate(address pool, uint256 tokenId) external override virtual view returns(uint256 liquidity, uint256 collateral) {

    }

    /// @dev See {ILiquidator-canLiquidate}.
    function canLiquidate(address pool, uint256[] calldata tokenIds) external override virtual view returns(uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) {

    }

    /// @dev See {ILiquidator-liquidate}.
    function liquidate(address pool, uint256 tokenId) external override virtual returns(uint256[] memory refunds) {

    }

    /// @dev See {ILiquidator-liquidateWithLP}.
    function liquidateWithLP(address pool, uint256 tokenId) external override virtual returns(uint256[] memory refunds) {

    }

    /// @dev See {ILiquidator-batchLiquidate}.
    function batchLiquidate(address pool, uint256[] calldata tokenIds) external override virtual returns(uint256[] memory _tokenIds, uint256[] memory refunds) {

    }

    /// @dev See {ILiquidator-getLoan}.
    function getLoan(address pool, uint256 tokenId) external override virtual view returns(IGammaPool.LoanData memory loan) {

    }

    /// @dev See {ILiquidator-getLoans}.
    function getLoans(address pool, uint256[] calldata tokenId, bool active) external override virtual view returns(IGammaPool.LoanData[] memory loans) {

    }

    /// @dev See {ILiquidator-getOpenLoans}.
    function getLoans(address pool, uint256 start, uint256 end, bool active) external override virtual view returns(IGammaPool.LoanData[] memory loans) {

    }

    /// @dev See {ILiquidator-getOpenLoanIds}.
    function getLoanIds(address pool, uint256 start, uint256 end, bool active) external override virtual view returns(uint256[] memory tokenIds) {

    }
}
