// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

/// @title Aave V2 LendingPool Addresses Provider (minimal)
/// @notice Provides access to the current LendingPool address for the protocol.
/// @dev Acts as a registry; the LendingPool address may change when Aave upgrades
///      its core contracts. Always resolve the latest pool via {getLendingPool}
///      before interacting with flash loans or other LendingPool functionality.
interface ILendingPoolAddressesProvider {
    /**
     * @notice Returns the current LendingPool implementation address.
     * @dev This value can change over time as Aave governance upgrades the pool.
     *      Contracts should query this provider each time before initiating flash loans.
     * @return The address of the active LendingPool contract.
     */
    function getLendingPool() external view returns (address);
}
