// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/* * @title OracleLib
 * @notice This library is intended to check Chainlink Oracle for stale data
 * If price is stale then function will revert and render DSC Engine unusable
 * We want to freeze DSC Engine if price is stale to prevent users from minting DSC
 * 
 * If Chainlink network is down and you have a lot of money in the protocol....bad news
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 public constant TIMEOUT = 3 hours; // 3 * 60 * 60 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        uint256 secondsSince = (block.timestamp - updatedAt);
        if( secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }
}