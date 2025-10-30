// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHEngine} from "../../src/XHHEngine.sol";
import {XHHStablecoin} from "../../src/XHHStablecoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    XHHEngine public engine;
    XHHStablecoin public stablecoin;

    constructor(XHHEngine _engine, XHHStablecoin _stablecoin) {
        engine = _engine;
        stablecoin = _stablecoin;
    }

    function depositCollateral(uint256 _seed, uint256 _amount) public {
        address collateralToken = getRandomAddress(_seed);

        // _amount should be between 1 and type(uint120).max
        _amount = bound(_amount, 1, type(uint120).max);
        vm.startPrank(msg.sender);
        ERC20Mock(collateralToken).mint(msg.sender, _amount);
        ERC20Mock(collateralToken).approve(address(engine), _amount);
        engine.depositCollateral(collateralToken, _amount);
        vm.stopPrank();
    }

    function getRandomAddress(uint256 _seed) public view returns (address) {
        address[] memory collateralTokens = engine.getCollateralTokens();
        address collateralToken = collateralTokens[_seed % collateralTokens.length];
        return collateralToken;
    }
}
