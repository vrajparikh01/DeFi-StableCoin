// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DecentralizedStablecoin } from "./DecentralizedStablecoin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
 * @title DSCEngine
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__DepositCollateral_ZeroAmount();
    error DSCEngine__TokenAddressesAndPriceFeedsAddressLengthMismatch();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    DecentralizedStablecoin private immutable i_dscToken;

    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__DepositCollateral_ZeroAmount();
        }
        _;
    }

    modifier onlySupportedCollateral(address collateralToken) {
        if (s_priceFeeds[collateralToken] == address(0)) {
            revert DSCEngine__TokenNotAllowed(collateralToken);
        }
        _;
    }

    constructor(address[] memory collateralTokens, address[] memory priceFeeds, address dscToken) {
        if(collateralTokens.length != priceFeeds.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressLengthMismatch();
        }

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            s_priceFeeds[collateralTokens[i]] = priceFeeds[i];
        }
        i_dscToken = DecentralizedStablecoin(dscToken);
    }

    /* 
     * @notice This function allows users to deposit collateral into the DSCEngine.
     * It follows CEI (Checks-Effects-Interactions) pattern.
     * @param collateralToken The address of the collateral token to deposit.
     * @param collateralAmount The amount of collateral to deposit.
     */
    function depositCollateral(
        address collateralToken,
        uint256 collateralAmount
    )   public 
        moreThanZero(collateralAmount)
        onlySupportedCollateral(collateralToken)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][collateralToken] += collateralAmount;
        emit CollateralDeposited(msg.sender, collateralToken, collateralAmount);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }            
    }
}