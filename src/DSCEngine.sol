// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

/////////////
// Imports //
/////////////

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

////////////////
// Interfaces //
////////////////

//////////////
// Liraries //
//////////////

///////////////
// Contracts //
///////////////

/*
    * @title Engine For Stable Coin DSC
    * @author ahmed Abo Abdallah
    * @dev this contract is the main engine that controls all the functions in the stable coin
*/

contract DSCEngine is ReentrancyGuard {
    ////////////
    // Errors //
    ////////////

    /**
     * @notice it is preffered to use error codes as it is more gas efficient
     * @notice write the contract name at the beginning of the error message
     * @custom:example "error ContractName__AmountMustBeGreaterThanZero();"
     */
    error DSCEngine__ArrayLengthsDoNotMatch();
    error DSCEngine__AmountMustBeGreaterThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////
    // Types //
    ///////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // State Variables //
    /////////////////////

    /**
     * @notice immutables then constants then state variables
     * @notice write the name of immuatable as i_variableName
     * @notice write the name of constant using CAPITAL letters as CONSTANT_NAME
     * @notice write the name of state variables as s_variableName
     */
    uint256 private constant ADDITIONAL_PRICEFEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address token => address priceFeed) private s_tokenPriceFeed;
    mapping(address user => mapping(address token => uint256 collateralDeposited)) private s_userCollateralDeposited;
    mapping(address user => uint256 dscMinted) private s_userDscMinted;
    address[] private s_collateralTokens;

    ////////////
    // Events //
    ////////////

    /**
     * @notice indexed keyword can be added only up to 3 parameters
     * @custom:example "event ExampleEvent(address indexed _address, uint256 _amount);"
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////
    // Modifiers //
    ///////////////

    modifier greterThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_tokenPriceFeed[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////

    /**
     * @notice Remember to Follow CEI pattern which is Checks, Effects, Interactions
     * checks: validate the inputs
     * effects: update the state variables
     * interactions: interact with other contracts or other functions
     * @notice Write the function name in camelCase
     */

    /////////////////
    // Constructor //
    /////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__ArrayLengthsDoNotMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
    Which function is called, fallback() or receive()?

           send Ether
               |
         msg.data is empty?
              / \
            yes  no
            /     \
    receive() exists?  fallback()
         /   \
        yes   no
        /      \
    receive()   fallback()

    */

    /////////////
    // recieve //
    /////////////

    // receive() external payable {}

    //////////////
    // fallback //
    //////////////

    // fallback() external payable {}

    ////////////////////////
    // External Functions //
    ////////////////////////

    /**
     * @notice External functions are part of the contract interface
     * which means they can be called from other contracts and via transactions.
     * @notice An external function f cannot be called internally (i.e. f() does not work, but this.f() works).
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        greterThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralAddress, totalCollateralToRedeem);
        _burnDsc(user, debtToCover);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////
    // Public Functions //
    //////////////////////

    /**
     * @notice Public functions are part of the contract interface and can be either called internally or via message calls.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) public {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    function depositCollateral(address tokenAddress, uint256 amount)
        public
        greterThanZero(amount)
        isAllowedToken(tokenAddress)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][tokenAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenAddress, amount);
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDSC(uint256 amountDscToMint) public greterThanZero(amountDscToMint) nonReentrant {
        s_userDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        public
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        greterThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public greterThanZero(amount) {
        _burnDsc(msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /**
     * @notice Internal functions can only be accessed from within the current contract or contracts deriving from it.
     * They cannot be accessed externally.
     * @notice They are not exposed to the outside through the contract’s ABI.
     * @notice They can take parameters of internal types like mappings or storage references.
     */

    ///////////////////////
    // Private Functions //
    ///////////////////////

    function _burnDsc(address onBehalfOf, uint256 amount) private {
        s_userDscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 collateralAmount)
        private
    {
        s_userCollateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Private functions are like internal ones but they are not visible in derived contracts.
     */

    //////////////////////////////////////////////
    // Internal & private view & pure Functions //
    //////////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_userDscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroken(userHealthFactor);
        }
    }

    /////////////////////////////////////////////
    // External & public view & pure Functions //
    /////////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenPriceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_PRICEFEED_PRECISION));
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenPriceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_PRICEFEED_PRECISION) * amount) / PRECISION;
    }

    /////////////
    // Getters //
    /////////////

    /**
     * @notice Getters are functions that return the value of state variables.
     * @notice state variables are more gas efficient when set to private so it is preffered to use getters to access them
     */
    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_userCollateralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_PRICEFEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_tokenPriceFeed[token];
    }
}
