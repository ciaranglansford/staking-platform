// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title StakingToken
/// @notice ERC20 token used as the staking asset. Mintable by the owner for testing or liquidity purposes.
contract StakingToken is ERC20, Ownable {
    /// @notice Creates the token and mints initial supply to the deployer.
    /// @param initialSupply Initial token supply minted to the deployer.
    constructor(uint256 initialSupply) ERC20("StakingToken", "STK") {
        _mint(msg.sender, initialSupply);
    }

    /// @notice Mint new tokens. Only callable by the owner.
    /// @param to Address to receive the minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
