// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;
import "./IMatch.sol";


interface IOracle is IMatch {
    struct Side {
        uint256 id;
        bytes name;
        Outcome outcome;
    }
    // struct Offer {
        
    // }
    function initializeEvent(bytes32, Side[2] memory, uint256) external;

    function hasResult(bytes32) external returns (bool);
}