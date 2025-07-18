// Have our invariants aka properties that should always hold true been violated

// What are our invariants?
// 1. Total supply of DSC should always be less than total supply of collateral
// 2. Getter view functions should not revert

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDsc public deployDsc;
    DSCEngine public dscEngine;
    DecentralizedStablecoin public dsc;
    HelperConfig public config;
    address public weth;
    address public wbtc;
    Handler public handler;

    function setUp() public {
        deployDsc = new DeployDsc();
        (dscEngine, dsc, config) = deployDsc.run();
        (,, weth, wbtc, ) = config.activeNetworkConfig();

        // Set the target contract for invariants
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));

        // don't call redeemCollateral if there is no collateral
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupplyDsc = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 totalValue = wethValue + wbtcValue;

        console.log("Weth Value: %s", wethValue);
        console.log("Wbtc Value: %s", wbtcValue);
        console.log("Total Value: %s", totalValue);
        console.log("Times Mint Called: %s", handler.timesMintIsCalled());

        assert(totalValue >= totalSupplyDsc);
    }
}