// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHEngine} from "../../src/XHHEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {XHHStablecoin} from "../../src/XHHStablecoin.sol";
import {Test, console, StdInvariant} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    XHHEngine public engine;
    HelperConfig public helperConfig;
    XHHStablecoin public stablecoin;

    function setUp() public {
        Deploy deploy = new Deploy();
        (stablecoin, engine, helperConfig) = deploy.run();
        Handler handler = new Handler(engine, stablecoin);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = stablecoin.totalSupply();
        address[] memory collateralTokens = helperConfig.getNetworkConfig().collateralTokens;
        uint256 wethAmount = ERC20Mock(collateralTokens[0]).balanceOf(address(engine));
        uint256 wbthAmount = ERC20Mock(collateralTokens[1]).balanceOf(address(engine));

        uint256 totalValue = 0;
        totalValue += engine.getUSDValue(address(collateralTokens[0]), wethAmount);
        totalValue += engine.getUSDValue(address(collateralTokens[1]), wbthAmount);

        console.log("totalValue:", totalValue);
        console.log("totalSupply:", totalSupply);

        assert(totalValue >= totalSupply);
    }
}
