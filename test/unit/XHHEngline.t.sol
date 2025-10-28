// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {XHHStablecoin} from "../../src/XHHStablecoin.sol";
import {XHHEngine} from "../../src/XHHEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract XHHEngineTest is Test {
    XHHStablecoin stablecoin;
    XHHEngine engine;
    HelperConfig helperConfig;

    address alice;

    function setUp() public {
        Deploy deploy = new Deploy();
        (stablecoin, engine, helperConfig) = deploy.run();

        alice = makeAddr("alice");
    }

    function test_depositCollateralIsZeroTokenAddress() public {
        address tokenAddr = address(0);
        uint256 amount = 100;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.depositCollateral(tokenAddr, amount);
    }

    function test_depositCollateralIsZeroAmount() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 0;
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.depositCollateral(tokenAddr, amount);
    }

    // check token  allowance
    function test_depositCollateralIsInsufficientAllowance() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;

        ERC20Mock(tokenAddr).mint(alice, amount + 10);
        console.log("alice balance: ", ERC20Mock(tokenAddr).balanceOf(alice));
        console.log("alice allowance: ", ERC20Mock(tokenAddr).allowance(alice, address(engine)));

        vm.expectRevert(XHHEngine.XHHEngine_InsufficientAllowance.selector);
        vm.prank(alice);
        engine.depositCollateral(tokenAddr, amount);
    }

    function test_depositCollateralIsSuccess() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;

        ERC20Mock(tokenAddr).mint(alice, amount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), amount);

        uint256 initialAliceBalance = ERC20Mock(tokenAddr).balanceOf(alice);

        console.log("alice balance: ", ERC20Mock(tokenAddr).balanceOf(alice));
        console.log("alice allowance: ", ERC20Mock(tokenAddr).allowance(alice, address(engine)));

        //  emit event
        vm.expectEmit(true, true, true, true);
        emit XHHEngine.XHHEngine_CollateralDeposited(alice, tokenAddr, amount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, amount);

        console.log("alice collateral amount: ", engine.getCollateralAmount(alice, tokenAddr));
        assertEq(engine.getCollateralAmount(alice, tokenAddr), amount);
        assertEq(ERC20Mock(tokenAddr).balanceOf(alice), initialAliceBalance - amount);
        assertEq(ERC20Mock(tokenAddr).balanceOf(address(engine)), amount);
    }

    function test_depositCollateralWhenTransferFailed() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;

        ERC20Mock(tokenAddr).mint(alice, amount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), amount);

        console.log("alice balance: ", ERC20Mock(tokenAddr).balanceOf(alice));
        console.log("alice allowance: ", ERC20Mock(tokenAddr).allowance(alice, address(engine)));

        vm.expectRevert(XHHEngine.XHHEngine_TransferFailed.selector);
        // mock transferFrom failed
        vm.mockCall(
            tokenAddr,
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(engine), amount),
            abi.encode(false)
        );

        //  mock transfer failed
        vm.prank(alice);
        engine.depositCollateral(tokenAddr, amount);
    }
}
