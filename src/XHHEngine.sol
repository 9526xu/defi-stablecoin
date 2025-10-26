// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {XHHStablecoin} from "./XHHStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract XHHEngine {
    error XHHEngine_InvalidToken();
    error XHHEngine_AmountMustBeGreaterThan0();
    error XHHEngine_TransferFailed();
    error XHHEngine_InsufficientBalance();
    error XHHEngine_InsufficientAllowance();

    event XHHEngine_CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event XHHEngine_RedeemCollateral(address indexed user, address indexed token, uint256 amount);

    /**
     * @dev Maps collateral token addresses to user addresses to deposited amounts.)
     * @notice Maps user addresses to token addresses to deposited amounts.
     */
    mapping(address => mapping(address => uint256)) private s_collateralDeposited;

    XHHStablecoin private immutable _stablecoin;

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

    constructor(address stablecoinAddress) {
        _stablecoin = XHHStablecoin(stablecoinAddress);
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
    function depositCollateral(address tokenAddr, uint256 amount) public checkToken(tokenAddr) checkAmount(amount) {
        // Check if the user has enough balance
        uint256 userBalance = IERC20(tokenAddr).balanceOf(msg.sender);
        if (userBalance < amount) {
            revert XHHEngine_InsufficientBalance();
        }
        // check if the user has approved the contract to transfer the tokens
        uint256 allowance = IERC20(tokenAddr).allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert XHHEngine_InsufficientAllowance();
        }

        //  TODO: check liquidity of the collateral token

        s_collateralDeposited[msg.sender][tokenAddr] += amount;
        emit XHHEngine_CollateralDeposited(msg.sender, tokenAddr, amount);

        // Transfer tokens safely using the IERC20 interface
        bool success = IERC20(tokenAddr).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
    }

    function mintXHH(uint256 amount) public checkAmount(amount) {
        _stablecoin.mint(msg.sender, amount);
    }

    function redeemCollateral(address tokenAddr, uint256 amount) public checkToken(tokenAddr) checkAmount(amount) {
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
        //  TODO: check liquidity of the collateral token

        emit XHHEngine_RedeemCollateral(msg.sender, tokenAddr, amount);
        //  transfer tokens safely using the IERC20 interface
        bool success = IERC20(tokenAddr).transfer(msg.sender, amount);
        if (!success) {
            revert XHHEngine_TransferFailed();
        }
    }

    function burnXHH(uint256 amount) public checkAmount(amount) {
        _stablecoin.burn(amount);
    }
}
