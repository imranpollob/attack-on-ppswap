// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {PPSwap} from "../src/PPSwap.sol";
import {Attack} from "../src/PPSwap.sol";

contract PPSwapTest is Test {
    PPSwap public ppSwap;
    address player1 = address(1);
    address player2 = address(2);
    address player3 = address(3);

    function setUp() public {
        ppSwap = new PPSwap();
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
    }

    function test_deposit() public {
        vm.prank(player1);
        ppSwap.deposit{value: 1 ether}();
        vm.prank(player2);
        ppSwap.deposit{value: 1 ether}();
        vm.prank(player3);
        ppSwap.deposit{value: 1 ether}();

        assertEq(
            address(ppSwap).balance,
            3 ether,
            "Deposit of 1 ether should be accepted"
        );

        assertEq(
            ppSwap.winner(),
            player3,
            "The winner should be the third player"
        );

        uint initialBalance = player3.balance;
        vm.prank(player3);
        ppSwap.claimReward();
        uint finalBalance = player3.balance;

        assertEq(
            finalBalance - initialBalance,
            3 ether,
            "Winner's balance should increase by 3 ether"
        );

        assertEq(
            ppSwap.winner(),
            address(0),
            "Winner address should be reset to 0"
        );
    }

    function test_attack() public {
        vm.prank(player1);
        ppSwap.deposit{value: 1 ether}();
        vm.prank(player2);
        ppSwap.deposit{value: 1 ether}();

        Attack attack = new Attack(payable(address(ppSwap)));
        attack.attack{value: 3 ether}();
        assertGt(
            address(ppSwap).balance,
            3 ether,
            "Deposit of 1 ether should be accepted"
        );

        vm.prank(player3);
        ppSwap.deposit{value: 1 ether}(); 
    }
}
