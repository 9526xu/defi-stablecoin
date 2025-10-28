// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.sol";
import {XHHStablecoin} from "../src/XHHStablecoin.sol";
import {XHHEngine} from "../src/XHHEngine.sol";

contract Deploy is Script {
    function run() external returns (XHHStablecoin stablecoin, XHHEngine engine, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getOrCreateAnvilEthConfig();

        vm.startBroadcast();
        //  deploy stablecoin
        stablecoin = new XHHStablecoin();

        // deploy engline
        engine =
            new XHHEngine(address(stablecoin), networkConfig.collateralTokens, networkConfig.collateralTokenPriceFeeds);
        // transfer ownership of stablecoin to engine
        stablecoin.transferOwnership(address(engine));
        vm.stopBroadcast();
    }
}
