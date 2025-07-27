// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockV3Aggregator {
    int256 private _price;
    uint8 public decimals;

    constructor(int256 initialPrice, uint8 _decimals) {
        _price = initialPrice;
        decimals = _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, _price, 0, 0, 0);
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
}
