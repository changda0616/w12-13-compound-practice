// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/ComptrollerInterface.sol";

import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";

import "compound-protocol/contracts/InterestRateModel.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";

import "../src/TestErc20.sol";

contract DeployComp is Script {

    function run()
        public
        returns (
            Unitroller,
            Comptroller,
            SimplePriceOracle,
            WhitePaperInterestRateModel,
            CErc20Delegate,
            CErc20Delegator
        )
    {
        uint256 key = vm.envUint("wallet_key");
        address admin = vm.envAddress("wallet");
        vm.startBroadcast(key);

        // propose controller and unitroller (proxy)
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller();
        Comptroller unitrollerProxy = Comptroller(address(unitroller));

        // set implementaton of unitroller
        unitroller._setPendingImplementation(address(comptroller));
        // unitroller accept comptroller
        comptroller._become(unitroller);

        // set close factor at 50%
        unitrollerProxy._setCloseFactor(0.5 * 1e18);
        // set liquidation incentive at 1.08
        unitrollerProxy._setLiquidationIncentive(1.08 * 1e18);
        // set prepare oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        unitrollerProxy._setPriceOracle(priceOracle);

        // prepare InterestRateModel
        WhitePaperInterestRateModel whitePaperInterestRateModel = new WhitePaperInterestRateModel(
                0,
                0
            );

        // prepare undelying ERC20 Token
        TestErc20 Sai = new TestErc20("Sai test", "SAI");

        // prepare token implementation, CErc20Delegate
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        // prepare token proxy, CErc20Delegator
        CErc20Delegator cSai = new CErc20Delegator(
            address(Sai),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1 * 1e18, // rate 10 ** 18 / 10 ** 18
            "Compound Sai",
            "cSAI",
            18,
            payable(admin),
            address(cErc20Delegate),
            ""
        );

        cSai._setReserveFactor(0.1 * 1e18);

        // Add cSai to unitroller's markets map
        unitrollerProxy._supportMarket(CToken(address(cSai)));
        
        priceOracle.setUnderlyingPrice(CToken(address(cSai)), 1e18);

        // The borrower can only borrow 70% of the collateral value
        unitrollerProxy._setCollateralFactor(CToken(address(cSai)), 0.7 * 1e18);


        vm.stopBroadcast();

        return (
            unitroller,
            comptroller,
            priceOracle,
            whitePaperInterestRateModel,
            cErc20Delegate,
            cSai
        );
    }
}
