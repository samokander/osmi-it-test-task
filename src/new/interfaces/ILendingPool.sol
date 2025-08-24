// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

/// @title Aave V2 LendingPool (minimal)
/// @notice Initiates flash loans of one or more reserve assets.
/// @dev This minimal interface exposes only {flashLoan}. When called, the pool transfers the requested
///      assets to `receiverAddress` and then invokes `IFlashLoanReceiver.executeOperation` on it.
///      All array parameters MUST have the same length. For pure flash loans, set each `modes[i]` to 0.
interface ILendingPool {
    /**
     * @notice Request a flash loan (or open debt, depending on `modes`) from the LendingPool.
     * @dev For a classic flash loan, use a single asset and pass `modes[0] = 0`. The pool will:
     *      1) Transfer `amounts[i]` of each `assets[i]` to `receiverAddress`,
     *      2) Call `IFlashLoanReceiver.executeOperation(...)` on the receiver,
     *      3) Expect the receiver to have approved back `amounts[i] + premium[i]` before returning.
     * @param receiverAddress The contract that receives the funds and implements `IFlashLoanReceiver`.
     * @param assets The list of reserve asset addresses to borrow.
     * @param amounts The amounts to borrow for each asset in `assets`.
     * @param modes Borrowing modes per asset: 0 = no debt (flash loan), 1 = stable debt, 2 = variable debt.
     * @param onBehalfOf If `modes[i] != 0`, the address that will incur the debt; ignored when `modes[i] == 0`.
     * @param params ABI‑encoded data forwarded to the receiver’s `executeOperation` call.
     * @param referralCode Integrator code for potential fee discounts or accounting; use 0 if none.
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}
