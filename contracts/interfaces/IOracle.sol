// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;
import "./IMatch.sol";


interface IOracle is IMatch {
    struct Side {
        uint256 id;
        Outcome outcome;
    }
    function requestOutcome(bytes32, Side[2] memory) external;
}