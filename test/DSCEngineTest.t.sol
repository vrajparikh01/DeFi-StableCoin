// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "../script/DeployDsc.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDsc public deployDsc;
    DSCEngine public dscEngine;
    DecentralizedStablecoin public dsc;
    HelperConfig public config;
    address weth;
    address ethUsdPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant MINT_AMOUNT = 100 ether;
    
    function setUp() public {
        deployDsc = new DeployDsc();
        (dscEngine, dsc, config) = deployDsc.run();
        (ethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
    }

    function testGetUsdValue() public view{
        uint256 amount = 10 ether;
        uint256 expectedUsdValue = amount * 2000; // Assuming ETH price is $2000
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, amount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value calculation is incorrect");
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__DepositCollateral_ZeroAmount.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
