// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";

contract DeployComp is Script {
    function setUp() public {
        
    }

    function run() public {
        uint256 key = vm.envUint('wallet_key');
        vm.startBroadcast(key);
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller();
        Comptroller unitrollerProxy = Comptroller(address(unitroller));
        
        // prepare oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        
        
        vm.stopBroadcast();
    }
}
