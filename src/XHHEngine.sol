// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHStablecoin} from "./XHHStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract XHHEngine is ReentrancyGuard {
    error XHHEngine_InvalidAddress();
    error XHHEngine_AmountMustBeGreaterThan0();
    error XHHEngine_TransferFailed();
    error XHHEngine_InsufficientBalance();
    error XHHEngine_InsufficientAllowance();
    error XHHEngine_InvalidPriceFeed();
    error XHHEngine_UserUnhealthy();
    error XHHEngine_InvalidFeeds();
    error XHHEngine_UserHealthy();
    error XHHEngine_UserHealthyFactorNotImproved();

    event XHHEngine_CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event XHHEngine_RedeemCollateral(address indexed from, address indexed to, address indexed token, uint256 amount);

    /**
     * @dev Maps collateral token addresses to user addresses to deposited amounts.)
     * @notice Maps user addresses to token addresses to deposited amounts.
     */
    mapping(address => mapping(address => uint256)) private s_collateralDeposited;

    /**
     * @dev Maps collateral token addresses to price feed addresses.
     */
    mapping(address => address) private s_collateralTokenFeeds;

    /**
     * @dev Maps user addresses to minted stablecoin amounts.
     */
    mapping(address => uint256) private s_mints;

    XHHStablecoin private immutable _stablecoin;

    address[] private s_collateralTokens;

    uint256 private constant PRECISION_UNIT = 1e18;
    uint256 private constant PRICE_SCALE = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    modifier checkAmount(uint256 amount) {
        if (amount == 0) {
            revert XHHEngine_AmountMustBeGreaterThan0();
        }
        _;
    }

    modifier checkZeroAddress(address tokenAddr) {
        if (tokenAddr == address(0)) {
            revert XHHEngine_InvalidAddress();
        }

        _;
    }

    modifier checkTokenBalance(address tokenAddr, uint256 amount) {
        // Check if the contract has enough balance of the collateral token
        uint256 contractBalance = IERC20(tokenAddr).balanceOf(msg.sender);
        if (contractBalance < amount) {
            revert XHHEngine_InsufficientBalance();
        }
        _;
    }

    modifier checkTokenAllowance(address tokenAddr, uint256 amount) {
        // Check if the user has approved the contract to transfer the tokens
        uint256 allowance = IERC20(tokenAddr).allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert XHHEngine_InsufficientAllowance();
        }
        _;
    }

    modifier checkPriceFeedAddress(address tokenAddr) {
        if (s_collateralTokenFeeds[tokenAddr] == address(0)) {
            revert XHHEngine_InvalidPriceFeed();
        }
        _;
    }

    constructor(address stablecoinAddress, address[] memory tokenAddrs, address[] memory tokenFeeds) {
        if (tokenAddrs.length != tokenFeeds.length) {
            revert XHHEngine_InvalidFeeds();
        }
        _stablecoin = XHHStablecoin(stablecoinAddress);
        s_collateralTokens = tokenAddrs;
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            s_collateralTokenFeeds[tokenAddrs[i]] = tokenFeeds[i];
        }
    }
    /**
     * @dev Deposits `amount` of `tokenAddr` to the contract and mints `amount` of stablecoin to the caller.
     *
     * @param tokenAddr The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to deposit.
     * @param mintAmount The amount of stablecoin tokens to mint.
     */

    function depositCollateralAndMintXHH(address tokenAddr, uint256 collateralAmount, uint256 mintAmount) public {
        depositCollateral(tokenAddr, collateralAmount);
        mintXHH(mintAmount);
    }

    /**
     * @dev Deposits `amount` of `tokenAddr` to the contract.
     *
     * Emits a {CollateralDeposited} event.
     *
     * Requirements:
     *
     * - `tokenAddr` must be a valid token.
     * - `amount` must be greater than 0.
     */
    function depositCollateral(address tokenAddr, uint256 amount)
        public
        checkZeroAddress(tokenAddr)
        checkAmount(amount)
        checkTokenAllowance(tokenAddr, amount)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenAddr] += amount;
        emit XHHEngine_CollateralDeposited(msg.sender, tokenAddr, amount);
        // Transfer tokens safely using the IERC20 interface
        bool success = IERC20(tokenAddr).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
    }

    /**
     * @dev Mints `amount` of stablecoin to the caller.
     *
     *
     * Requirements:
     *
     * - `amount` must be greater than 0.
     */
    function mintXHH(uint256 amount) public checkAmount(amount) nonReentrant {
        _mintXHH(msg.sender, amount);
        //  mint stablecoin can reduce the health factor of the user,so we need to check if the user is healthy after minting.
        _revertIfUserUnhealthy(msg.sender);
    }

    function _mintXHH(address user, uint256 amount) internal {
        s_mints[user] += amount;
        _stablecoin.mint(user, amount);
    }

    /**
     * @dev Redeems `amount` of `tokenAddr` from the contract and burns `amount` of stablecoin from the caller.
     *
     * @param tokenAddr The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to redeem.
     * @param burnAmount The amount of stablecoin tokens to burn.
     */
    function redeemCollateralAndBurnXHH(address tokenAddr, uint256 collateralAmount, uint256 burnAmount) public {
        redeemCollateral(tokenAddr, collateralAmount);
        burnXHH(burnAmount);
    }

    /**
     * @dev Redeems `amount` of `tokenAddr` from the contract.
     *
     * Emits a {RedeemCollateral} event.
     *
     * Requirements:
     *
     * - `tokenAddr` must be a valid token.
     * - `amount` must be greater than 0.
     */
    function redeemCollateral(address tokenAddr, uint256 amount)
        public
        checkZeroAddress(tokenAddr)
        checkAmount(amount)
        nonReentrant
    {
        _redeemCollateral(tokenAddr, msg.sender, msg.sender, amount);
        //  check if the user is healthy after redeeming the collateral
        _revertIfUserUnhealthy(msg.sender);
    }

    /**
     * @dev Redeems `amount` of `tokenAddr` from the contract.
     *
     * Emits a {RedeemCollateral} event.
     *
     * Requirements:
     *
     * - `tokenAddr` must be a valid token.
     * - `amount` must be greater than 0.
     */
    function _redeemCollateral(address tokenAddr, address from, address to, uint256 amount) internal {
        // Check if the user has enough deposited collateral
        uint256 depositedAmount = s_collateralDeposited[from][tokenAddr];
        if (depositedAmount < amount) {
            revert XHHEngine_InsufficientBalance();
        }

        s_collateralDeposited[from][tokenAddr] -= amount;
        emit XHHEngine_RedeemCollateral(from, to, tokenAddr, amount);
        //  transfer tokens safely using the IERC20 interface
        bool success = IERC20(tokenAddr).transfer(to, amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
    }

    function burnXHH(uint256 amount) public checkAmount(amount) nonReentrant {
        _burnXHH(msg.sender, msg.sender, amount);
    }

    /**
     * @dev Burns `amount` of stablecoin from the caller.
     *
     *
     * - `debtUser` must be a valid user.
     * - `xhhFrom` must be a valid user.
     * - `amount` must be greater than 0.
     */
    function _burnXHH(address debtUser, address xhhFrom, uint256 amount) internal {
        s_mints[debtUser] -= amount;
        // transfer stablecoin to the contract
        bool success = _stablecoin.transferFrom(xhhFrom, address(this), amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
        _stablecoin.burn(amount);
    }

    /**
     * @dev Calculates the amount of USD that `amount` of `tokenAddr` tokens is worth.
     *
     *
     * @param tokenAddr The address of the collateral token.
     * @param amount The amount of collateral tokens to calculate the USD value for.
     * @return The amount of USD that `amount` of `tokenAddr` tokens is worth.
     */
    function getUSDValue(address tokenAddr, uint256 amount)
        public
        view
        checkZeroAddress(tokenAddr)
        checkPriceFeedAddress(tokenAddr)
        returns (uint256)
    {
        if (amount == 0) {
            return 0;
        }

        address priceFeedAddr = s_collateralTokenFeeds[tokenAddr];

        //  get price from price feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price <= 0) {
            revert XHHEngine_InvalidPriceFeed();
        }
        //  convert price to uint256 and scale it to the same decimal as the collateral token
        // the price is in 8 decimal places, so we need to scale it to 18 decimal places
        // `price` is in 8 decimal places, so we need to scale it to 18 decimal places
        // `amount` is in 18 decimal places, so we need to divide it by 1e18 to get the price in 18 decimal places
        return uint256(price) * PRICE_SCALE * amount / PRECISION_UNIT;
    }

    /**
     * @dev Calculates the amount of `tokenAddr` tokens that can be redeemed for `usdAmount` of stablecoin.
     *
     *
     * @param tokenAddr The address of the collateral token.
     * @param usdAmount The amount of stablecoin tokens to redeem,1:1 usd
     * @return The amount of `tokenAddr` tokens that can be redeemed for `usdAmount` of stablecoin.
     */
    function getTokenAmountFromUSD(address tokenAddr, uint256 usdAmount)
        public
        view
        checkZeroAddress(tokenAddr)
        checkAmount(usdAmount)
        checkPriceFeedAddress(tokenAddr)
        returns (uint256)
    {
        address priceFeedAddr = s_collateralTokenFeeds[tokenAddr];

        //  get price from price feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price <= 0) {
            revert XHHEngine_InvalidPriceFeed();
        }
        //  convert price to uint256 and scale it to the same decimal as the collateral token
        // the price is in 8 decimal places, so we need to scale it to 18 decimal places
        // `price` is in 8 decimal places, so we need to scale it to 18 decimal places
        // `usdAmount` is in 18 decimal places, so we need to divide it by 1e18 to get the price in 18 decimal places
        return usdAmount * PRECISION_UNIT / (uint256(price) * PRICE_SCALE);
    }

    function healthFactor(address userAddr) public view returns (uint256) {
        (uint256 totalCollateralValue, uint256 totalMintedAmount) = _calculateCollateralValues(userAddr);
        return _calculateHealthFactor(totalCollateralValue, totalMintedAmount);
    }

    function getPRICE_SCALE() public pure returns (uint256) {
        return PRICE_SCALE;
    }

    /**
     * @dev Liquidates `userAddr`'s position if the health factor is below the threshold.
     *
     * @param collateral The address of the collateral token.
     * @param userAddr The address of the user to liquidate.
     * @param debtToCover The amount of stablecoin tokens to cover.
     */
    function liquidate(address collateral, address userAddr, uint256 debtToCover)
        public
        checkZeroAddress(collateral)
        checkZeroAddress(userAddr)
        checkAmount(debtToCover)
    {
        // check the user stablecoin balance
        uint256 userDebt = s_mints[userAddr];
        if (userDebt < debtToCover) {
            revert XHHEngine_InsufficientBalance();
        }

        //  check the user health factor
        uint256 userStartHealthFactor = healthFactor(userAddr);
        if (userStartHealthFactor >= MIN_HEALTH_FACTOR) {
            revert XHHEngine_UserHealthy();
        }

        // calculate the collateral amount to liquidate
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);

        // calculate the bonus amount
        uint256 bonusTokenAmount = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;

        _redeemCollateral(collateral, userAddr, msg.sender, tokenAmountFromDebtCovered + bonusTokenAmount);
        _burnXHH(userAddr, msg.sender, debtToCover);

        // check the user health factor after liquidation is improved
        uint256 userEndHealthFactor = healthFactor(userAddr);
        if (userEndHealthFactor <= userStartHealthFactor) {
            revert XHHEngine_UserHealthyFactorNotImproved();
        }

        //  check the liquidated user health factor
        _revertIfUserUnhealthy(msg.sender);
    }

    function calculateHealthFactor(uint256 totalCollateralValue, uint256 totalMintedAmount)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalCollateralValue, totalMintedAmount);
    }

    /**
     * @dev Calculates the health factor of a user.
     *
     * @param totalCollateralValue The total value of the collateral tokens in wei.
     * @param totalMintedAmount The total amount of the minted stablecoin tokens in wei.
     * @return healthFactor The health factor of the user.
     */
    function _calculateHealthFactor(uint256 totalCollateralValue, uint256 totalMintedAmount)
        internal
        pure
        returns (uint256)
    {
        // if the user has no minted stablecoin tokens, the health factor is max
        if (totalMintedAmount == 0) {
            return type(uint256).max;
        }
        //
        uint256 halfCollateralValue = totalCollateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return halfCollateralValue * PRECISION_UNIT / totalMintedAmount;
    }

    function calculateCollateralValues(address userAddr)
        external
        view
        returns (uint256 totalCollateralValue, uint256 totalMintedAmount)
    {
        return _calculateCollateralValues(userAddr);
    }

    /**
     * @dev Calculates the total value and amount of collateral tokens deposited by `userAddr`.
     *
     * @param userAddr The address of the user.
     * @return totalCollateralValue The total value of the collateral tokens in wei.
     * @return totalMintedAmount The total amount of the minted stablecoin tokens in wei.
     */
    function _calculateCollateralValues(address userAddr)
        internal
        view
        returns (uint256 totalCollateralValue, uint256 totalMintedAmount)
    {
        totalMintedAmount = s_mints[userAddr];
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddr = s_collateralTokens[i];
            uint256 depositedAmount = s_collateralDeposited[userAddr][tokenAddr];
            if (depositedAmount == 0) {
                continue;
            }
            uint256 tokenPrice = getUSDValue(tokenAddr, depositedAmount);
            totalCollateralValue += tokenPrice;
        }
    }

    function checkHealthFactor(address userAddr) public view returns (bool) {
        return healthFactor(userAddr) >= MIN_HEALTH_FACTOR;
    }

    function _revertIfUserUnhealthy(address userAddr) internal view {
        if (healthFactor(userAddr) < MIN_HEALTH_FACTOR) {
            revert XHHEngine_UserUnhealthy();
        }
    }

    function getCollateralAmount(address userAddr, address tokenAddr) public view returns (uint256) {
        return s_collateralDeposited[userAddr][tokenAddr];
    }

    function getMintAmount(address userAddr) public view returns (uint256) {
        return s_mints[userAddr];
    }

    function getPrecisionUnit() public pure returns (uint256) {
        return PRECISION_UNIT;
    }

    function getPriceFeed(address tokenAddr) public view returns (AggregatorV3Interface) {
        return AggregatorV3Interface(s_collateralTokenFeeds[tokenAddr]);
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
}
