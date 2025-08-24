// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {FlashArbMainnetReady} from "../src/new/FlashArbMainnetReady.sol";

contract Deploy is Script {
    function run() external {
        // PRIVATE_KEY берём из .env
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        FlashArbMainnetReady arb = new FlashArbMainnetReady();
        vm.stopBroadcast();

        console2.log("Deployer:", deployer);
        console2.log("FlashArbMainnetReady:", address(arb));

        // sanity-чеки
        console2.log("Aave provider:", address(arb.provider()));
        console2.log("LendingPool:", arb.lendingPool());
        console2.log("UNISWAP whitelisted:", arb.routerWhitelist(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
        console2.log("SUSHI whitelisted:", arb.routerWhitelist(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F));
    }
}
