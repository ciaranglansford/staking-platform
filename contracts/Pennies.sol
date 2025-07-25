// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Pennies is ERC20 {
    constructor() ERC20("Pennies", "PNS") {
        _mint(msg.sender, 1_000_000 ether);
    }
}