// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Wrapped Ether (WETH) Interface
/// @notice ERC-20 compliant interface for the canonical WETH token.
/// @dev Extends {IERC20} with deposit and withdraw methods to wrap and unwrap native ETH.
///      Each deposited wei of ETH mints 1 WETH token; each WETH burned withdraws 1 wei of ETH.

interface IWETH is IERC20 {
    /**
     * @notice Deposit native ETH and receive equivalent WETH.
     * @dev Mints WETH 1:1 for the amount of ETH sent with the transaction.
     *      Caller must send ETH along with the call (`msg.value`).
     */
    function deposit() external payable;
    /**
     * @notice Withdraw native ETH by burning WETH.
     * @dev Burns `wad` WETH tokens from the caller and transfers the same amount of ETH back.
     * @param wad The amount of WETH to burn and corresponding ETH to withdraw.
     */
    function withdraw(uint256 wad) external;
}
