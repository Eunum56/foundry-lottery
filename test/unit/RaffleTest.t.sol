//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint32 callBackGasLimit;
    uint256 subscriptionId;

    event RaffleEntered(address indexed player);
    event RaffleWinner(address indexed winner);

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether; // 10e18

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        callBackGasLimit = config.callBackGasLimit;
        subscriptionId = config.subscriptionId;

        // Set PLAYER balance to 10 ether
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    //* Enter Raffle function tests

    function testRaffleStateInitializeCorrectly() public view {
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
        // console.log(raffle.getRaffleState());
        // console.log(Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testPlayerIsEnteredRaffle() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address player = raffle.getPlayer(0);
        assertEq(player, PLAYER);
    }

    function testEnteringRaffleEmmitingEvent() public {
        vm.prank(PLAYER);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(address(PLAYER));

        raffle.enterRaffle{value: entranceFee}();
    }

    function testNotAllowPlayesToEnterRaffleWhenRaffleIsNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // vm.warp is a cheatcode that adds or pass time in the blockchain
        vm.roll(block.number + 2); // vm.roll is a cheatcode that adds or pass blocks in the blockchain
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleIsNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    // CheckUpkeep function tests
    function testCheckUpKeepRevertWhenHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upKeepNeeded,) = raffle.checkUpKeep("");

        // Asssert
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseWhenRaffleStateIsClosed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        (bool upKeepNeeded,) = raffle.checkUpKeep("");

        // Assert
        assert(!upKeepNeeded);
    }
}
