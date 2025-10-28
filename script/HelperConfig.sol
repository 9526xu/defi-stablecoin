// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// In your test file or a setup script
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Vm} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] collateralTokens;
        address[] collateralTokenPriceFeeds;
    }

    NetworkConfig internal networkConfig;

    constructor() {
        if (block.chainid == 11_155_111) {
            //  networkConfig = getSepoliaEthConfig();
        } else {
            networkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (networkConfig.collateralTokens.length != 0) {
            return networkConfig;
        }

        vm.startBroadcast();
        // Deploy a mock price feed for WETH
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(8, 200000000000);
        ERC20Mock wethMock = new ERC20Mock();

        // Deploy a mock price feed for WBTC
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(8, 500000000000);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(wethMock);
        collateralTokens[1] = address(wbtcMock);

        address[] memory collateralTokenPriceFeeds = new address[](2);
        collateralTokenPriceFeeds[0] = address(wethPriceFeed);
        collateralTokenPriceFeeds[1] = address(wbtcPriceFeed);

        return NetworkConfig({collateralTokens: collateralTokens, collateralTokenPriceFeeds: collateralTokenPriceFeeds});
    }
}
