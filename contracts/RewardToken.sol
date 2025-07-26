// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardToken
/// @notice ERC20 token that can be minted by the owner. Used as rewards in the staking platform.
contract RewardToken is ERC20, Ownable {
    /// @notice Creates the token and mints initial supply to the deployer.
    /// @param initialSupply Initial token supply minted to the deployer.
    constructor(uint256 initialSupply) ERC20("RewardToken", "RWT") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

    /// @notice Mint new tokens. Only callable by the owner.
    /// @param to Address to receive the minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
