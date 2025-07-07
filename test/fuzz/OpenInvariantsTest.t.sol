// Have our invariants aka properties that should always hold true been violated

// What are our invariants?
// 1. Total supply of DSC should always be less than total supply of collateral
// 2. Getter view functions should not revert

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDsc public deployDsc;
    DSCEngine public dscEngine;
    DecentralizedStablecoin public dsc;
    HelperConfig public config;
    address public weth;
    address public wbtc;

    function setUp() public {
        deployDsc = new DeployDsc();
        (dscEngine, dsc, config) = deployDsc.run();
        (,, weth, wbtc, ) = config.activeNetworkConfig();

        // Set the target contract for invariants
        targetContract(address(dscEngine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupplyDsc = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 totalValue = wethValue + wbtcValue;

        assert(totalValue >= totalSupplyDsc);
    }
}