// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
* This is an ERC20 contract meant to be owned by DSCEngine that can be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStablecoin is ERC20, ERC20Burnable, Ownable {
    constructor(address initialOwner)
        ERC20("DecentralizedStablecoin", "DSC")
        Ownable(initialOwner)
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Cannot mint to the zero address");
        require(amount > 0, "Amount must be greater than zero");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        require(from != address(0), "Cannot burn from the zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(from) >= amount, "Insufficient balance to burn");
        _burn(from, amount);
    }
}