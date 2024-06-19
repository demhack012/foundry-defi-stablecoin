// // SPDX-License-Identifier: MIT

// pragma solidity 0.8.22;

// import {Test, stdError, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
// import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is Test {
//     DSCEngine engine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address ethUSDPriceFeed;
//     address btcUSDPriceFeed;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         DeployDSC deployer = new DeployDSC();
//         (dsc, engine, config) = deployer.run();
//         (ethUSDPriceFeed, btcUSDPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(engine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsc));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsc));

//         uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         assert(wethValue + wbtcValue > totalSupply);
//     }
// }
