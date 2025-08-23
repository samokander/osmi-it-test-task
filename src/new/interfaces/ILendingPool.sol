// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

// Aave V2 lending pool minimal interface
interface ILendingPool {
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
