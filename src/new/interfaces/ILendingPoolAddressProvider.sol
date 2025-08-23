// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}
