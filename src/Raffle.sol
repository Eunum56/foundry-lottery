//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailer();
    error Raffle__RaffleIsNotOpen();
    error Raffle__upKeepNotNeeded(uint256 balance, uint256 playersLength, RaffleState lotteryState);

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CLOSED
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event RaffleWinner(address indexed winner);
    event RaffleRequestIdWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint32 callBackGasLimit,
        uint256 subscriptionId
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callBackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        // require(msg.value >= i_entranceFee, NotEnoughEthSent());
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleIsNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }
    // Time interval has passed
    // Raffle is open
    // At least one player has entered
    // Implicitly, your subcription has LINK

    function checkUpKeep(bytes memory /* callData */ )
        public
        view
        returns (bool upKeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = timeHasPassed && raffleIsOpen && hasBalance && hasPlayers;
        return (upKeepNeeded, "");
    }

    // 1 Get a random number.
    // 2 Pick a winner.
    // 3 Transfer the prize to the winner.
    // 4 Reset the players array.
    // 5 Reset the lottery timestamp.
    function performUpkeep(bytes calldata /* performData */ ) public {
        // check to see if enough time has passed
        (bool upKeepNeeded,) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__upKeepNotNeeded(address(this).balance, s_players.length, s_raffleState);
        }
        s_raffleState = RaffleState.CLOSED;
        // Getting a random number from chainlink VRF
        // uint256 requestId =
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        emit RaffleRequestIdWinner(requestId);
    }

    //! This function will follow CEI pattern
    //! which stands for Checks, Effects, and Interactions
    function fulfillRandomWords(
        uint256,
        /*requestId*/
        uint256[] calldata randomWords
    ) internal override {
        //! Checks (conditionals statements)

        //! Effects (changing the state variables)
        // random number
        uint256 randomNumber = randomWords[0] % s_players.length;
        address payable winner = s_players[randomNumber];
        s_recentWinner = winner;

        // reset the players array and the lottery timestamp
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        //! Interactions (calling other contracts)
        // transfer the prize to the winner
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) revert Raffle__TransferFailer();
        emit RaffleWinner(winner);
    }

    // Getters
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
