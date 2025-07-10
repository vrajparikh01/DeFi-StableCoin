//  Handler narrows down the way we call the functions in the contract

// If we deposit collateral, we have to approve the contract to spend our tokens and then call the depositCollateral function
// So, handler makes it easier to call the functions in the contract (so that we don't waste the runs on the same function call)

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStablecoin public dsc;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public wethUsdPriceFeed;

    uint256 public constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStablecoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        wethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) external {
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalCollateralValue, uint256 totalDscMinted) = dscEngine.getAccountInformation(msg.sender);
        int256 maxDscToMint = (int256(totalCollateralValue) / 2) - int256(totalDscMinted);
        if(maxDscToMint <= 0) {
            return; // No need to mint if maxDscToMint is zero or negative
        }
        amountDsc = bound(amountDsc, 1, uint256(maxDscToMint));
        vm.startPrank(sender);
        dscEngine.mintDsc(amountDsc);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) external {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) external {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return; // No need to call redeemCollateral if amount is zero
        }
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    // This will break the fuzzing if we use it, so we comment it out
    // function updateCollateralPrice(uint96 newPrice) external {
    //     int256 newPriceInt = int256(uint256(newPrice)); 
    //     wethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}