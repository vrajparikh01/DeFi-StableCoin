// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DecentralizedStablecoin } from "./DecentralizedStablecoin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { OracleLib } from "./libraries/OracleLib.sol";

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
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    DecentralizedStablecoin private immutable i_dscToken;
    mapping(address user => uint256 amount) public s_dscMinted;
    address[] public s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Chainlink price feeds return values in 8 decimal places
    uint256 private constant PRECISION = 1e18; 
    // 50% liquidation threshold means 200% collateralization ratio
    // eg: if a user has $200 worth of collateral, they can mint $100 worth of DSC
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant LIQUIDATION_THRESHOLD_PRECISION = 100; 
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address indexed collateralToken, uint256 amount);

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
            s_collateralTokens.push(collateralTokens[i]);
        }
        i_dscToken = DecentralizedStablecoin(dscToken);
    }

    /*
     * @notice This function allows users to deposit collateral and mint DSC in one transaction.
     * It follows CEI (Checks-Effects-Interactions) pattern.
     * @param collateralToken The address of the collateral token to deposit.
     * @param collateralAmount The amount of collateral to deposit.
     * @param dscAmountToMint The amount of DSC tokens to mint.
     */
    function depositCollateralAndMintDsc(address collateralToken, uint256 collateralAmount, uint256 dscAmountToMint) external{
        depositCollateral(collateralToken, collateralAmount);
        mintDsc(dscAmountToMint);
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

    /*
     * @notice Users must have more collateral than the value of DSC they mint.
     * It checks that the amount to mint is greater than zero and that the user has enough collateral.
     * @param dscAmountToMint The amount of DSC tokens to mint.
     */
    function mintDsc(uint256 dscAmountToMint) public moreThanZero(dscAmountToMint) nonReentrant {
        s_dscMinted[msg.sender] += dscAmountToMint;
        // check that the user has enough collateral to back the DSC they are minting
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dscToken.mint(msg.sender, dscAmountToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /*
     * @notice This function allows users to redeem their collateral and burn the corresponding DSC tokens.
     * In order to redeem collateral, health factor must be above 1 after collateral is redeemed.
     * It follows CEI (Checks-Effects-Interactions) pattern.
     * @param tokenCollateralAddress The address of the collateral token to redeem.
     * @param amountCollateral The amount of collateral to redeem.
     * @param burnAmount The amount of DSC tokens to burn.
     */
    function redeemCollateralAndBurnDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 burnAmount) external moreThanZero(amountCollateral) nonReentrant {
        // Burn the DSC tokens first
        s_dscMinted[msg.sender] -= burnAmount;
        i_dscToken.burn(msg.sender, burnAmount);

        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant onlySupportedCollateral(tokenCollateralAddress) {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // transfer the collateral to the user
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @notice This function allows users to liquidate a user's collateral if their health factor is below 1.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * It transfers the collateral to the liquidator and burns the corresponding DSC tokens.
     * @param collateralToken The address of the collateral token to liquidate.
     * @param user The address of the user to liquidate.
     * @param debtToCover The amount of collateral to liquidate.
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        // check the health factor of the user
        uint256 startinghealthFactor = _healthFactor(user);
        if (startinghealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // We want to burn the DSC debt of the user and take their collateral.
        //  Bad user: 140$ ETH, 100$ Dsc minted
        // debtToCover = 100$ Dsc
        // So we need to take 100$ worth of collateral from the user.
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        // give 10% of bonus to the liquidator
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;

        uint256 totalCollateralToLiquidate = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralToken, totalCollateralToLiquidate);

        // burn the DSC tokens of the user
        s_dscMinted[user] -= debtToCover;
        i_dscToken.burn(user, debtToCover);

        uint256 healthFactorAfterLiquidation = _healthFactor(user);
        if (healthFactorAfterLiquidation <= startinghealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        return (usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through all collateral tokens and sum their values
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // The returned value is in 8 decimal places, so we need to adjust it
        // to match the token's decimal places.
        if (price <= 0) {
            return 0;
        }
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _getAccountInformation(address user) private view returns (uint256 totalCollateralValue, uint256 totalDscMinted) {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValue = getAccountCollateralValue(user);
    }

    function getAccountInformation(address user) external view returns (uint256 totalCollateralValue, uint256 totalDscMinted) {
        (totalCollateralValue, totalDscMinted) = _getAccountInformation(user);
        return (totalCollateralValue, totalDscMinted);
    }

    /*
     * @notice This function calculates how close a user is to being liquidated.
     * The health factor is the ratio of the value of collateral to the value of DSC minted.
     * If the health factor is less than 1, it means the user can get liquidated.
     * @param user The address of the user to check.
     * @return The health factor for the user.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total Dsc minted
        // total collateral value
        (uint256 totalCollateralValue, uint256 totalDscMinted) = _getAccountInformation(user);
        return _calculateHealthFactor(totalCollateralValue, totalDscMinted);
    }

    function _calculateHealthFactor(uint256 totalCollateralValue, uint256 totalDscMinted) internal pure returns (uint256) {
        if (totalDscMinted == 0) {
            return type(uint256).max; // No DSC minted, health factor is infinite
        }
        // health factor = total collateral value / total Dsc minted
        // We multiply by PRECISION to avoid division by zero and to keep the precision
        return (totalCollateralValue * PRECISION) / totalDscMinted;
    }

    function calculateHealthFactor(uint256 totalCollateralValue, uint256 totalDscMinted) external pure returns (uint256) {
        return _calculateHealthFactor(totalCollateralValue, totalDscMinted);
    }

    // chech the health factor (do they have enough collateral to back the DSC they minted?)
    // if not, revert
    function _revertIfHealthFactorIsBroken(address user) internal view{
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken(healthFactor);
        }
    }

    // Getter functions
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dscToken);
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address collateralToken) external view returns (uint256) {
        return s_collateralDeposited[user][collateralToken];
    }

    function getCollateralTokenPriceFeed(address collateralToken) external view returns (address) {
        return s_priceFeeds[collateralToken];
    }
}