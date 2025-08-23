// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

// Aave V2 receiver interface
interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
