// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.8.0;

import "@gammaswap/v1-core/contracts/interfaces/IGammaPool.sol";

/// @title Interface for Liquidator contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Helps liquidation of loans in GammaPools
interface ILiquidator {
    /// @dev Initialized to address(0)
    /// @dev When set to address(0) anyone can call liquidation functions
    /// @return Address that is allowed to call liquidation functions
    function liquidator() external view returns(address);

    /// @dev Calculate liquidity debt as CFMM LP Tokens
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @return lpTokens - liquidity debt of loan as CFMM LP Tokens
    function calcLPTokenDebt(address pool, uint256 tokenId) external view returns(uint256 lpTokens);

    /// @dev Check if loan in `pool` identified by `tokenId` can be liquidated
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @return liquidity - liquidity debt of loan (not written down), if it can be liquidated. Otherwise it returns 0
    /// @return collateral - liquidity collateral backing loan, if it can be liquidated. Otherwise it returns 0
    function canLiquidate(address pool, uint256 tokenId) external view returns(uint256 liquidity, uint256 collateral);

    /// @dev Check if loans in `pool` identified by `tokenIds` can be liquidated
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenIds - list of tokenIds of loans in GammaPool (`pool`) to check
    /// @return _tokenIds - list of tokenIds of loans that can be liquidated. The array may be larger
    /// @return _liquidity - summed liquidity debt of loans (not written down) that can be liquidated. If a loan can't be liquidate it is not summed
    /// @return _collateral - liquidity collateral backing loan that can be liquidated. If a loan can't be liquidate it is not summed
    function canBatchLiquidate(address pool, uint256[] calldata tokenIds) external view returns(uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral);

    /// @dev Liquidate loan in `pool` identified by `tokenId` using the loan's own collateral tokens
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @param to - receiver of liquidation fee
    /// @return refund - CFMM LP tokens that are refunded to liquidator
    function liquidate(address pool, uint256 tokenId, address to) external returns(uint256 refund);

    /// @dev Liquidate loan in `pool` identified by `tokenId` using CFMM LP tokens of the CFMM liquidity was borrowed from
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @param lpTokens - CFMM LP tokens to transfer to liquidate
    /// @param calcLpTokens - if true calculate how many CFMM LP Tokens to liquidate
    /// @param to - receiver of liquidation fee
    /// @return refunds - collateral tokens that are refunded to liquidator
    function liquidateWithLP(address pool, uint256 tokenId, uint256 lpTokens, bool calcLpTokens, address to) external returns(uint256[] memory refunds);

    /// @dev Liquidate loan in `pool` identified by `tokenId` using the loan's own collateral tokens
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @param to - receiver of liquidation fee
    /// @return _tokenIds - list of tokenIds of loans that were liquidated
    /// @return refunds - collateral tokens that are refunded to liquidator from all loans that were liquidated
    function batchLiquidate(address pool, uint256[] calldata tokenId, address to) external returns(uint256[] memory _tokenIds, uint256[] memory refunds);

    /// @dev Get most updated loan information for a loan identified by `tokenId` in `pool`
    /// @param pool - address of GammaPool loan belongs to
    /// @param tokenId - tokenId of loan in GammaPool (`pool`) to check
    /// @return loan - struct containing most up to date loan information and other data to identify loan
    function getLoan(address pool, uint256 tokenId) external view returns(IGammaPool.LoanData memory loan);

    /// @dev Get most updated loan information for list of loans in GammaPool
    /// @param pool - address of GammaPool loans belong to
    /// @param tokenIds - list of tokenIds of loans in GammaPool (`pool`) to get information for
    /// @param active - filter to select only loans with outstanding liquidity debts (if true, ignore loans with 0 liquidity debts)
    /// @return loans - struct containing most up to date loan information and other data to identify loan
    function getLoans(address pool, uint256[] calldata tokenIds, bool active) external view returns(IGammaPool.LoanData[] memory loans);

    /// @dev Get most updated loan information for loans opened in GammaPool from index `start` to `end`
    /// @notice All loans in GammaPool are opened in ascending order. The first loan has index 1, the next is 2, ...
    /// @param pool - address of GammaPool loans belong to
    /// @param start - beginning index to query for loans in GammaPool
    /// @param end - last index to query for loans in GammaPool
    /// @param active - filter to select only loans with outstanding liquidity debts (if true, ignore loans with 0 liquidity debts)
    /// @return loans - struct containing most up to date loan information and other data to identify loan
    function getLoans(address pool, uint256 start, uint256 end, bool active) external view returns(IGammaPool.LoanData[] memory loans);

    /// @dev Get tokenIds of loans opened in GammaPool from index `start` to `end`
    /// @notice All loans in GammaPool are opened in ascending order. The first loan has index 1, the next is 2, ...
    /// @param pool - address of GammaPool loans belong to
    /// @param start - beginning index to query for loans in GammaPool
    /// @param end - last index to query for loans in GammaPool
    /// @param active - filter to select only loans with outstanding liquidity debts (if true, ignore loans with 0 liquidity debts)
    /// @return tokenIds - list of tokenIds of loans found in query
    function getLoanIds(address pool, uint256 start, uint256 end, bool active) external view returns(uint256[] memory tokenIds);
}
