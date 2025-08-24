// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

/// @title Aave V2 Flash Loan Receiver Interface
/// @notice Interface for contracts that receive Aave V2 flash loans and must implement the callback.
/// @dev The LendingPool calls {executeOperation} after transferring the borrowed assets to the receiver.
/// Implementations MUST ensure:
/// - The caller is the expected Aave LendingPool.
/// - Principal + `premiums[i]` are available and approved back to the pool by the end of the call.
interface IFlashLoanReceiver {
    /**
     * @notice Aave callback invoked after a flash loan is issued to this contract.
     * @dev The receiver should perform its logic (e.g., swaps/arbitrage/liquidations), then approve
     *      the LendingPool to pull each `amounts[i] + premiums[i]` for `assets[i]`.
     *      Implementations should validate the caller (LendingPool) and handle reentrancy as needed.
     * @param assets The list of borrowed asset addresses.
     * @param amounts The amounts borrowed for each corresponding asset in `assets`.
     * @param premiums The fee amounts owed for each borrowed asset.
     * @param initiator The address that initiated the flash loan on the LendingPool.
     * @param params Arbitrary data passed through by the initiator, ABI-encoded for the receiver.
     * @return success Must return true if the operation completed and repayment approval was set.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
