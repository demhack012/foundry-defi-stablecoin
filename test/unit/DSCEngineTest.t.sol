// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {Test, stdError, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralSecondUser() {
        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function calculateHealthFactor(uint256 collateralValueInUsd, uint256 totalDscMinted)
        public
        pure
        returns (uint256)
    {
        return ((((collateralValueInUsd * 50) / 100) * 1e18) / totalDscMinted);
    }

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER2, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfPriceFeedAddressesLengthDoesntMatchTokenLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__ArrayLengthsDoNotMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    // Prices Tests //
    //////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 2 ether;
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        uint256 expectedUsdValue = 8000e18;
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 2000 ether;
        uint256 actualTokenAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        uint256 expectedTokenAmount = 0.5 ether;
        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    ///////////////////
    // Deposit Tests //
    ///////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        // ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RanToken", "RAN", USER, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        // ranToken.approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedCollateralDeposited, COLLATERAL_AMOUNT);
        assertEq(expectedDscMinted, dscMinted);
    }

    function testMintDscRevertsIfHealthFactorBroken() public depositCollateral {
        vm.startPrank(USER);
        uint256 userHealthFactor = 5e17;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, userHealthFactor));
        engine.mintDSC(40000 ether);
    }

    function testGetHealthFactor() public depositCollateral {
        vm.startPrank(USER);
        uint256 expectedUserHealthFactor = 1e18;
        engine.mintDSC(20000 ether);
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedUserHealthFactor);
        vm.stopPrank();
    }

    function testGetHealthFactorReturnsMaxWhenNoDscMinted() public depositCollateral {
        vm.startPrank(USER);
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(actualHealthFactor, type(uint256).max);
        vm.stopPrank();
    }

    function testMintDscUpdatesState() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(1000 ether);
        engine.mintDSC(2000 ether);
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 3000 ether;
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedCollateralDeposited, COLLATERAL_AMOUNT);
        assertEq(expectedDscMinted, dscMinted);
    }

    function testDepositCollateralAndMintDscRevertsIfHealthFactorBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        uint256 userHealthFactor = 5e17;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, userHealthFactor));
        engine.depositCollateralAndMintDSC(weth, COLLATERAL_AMOUNT, 40000 ether);
    }

    function testDepositCollateralAndMintDscUpdatesState() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDSC(weth, COLLATERAL_AMOUNT, 20000 ether);
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 20000 ether;
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        vm.stopPrank();
        assertEq(expectedCollateralDeposited, COLLATERAL_AMOUNT);
        assertEq(expectedDscMinted, dscMinted);
    }

    //////////////////
    // Redeem Tests //
    //////////////////

    function testRedeemCollateralRevertsIfLessThanZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsIfGreaterThanDeposited() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(stdError.arithmeticError);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT + 1);
        vm.stopPrank();
    }

    function testRedeemCollateralAllowsFullWithdrawalAndUpdatesState() public depositCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedUserBalance = 10 ether;
        (, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedCollateralDeposited, 0);
        assertEq(userBalance, expectedUserBalance);
    }

    function testRedeemCollateralFailsIfHealthFactorBroken() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        uint256 userHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, userHealthFactor));
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testBurnsDscGreaterThanZero() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        engine.burnDSC(0);
    }

    function testBurnsDscRevertsIfHealthFactorIsBroken() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(2000e8);
        uint256 collateralValueInUsd = engine.getUsdValue(weth, COLLATERAL_AMOUNT);
        uint256 userHealthFactor = calculateHealthFactor(collateralValueInUsd, 15000 ether);
        dsc.approve(address(engine), 20000 ether);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, userHealthFactor));
        engine.burnDSC(5000 ether);
    }

    function testBurnsDscUpdatesState() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        dsc.approve(address(engine), 20000 ether);
        engine.burnDSC(5000 ether);
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 15000 ether;
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedCollateralDeposited, COLLATERAL_AMOUNT);
        assertEq(expectedDscMinted, dscMinted);
    }

    function testRedeemCollateralForDscRevertsIfHealthFactorBroken() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        uint256 userHealthFactor = 0;
        dsc.approve(address(engine), 20000 ether);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorBroken.selector, userHealthFactor));
        engine.redeemCollateralForDsc(weth, COLLATERAL_AMOUNT, 1000 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscUpdatesState() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        dsc.approve(address(engine), 20000 ether);
        engine.redeemCollateralForDsc(weth, 1 ether, 5000 ether);
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 15000 ether;
        uint256 expectedCollateralDeposited = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedUserBalance = 1 ether;
        vm.stopPrank();
        assertEq(expectedCollateralDeposited, COLLATERAL_AMOUNT - 1 ether);
        assertEq(expectedDscMinted, dscMinted);
        assertEq(userBalance, expectedUserBalance);
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    /////////////////////
    // Liquidate Tests //
    /////////////////////

    function testLiquidateDebtToCoverGreaterThanZero() public depositCollateral depositCollateralSecondUser {
        vm.startPrank(USER2);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        engine.liquidate(weth, USER, 0);
    }

    function testCantLiquidateIfUserHasGoodHealthFactor() public depositCollateral depositCollateralSecondUser {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        vm.stopPrank();
        vm.startPrank(USER2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, 1000 ether);
    }

    function testLiquidationReducesDebt() public depositCollateral depositCollateralSecondUser {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        vm.stopPrank();
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(3200e8);
        vm.startPrank(USER2);
        engine.mintDSC(5000 ether);
        dsc.approve(address(engine), 2000 ether);
        engine.liquidate(weth, USER, 2000 ether);
        (uint256 dscMinted,) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 18000 ether;
        assertEq(dscMinted, expectedDscMinted);
    }

    function testLiquidationBonus() public depositCollateral depositCollateralSecondUser {
        vm.startPrank(USER);
        engine.mintDSC(20000 ether);
        vm.stopPrank();
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(3200e8);
        vm.startPrank(USER2);
        engine.mintDSC(5000 ether);
        dsc.approve(address(engine), 2000 ether);
        // console.log(ERC20Mock(weth).balanceOf(USER2));
        engine.liquidate(weth, USER, 2000 ether);
        uint256 expectedRedeemedCollateral = 0.6875 ether;
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER2);
        assertEq(userBalance, expectedRedeemedCollateral);
    }
}
