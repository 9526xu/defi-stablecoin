// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract XHHStablecoin is ERC20, Ownable, ERC20Burnable {
    error Stablecoin_AmountMustBeGreaterThan0();
    error Stablecoin_AddressMustBeValid();
    error Stablecoin_AmountMustBeLessThanOrEqualToBalance();

    constructor() ERC20("XHHStablecoin", "XHH") Ownable(msg.sender) {}

    modifier _checkAmountIsValid(uint256 amount) {
        if (amount <= 0) {
            revert Stablecoin_AmountMustBeGreaterThan0();
        }
        _;
    }

    function mint(address to, uint256 amount) public _checkAmountIsValid(amount) onlyOwner {
        if (to == address(0)) {
            revert Stablecoin_AddressMustBeValid();
        }

        _mint(to, amount);
    }

    function burn(uint256 amount) public override _checkAmountIsValid(amount) onlyOwner {
        if (amount > balanceOf(msg.sender)) {
            revert Stablecoin_AmountMustBeLessThanOrEqualToBalance();
        }

        super.burn(amount);
    }
}
