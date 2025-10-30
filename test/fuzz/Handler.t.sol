// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHEngine} from "../../src/XHHEngine.sol";
import {XHHStablecoin} from "../../src/XHHStablecoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    XHHEngine public engine;
    XHHStablecoin public stablecoin;

    uint256 public mintCount = 0;
    address[] public users;

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

        users.push(msg.sender);
    }

    function redeemCollateral(uint256 _seed, uint256 _amount) public {
        address collateralToken = getRandomAddress(_seed);
        uint256 collateralAmount = engine.getCollateralAmount(msg.sender, collateralToken);

        _amount = bound(_amount, 0, collateralAmount);
        if (_amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        engine.redeemCollateral(collateralToken, _amount);
        vm.stopPrank();
    }

    function mintXHH(uint256 _amount, uint256 _seed) public {
        if (users.length == 0) {
            return;
        }
        address user = users[_seed % users.length];

        (uint256 totalCollateralValue, uint256 totalMintedAmount) = engine.getAccountInformation(user);

        uint256 onlyMaxMintAmount = totalCollateralValue / 2 - totalMintedAmount;

        _amount = bound(_amount, 0, onlyMaxMintAmount);

        if (_amount == 0) {
            return;
        }

        vm.startPrank(user);
        engine.mintXHH(_amount);
        vm.stopPrank();
        mintCount++;
    }

    // function updateCollateralPrice(uint96 _price) public {
    //     address collateralToken = engine.getCollateralTokens()[0];
    //     MockV3Aggregator priceFeed = MockV3Aggregator(engine.getPriceFeed(collateralToken));
    //     priceFeed.updateAnswer(int256(uint256(_price)));
    // }

    // function burnXHH(uint256 _amount) public {
    //     (uint256 totalCollateralValue, uint256 totalMintedAmount) = engine.getAccountInformation(msg.sender);

    //     _amount = bound(_amount, 0, totalMintedAmount);
    //     if (_amount == 0) {
    //         return;
    //     }
    //     vm.startPrank(msg.sender);
    //     engine.burnXHH(_amount);
    //     vm.stopPrank();
    // }

    function getRandomAddress(uint256 _seed) public view returns (address) {
        address[] memory collateralTokens = engine.getCollateralTokens();
        address collateralToken = collateralTokens[_seed % collateralTokens.length];
        return collateralToken;
    }
}
