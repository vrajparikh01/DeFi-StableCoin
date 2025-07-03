// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDsc is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(DSCEngine, DecentralizedStablecoin, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin dsc = new DecentralizedStablecoin(vm.addr(deployerKey));
        console.log("DSC Address: ", address(dsc));

        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc)); 
        console.log("DSCEngine Address: ", address(dscEngine));

        // Transfer ownership of the DSC token to the DSCEngine
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dscEngine, dsc, helperConfig);
    }
}
