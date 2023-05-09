// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/Math.sol";
import "./interfaces/ILiquidator.sol";

/// @title Liquidator Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Helps liquidation of loans in GammaPools
contract Liquidator is ILiquidator {

    constructor(){
    }

    /// @dev See {ILiquidator-canLiquidate}.
    function canLiquidate(address pool, uint256 tokenId) external override view returns(uint256 liquidity, uint256 collateral) {
        return _canLiquidate(pool, tokenId);
    }

    function _canLiquidate(address pool, uint256 tokenId) internal virtual view returns(uint256 liquidity, uint256 collateral) {
        if(IGammaPool(pool).canLiquidate(tokenId)) {
            IGammaPool.LoanData memory loan = IGammaPool(pool).loan(tokenId);
            liquidity = loan.liquidity;
            collateral = Math.sqrt(uint256(loan.tokensHeld[0])*loan.tokensHeld[1]);
        }
    }

    /// @dev See {ILiquidator-canBatchLiquidate}.
    function canBatchLiquidate(address pool, uint256[] calldata tokenIds) external override virtual view returns(uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) {
        return _canBatchLiquidate(pool, tokenIds);
    }

    function _canBatchLiquidate(address pool, uint256[] calldata tokenIds) internal virtual view returns(uint256[] memory _tokenIds, uint256 _liquidity, uint256 _collateral) {
        IGammaPool.LoanData[] memory _loans = IGammaPool(pool).getLoansById(tokenIds, true);
        uint256[] memory __tokenIds = new uint256[](_loans.length);
        uint256 k = 0;
        IGammaPool.LoanData memory _loan;
        for(uint256 i = 0; i < _loans.length;) {
            _loan = _loans[i];
            if(_loan.id > 0) {
                if(_loan.canLiquidate) {
                    __tokenIds[k] = _loan.tokenId;
                    _liquidity += _loan.liquidity;
                    _collateral += Math.sqrt(uint256(_loan.tokensHeld[0]) * _loan.tokensHeld[1]);
                    unchecked {
                        k++;
                    }
                }
            } else {
                break;
            }
            unchecked {
                i++;
            }
        }
        _tokenIds = new uint256[](k);
        for(uint256 j = 0; j < _tokenIds.length;) {
            _tokenIds[j] = __tokenIds[j];
            unchecked {
                j++;
            }
        }
    }

    /// @dev See {ILiquidator-liquidate}.
    function liquidate(address pool, uint256 tokenId, uint256 collateralId, uint256[] calldata fees) external override virtual returns(uint256[] memory refunds) {
        if(IGammaPool(pool).canLiquidate(tokenId)) {
            uint256 writedownAmt = _calcWritedown(pool, tokenId);
            IGammaPool.LoanData memory _loan = IGammaPool(pool).loan(tokenId);
            int256[] memory deltas = IGammaPool(pool).calcDeltasToClose(_loan.tokensHeld, IGammaPool(pool).getLatestCFMMReserves(),
                _loan.liquidity - writedownAmt, collateralId);
            (,refunds) = IGammaPool(pool).liquidate(tokenId, deltas, fees);
            _transferRefunds(pool, refunds, msg.sender);
        }
    }

    /// @dev See {ILiquidator-calcLPTokenDebt}.
    function calcLPTokenDebt(address pool, uint256 tokenId) external override virtual view returns(uint256 lpTokens) {
        return _calcLPTokenDebt(pool, tokenId);
    }

    function _calcLPTokenDebt(address pool, uint256 tokenId) internal virtual view returns(uint256 lpTokens) {
        IGammaPool.LoanData memory _loan = IGammaPool(pool).loan(tokenId);
        lpTokens = _convertLiquidityToLPTokens(pool, _loan.liquidity);
    }

    /// @dev See {ILiquidator-liquidateWithLP}.
    function liquidateWithLP(address pool, uint256 tokenId, uint256 lpTokens, bool calcLpTokens) external override virtual returns(uint256[] memory refunds) {
        //check can liquidate first
        if(IGammaPool(pool).canLiquidate(tokenId)){
            if(calcLpTokens) {
                lpTokens = _calcLPTokenDebt(pool, tokenId) * 1001 / 1000; // adding 0.1% to avoid rounding issues
            }
            // transfer CFMM LP Tokens
            _transferLPTokens(pool, lpTokens);
            (,refunds) = IGammaPool(pool).liquidateWithLP(tokenId);
            _transferRefunds(pool, refunds, msg.sender);
        }
    }

    /// @dev See {ILiquidator-batchLiquidate}.
    function batchLiquidate(address pool, uint256[] calldata tokenIds) external override virtual returns(uint256[] memory _tokenIds, uint256[] memory refunds) {
        //call canLiquidate first
        uint256 _liquidity;
        (_tokenIds, _liquidity,) = _canBatchLiquidate(pool, tokenIds);
        if(_liquidity > 0) {
            uint256 lpTokens = _convertLiquidityToLPTokens(pool, _liquidity) * 1001 / 1000;
            // transfer CFMM LP Tokens
            _transferLPTokens(pool, lpTokens);
            (,,refunds) = IGammaPool(pool).batchLiquidations(_tokenIds);
            _transferRefunds(pool, refunds, msg.sender);
        }
    }

    /// @dev See {ILiquidator-getLoan}.
    function getLoan(address pool, uint256 tokenId) external override virtual view returns(IGammaPool.LoanData memory loan) {
        loan = IGammaPool(pool).loan(tokenId);
    }

    /// @dev See {ILiquidator-getLoans}.
    function getLoans(address pool, uint256[] calldata tokenId, bool active) external override virtual view returns(IGammaPool.LoanData[] memory loans) {
        loans = IGammaPool(pool).getLoansById(tokenId, active);
    }

    /// @dev See {ILiquidator-getOpenLoans}.
    function getLoans(address pool, uint256 start, uint256 end, bool active) external override virtual view returns(IGammaPool.LoanData[] memory loans) {
        loans = IGammaPool(pool).getLoans(start, end, active);
    }

    /// @dev See {ILiquidator-getOpenLoanIds}.
    function getLoanIds(address pool, uint256 start, uint256 end, bool active) external override virtual view returns(uint256[] memory tokenIds) {
        IGammaPool.LoanData[] memory loans = IGammaPool(pool).getLoans(start, end, active);
        tokenIds = new uint256[](loans.length);
        for(uint256 i = 0; i < loans.length;) {
            tokenIds[i] = loans[i].tokenId;
            unchecked {
                i++;
            }
        }
    }

    /// @dev convert liquidity invariant units to LP tokens
    /// @param pool - address of GammaPool for CFMM's liquidity
    /// @param liquidity - liquidity invariant units to convert into CFMM LP tokens
    /// @return lpTokens - CFMM LP tokens `liquidity` invariant units converts to
    function _convertLiquidityToLPTokens(address pool, uint256 liquidity) internal virtual view returns(uint256 lpTokens) {
        (, uint256 cfmmInvariant, uint256 cfmmTotalSupply) = IGammaPool(pool).getLatestCFMMBalances();
        lpTokens = liquidity * cfmmTotalSupply / cfmmInvariant;
    }

    /// @dev transfer refunded amounts to `to` address
    /// @param pool - refunded quantities of CFMM tokens
    /// @param refunds - refunded quantities of CFMM tokens
    /// @param to - address that will receive refunded quantities
    function _transferRefunds(address pool, uint256[] memory refunds, address to) internal virtual {
        address[] memory tokens = IGammaPool(pool).tokens();
        for(uint256 i = 0; i < refunds.length;) {
            IERC20(tokens[i]).transfer(to, refunds[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @dev transfer refunded amounts to `to` address
    /// @param pool - address of GammaPool that will receive the LP tokens
    /// @param lpTokens - CFMM LP token amounts refunded
    function _transferLPTokens(address pool, uint256 lpTokens) internal virtual {
        IERC20(IGammaPool(pool).cfmm()).transferFrom(msg.sender,pool,lpTokens);
    }

    function _calcWritedown(address pool, uint256 tokenId) internal virtual returns (uint256) {
        address liquidationStrategy = IGammaPool(pool).liquidationStrategy();
        (bool success, bytes memory data) = liquidationStrategy.staticcall(abi.encodeWithSignature("LIQUIDATION_FEE()"));
        if (success && data.length > 0) {
            uint16 liquidationFee = abi.decode(data, (uint16));
            (uint256 debt, uint256 collateral) = _canLiquidate(pool, tokenId);
            collateral = collateral * (1e4 - liquidationFee) / 1e4;

            return collateral >= debt ? 0 : debt - collateral;
        }

        return 0;
    }
}
