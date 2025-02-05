//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {ChainConstants} from "../../script/HelperConfig.s.sol";

contract RaffleTest is ChainConstants, Test {
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

    modifier enterRaffle() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

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
        assertEq(
            uint256(raffle.getRaffleState()),
            uint256(Raffle.RaffleState.OPEN)
        );
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
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");

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
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(!upKeepNeeded);
    }

    // Perform Up Keep tests

    function testPerformUpKeepRevertsWhenUpKeepNotNeeded() public enterRaffle {
        // Act/Assert
        raffle.performUpkeep("");
    }

    function testPerformUpKeepRevertsWhenIfCheckUpKeepFalse() public {
        // Arrage
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance += entranceFee;
        numPlayers += 1;

        // Act/Asert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__upKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpKeepRaffleStateEmitsRequestId() public enterRaffle {
        // Act
        vm.recordLogs(); // vm.recordLogs is a cheatCode for recording logs that will emit in any function call
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Vm.Log will return array of different emit and vm.getRecordedLogs will give every recoreded logs!
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    // fullFillRandomWords function tests
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }
    function testFullFillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(
        uint256 randomRequestId
    ) public skipFork enterRaffle {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testfulFillRandomWrodsPicksAWinnerSendMoneyResetTheLottery()
        public
        skipFork
        enterRaffle
    {
        // Arrange
        uint256 additionalPlayers = 3; // total 4
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalPlayers;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState rState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalPlayers + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(rState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
