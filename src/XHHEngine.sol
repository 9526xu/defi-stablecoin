// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHStablecoin} from "./XHHStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract XHHEngine is ReentrancyGuard {
    error XHHEngine_InvalidToken();
    error XHHEngine_AmountMustBeGreaterThan0();
    error XHHEngine_TransferFailed();
    error XHHEngine_InsufficientBalance();
    error XHHEngine_InsufficientAllowance();
    error XHHEngine_InvalidPriceFeed();
    error XHHEngine_UserUnhealthy();

    event XHHEngine_CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event XHHEngine_RedeemCollateral(address indexed user, address indexed token, uint256 amount);

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

    modifier checkAmount(uint256 amount) {
        if (amount == 0) {
            revert XHHEngine_AmountMustBeGreaterThan0();
        }
        _;
    }

    modifier checkToken(address tokenAddr) {
        if (tokenAddr == address(0)) {
            revert XHHEngine_InvalidToken();
        }

        _;
    }

    modifier checkTokenBalance(address tokenAddr, uint256 amount) {
        // Check if the contract has enough balance of the collateral token
        uint256 contractBalance = IERC20(tokenAddr).balanceOf(address(this));
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

    constructor(address stablecoinAddress, address[] memory tokenAddrs, address[] memory tokenFeeds) {
        if (tokenAddrs.length != tokenFeeds.length) {
            revert XHHEngine_InvalidToken();
        }
        s_collateralTokens = tokenAddrs;
        _stablecoin = XHHStablecoin(stablecoinAddress);
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            s_collateralTokenFeeds[tokenAddrs[i]] = tokenFeeds[i];
        }
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
        checkToken(tokenAddr)
        checkAmount(amount)
        checkTokenBalance(tokenAddr, amount)
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
        s_mints[msg.sender] += amount;

        //  mint stablecoin can reduce the health factor of the user,so we need to check if the user is healthy after minting.
        _revertIfUserUnhealthy(msg.sender);
        _stablecoin.mint(msg.sender, amount);
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
        checkToken(tokenAddr)
        checkAmount(amount)
        nonReentrant
    {
        _redeemCollateral(tokenAddr, amount);
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
    function _redeemCollateral(address tokenAddr, uint256 amount)
        public
        checkToken(tokenAddr)
        checkAmount(amount)
        nonReentrant
    {
        // Check if the user has enough deposited collateral
        uint256 depositedAmount = s_collateralDeposited[msg.sender][tokenAddr];
        if (depositedAmount < amount) {
            revert XHHEngine_InsufficientBalance();
        }

        //  check if the contract has enough balance of the collateral token
        uint256 contractBalance = IERC20(tokenAddr).balanceOf(address(this));
        if (contractBalance < amount) {
            revert XHHEngine_InsufficientBalance();
        }

        s_collateralDeposited[msg.sender][tokenAddr] -= amount;
        emit XHHEngine_RedeemCollateral(msg.sender, tokenAddr, amount);
        //  transfer tokens safely using the IERC20 interface
        bool success = IERC20(tokenAddr).transfer(msg.sender, amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
    }

    /**
     * @dev Burns `amount` of stablecoin from the caller.
     *
     * 1. transfer stablecoin from the caller to the contract
     * 2. burn stablecoin from the contract
     *
     * because only the owner (XHHEngine) can burn stablecoin, so we need to check if the caller is the owner.
     *
     * Requirements:
     *
     * - `amount` must be greater than 0.
     */
    function burnXHH(uint256 amount) public checkAmount(amount) nonReentrant {
        s_mints[msg.sender] -= amount;
        // transfer stablecoin to the contract
        bool success = _stablecoin.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
        _stablecoin.burn(amount);
    }

    function getCollateralTokenPrice(address tokenAddr, uint256 amount) public view returns (uint256) {
        address priceFeedAddr = s_collateralTokenFeeds[tokenAddr];
        if (priceFeedAddr == address(0)) {
            revert XHHEngine_InvalidToken();
        }

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

    function healthFactor(address userAddr) public view returns (uint256) {
        (uint256 totalCollateralValue, uint256 totalMintedAmount) = _calculateCollateralValues(userAddr);

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
            uint256 tokenPrice = getCollateralTokenPrice(tokenAddr, depositedAmount);
            totalCollateralValue += tokenPrice;
        }
    }

    function _revertIfUserUnhealthy(address userAddr) internal view {
        if (healthFactor(userAddr) < MIN_HEALTH_FACTOR) {
            revert XHHEngine_UserUnhealthy();
        }
    }
}
