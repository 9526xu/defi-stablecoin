// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {XHHStablecoin} from "../../src/XHHStablecoin.sol";
import {XHHEngine} from "../../src/XHHEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    function test_mintXHHIsSuccess() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;

        ERC20Mock(tokenAddr).mint(alice, amount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), amount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, amount);

        uint256 mintAmount = 10;
        vm.prank(alice);
        engine.mintXHH(mintAmount);

        assertEq(engine.getMintAmount(alice), mintAmount);
    }

    function test_mintXHHWhenAmountIs0() public {
        uint256 mintAmount = 0;
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        vm.prank(alice);
        engine.mintXHH(mintAmount);
    }

    function test_mintXHHWhenUserUnhealthy() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 10;

        ERC20Mock(tokenAddr).mint(alice, amount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), amount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, amount);

        //  get price of weth
        (, int256 price,,,) = engine.getPriceFeed(tokenAddr).latestRoundData();

        uint256 mintAmount = (amount * (uint256(price) * engine.getPrecisionUnit())) / engine.getPrecisionUnit() + 1;
        console.log("mintAmount: ", mintAmount);

        vm.expectRevert(XHHEngine.XHHEngine_UserUnhealthy.selector);
        vm.prank(alice);
        engine.mintXHH(mintAmount);
    }

    function test_depositCollateralAndMintXHHIsSuccess() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;
        uint256 mintAmount = 10;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateralAndMintXHH(tokenAddr, collateralAmount, mintAmount);

        assertEq(engine.getCollateralAmount(alice, tokenAddr), collateralAmount);
        assertEq(engine.getMintAmount(alice), mintAmount);
    }

    function test_redeemCollateralIsSuccess() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, collateralAmount);

        uint256 redeemAmount = 50;
        vm.prank(alice);
        engine.redeemCollateral(tokenAddr, redeemAmount);

        assertEq(engine.getCollateralAmount(alice, tokenAddr), collateralAmount - redeemAmount);
    }

    function test_redeemCollateralWhenInsufficientBalance() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, collateralAmount);

        uint256 redeemAmount = 150;
        vm.prank(alice);
        vm.expectRevert(XHHEngine.XHHEngine_InsufficientBalance.selector);
        engine.redeemCollateral(tokenAddr, redeemAmount);
    }

    function test_redeemCollateralWhenAmountIs0() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 redeemAmount = 0;
        vm.prank(alice);
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.redeemCollateral(tokenAddr, redeemAmount);
    }

    function test_redeemCollateralWhenTokenAddrIs0() public {
        address tokenAddr = address(0);
        uint256 redeemAmount = 100;
        vm.prank(alice);
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.redeemCollateral(tokenAddr, redeemAmount);
    }

    function test_redeemCollateralWhenTransferFailed() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, collateralAmount);

        uint256 redeemAmount = 50;
        vm.mockCall(tokenAddr, abi.encodeWithSelector(IERC20.transfer.selector, alice, redeemAmount), abi.encode(false));

        vm.prank(alice);
        vm.expectRevert(XHHEngine.XHHEngine_TransferFailed.selector);
        engine.redeemCollateral(tokenAddr, redeemAmount);
    }

    function test_burnXHHIsSuccess() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;
        uint256 mintAmount = 10;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        // approve engine to spend alice's token
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateralAndMintXHH(tokenAddr, collateralAmount, mintAmount);

        uint256 burnAmount = 5;
        vm.prank(alice);
        stablecoin.approve(address(engine), burnAmount);

        vm.prank(alice);
        engine.burnXHH(burnAmount);

        assertEq(engine.getMintAmount(alice), mintAmount - burnAmount);
    }

    function test_burnXHHWhenAmountIs0() public {
        uint256 burnAmount = 0;
        vm.prank(alice);
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.burnXHH(burnAmount);
    }

    function test_burnXHHWhenInsufficientBalance() public {
        uint256 burnAmount = 10;
        vm.prank(alice);
        vm.expectRevert();
        engine.burnXHH(burnAmount);
    }

    function test_getUSDValue_Success() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;
        (, int256 price,,,) = engine.getPriceFeed(tokenAddr).latestRoundData();

        uint256 expectedUsdValue = uint256(price) * engine.getPRICE_SCALE() * amount / engine.getPrecisionUnit();
        uint256 actualUsdValue = engine.getUSDValue(tokenAddr, amount);

        assertEq(actualUsdValue, expectedUsdValue);
    }

    function test_getUSDValue_InvalidPrice() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 100;

        // mock price feed to return 0
        vm.mockCall(
            helperConfig.getNetworkConfig().collateralTokenPriceFeeds[0],
            abi.encodeWithSelector(engine.getPriceFeed(tokenAddr).latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );

        vm.expectRevert(XHHEngine.XHHEngine_InvalidPriceFeed.selector);
        engine.getUSDValue(tokenAddr, amount);
    }

    function test_getUSDValue_InvalidToken() public {
        address tokenAddr = address(0);
        uint256 amount = 100;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.getUSDValue(tokenAddr, amount);
    }

    function test_getUSDValue_ZeroAmount() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 amount = 0;
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.getUSDValue(tokenAddr, amount);
    }

    function test_getTokenAmountFromUSD_Success() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 usdAmount = 100;
        (, int256 price,,,) = engine.getPriceFeed(tokenAddr).latestRoundData();

        uint256 expectedTokenAmount = usdAmount * engine.getPrecisionUnit() / (uint256(price) * engine.getPRICE_SCALE());
        uint256 actualTokenAmount = engine.getTokenAmountFromUSD(tokenAddr, usdAmount);

        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    function test_getTokenAmountFromUSD_InvalidTokenAddress() public {
        address tokenAddr = address(0);
        uint256 usdAmount = 100;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.getTokenAmountFromUSD(tokenAddr, usdAmount);
    }

    function test_getTokenAmountFromUSD_UnlistedToken() public {
        address tokenAddr = makeAddr("unlistedToken");
        uint256 usdAmount = 100;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidPriceFeed.selector);
        engine.getTokenAmountFromUSD(tokenAddr, usdAmount);
    }

    function test_getTokenAmountFromUSD_ZeroUsdAmount() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 usdAmount = 0;
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.getTokenAmountFromUSD(tokenAddr, usdAmount);
    }

    function test_getTokenAmountFromUSD_InvalidPrice() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 usdAmount = 100;

        // mock price feed to return 0
        vm.mockCall(
            helperConfig.getNetworkConfig().collateralTokenPriceFeeds[0],
            abi.encodeWithSelector(engine.getPriceFeed(tokenAddr).latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );

        vm.expectRevert(XHHEngine.XHHEngine_InvalidPriceFeed.selector);
        engine.getTokenAmountFromUSD(tokenAddr, usdAmount);
    }

    // function test_liquidate_Success() public {

    // }

    function test_liquidate_RevertWhenUserIsHealthy() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 100;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, collateralAmount);

        uint256 mintAmount = 10;
        vm.prank(alice);
        engine.mintXHH(mintAmount);

        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 10;

        vm.prank(liquidator);
        vm.expectRevert(XHHEngine.XHHEngine_UserHealthy.selector);
        engine.liquidate(tokenAddr, alice, debtToCover);
    }

    function test_liquidate_RevertWhenCollateralIsZeroAddress() public {
        address tokenAddr = address(0);
        uint256 debtToCover = 10;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.liquidate(tokenAddr, alice, debtToCover);
    }

    function test_liquidate_RevertWhenUserIsZeroAddress() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        address user = address(0);
        uint256 debtToCover = 10;
        vm.expectRevert(XHHEngine.XHHEngine_InvalidAddress.selector);
        engine.liquidate(tokenAddr, user, debtToCover);
    }

    function test_liquidate_RevertWhenDebtToCoverIsZero() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 debtToCover = 0;
        vm.expectRevert(XHHEngine.XHHEngine_AmountMustBeGreaterThan0.selector);
        engine.liquidate(tokenAddr, alice, debtToCover);
    }

    function test_liquidate_RevertWhenDebtToCoverIsMoreThanUserDebt() public {
        address tokenAddr = helperConfig.getNetworkConfig().collateralTokens[0];
        uint256 collateralAmount = 10;

        ERC20Mock(tokenAddr).mint(alice, collateralAmount);
        vm.prank(alice);
        ERC20Mock(tokenAddr).approve(address(engine), collateralAmount);

        vm.prank(alice);
        engine.depositCollateral(tokenAddr, collateralAmount);

        uint256 mintAmount = 1000;
        vm.prank(alice);
        engine.mintXHH(mintAmount);

        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 1001;

        vm.prank(liquidator);
        vm.expectRevert(XHHEngine.XHHEngine_InsufficientBalance.selector);
        engine.liquidate(tokenAddr, alice, debtToCover);
    }
}
