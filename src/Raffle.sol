//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

contract Raffle {
    /* Errors */
    error Raffle__NotEnoughEthSent();

    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;

    /* Events */
    event RaffleEntered(address player);

    constructor(uint256 entranceFee, uint256 interval, uint256 lastTimeStamp) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = lastTimeStamp;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        // require(msg.value >= i_entranceFee, NotEnoughEthSent());
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    function pickWinner() public {
        if ((block.timestamp - s_lastTimeStamp > i_interval)) {
            revert();
        }
    }

    // Getters
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
