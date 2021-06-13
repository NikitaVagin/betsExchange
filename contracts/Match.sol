// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import './libs/strings.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract Match {
    using strings for *;
    using SafeMath for uint256;
    
    struct UserBet {
    uint256 userID;
    uint256 userTip;
    }

    struct Bet {
        uint256 amountBack;
        uint256 amountLay;
        mapping(address => UserBet) bets;
        uint256 idBet; // do it need a has? 
        uint256 rate; //Do it need a library for decimals 
        uint256 matched; //
    }

    mapping (uint => Bet) userBets;
    uint256 public startTime;
    constructor(uint256 _startTime){

    }
        
}

