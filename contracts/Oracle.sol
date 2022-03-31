// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IOptimisticOracle } from "./interfaces/IOptimisticOracle.sol";
import { IUmaFinder } from "./interfaces/IUmaFinder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IOracle.sol";
import "./interfaces/IMatch.sol";


contract Oracle is IOracle, Ownable {

    uint256 constant REQUEST_TIME = 100;
    bytes32 public constant IDENTIFIER = "YES_OR_NO_QUERY";

    /// @notice UMA Finder address
    address public umaFinder;

    uint256 public liveness;
    uint256 public pledge;
    uint256 public blockAmount;
    uint256 public availableAmount;

      struct QuestionData {
        // Unix timestamp(in seconds) at which a market can be resolved
        uint256 resolutionTime;
        // Reward offered to a successful proposer
        uint256 reward;
        // Additional bond required by Optimistic oracle proposers and disputers
        uint256 proposalBond;
        // Flag marking the block number when a question was settled
        uint256 settled;
        // Request timestmap, set when a request is made to the Optimistic Oracle
        uint256 requestTimestamp;
        // Admin Resolution timestamp, set when a market is flagged for admin resolution
        uint256 adminResolutionTimestamp;
        // Flag marking whether a question can be resolved early
        bool earlyResolutionEnabled;
        // Flag marking whether a question is resolved
        bool resolved;
        // Flag marking whether a question is paused
        bool paused;
        // ERC20 token address used for payment of rewards, proposal bonds and fees
        address rewardToken;
        // Data used to resolve a condition
        bytes ancillaryData;
    }



    IMatch matchContract;

     enum State {
        None,
        Requested,
        ProposedOrExpired,
        Expired,
        Disputed,
        Resolved,
        Settled
    }

    // Struct representing a price request.
    struct Event {
        uint256 estimatedStartTime;
        uint256 resolutionTime;
        uint256 reward;
        uint256 proposalBond;
        uint256 settled;
        address disputer;
        uint256 requestTimestamp;
        uint256 proposedTimestamp;
        bool refundOnDispute; // True if the requester should be refunded their reward on dispute.
        Outcome proposedOutcome; // Outcome that the proposer submitted.
        Outcome disputerOutcome;
        uint256 expirationTime; // Time at which the request auto-settles without a dispute..
        address rewardToken;
        Side[2] sides;
    }

    mapping(bytes32 => Event) private events;
    mapping(bytes32 => bytes32) requests;

    //TODO: create the request struct
    //mapping(bytes32 => Market) public requests;

    //event SetOutcome(bytes32 marketHash, LibOutcome.Outcome outcome);

     //TODO: add set func for it


     // Struct representing the state of a price request.
     // Never requested.
     // Proposed, but not expired or disputed yet
     // Proposed, not disputed, past liveness.
     // Disputed, but no Node Outcome returned yet.
     // Disputed and Outcome result is available.
     // Final Outcome been set in the contract (can get here from Expired or Resolved).

     constructor(address _match) {
        matchContract = IMatch(_match);
    }
    modifier onlyMatch() {
        require(msg.sender == address(matchContract), 'Oracle: caller is not the match contract');
        _;
    }
   
   function getOutcome() external {

   }

    // modifier notAlreadySet(bytes32 marketHash) {
    //     require(
    //         reportTime[marketHash] == 0,
    //         "MARKET_ALREADY_SETTLE"
    //     );
    //     _;
    // }
 

    
    function proposeOutcome(bytes32 _event, Outcome _outcome) external onlyOwner {
        require(events[_event].resolutionTime > 0, "proposeOutcome: isn't requested");
        Event storage e = events[_event];
        e.proposedOutcome = _outcome;
        e.expirationTime = block.timestamp + liveness;
    
    }

    //disputeOutcome
    function _returnQuestion(Outcome _outcome, Side[2] memory _sides) public pure returns(bytes memory){
            if(_outcome == Outcome.OUTCOME_ONE){
                bool isFirst = _sides[0].outcome == Outcome.OUTCOME_ONE;
                return bytes(abi.encodePacked("Did the the", isFirst ? _sides[0].name : _sides[1].name, 'beat the', isFirst ? _sides[1].name : _sides[0].name, 'January 6th, 2022?'));

            }else if(_outcome == Outcome.OUTCOME_TWO){
                bool isFirst = _sides[0].outcome == Outcome.OUTCOME_ONE;
                return bytes(abi.encodePacked("Did the the", isFirst ? _sides[0].name : _sides[1].name, 'beat the', isFirst ? _sides[1].name : _sides[0].name, 'January 6th, 2022?'));
            }else {
                return bytes(abi.encodePacked("Did the ", _sides[0].name, 'draw VS the', _sides[1].name , 'January 6th, 2022?'));
            }
    }


    function openDispute(bytes32 _event, Outcome _outcome) external {
        Event memory e = events[_event];
        require(
            _getState(_event) == State.ProposedOrExpired,
            "openDispute: isn't proposed"
        );
        require(_outcome != e.proposedOutcome);
        bytes memory question = _returnQuestion(_outcome, e.sides);
        if(_outcome == Outcome.OUTCOME_ONE){
            
        }else if(_outcome == Outcome.OUTCOME_ONE){

        }
        _requestPrice(
            msg.sender,
            IDENTIFIER,
            block.timestamp,
            question,
            e.rewardToken,
            e.reward,
            e.proposalBond

        );
       //requests[requestId] = _event;
    }

    /// @notice Request a price from the Optimistic Oracle
    /// @dev Transfers reward token from the requestor if non-zero reward is specified
    function _requestPrice(
        address requestor,
        bytes32 priceIdentifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 bond
    ) internal {
        // Fetch the optimistic oracle
        IOptimisticOracle optimisticOracle = getOptimisticOracle();

        // If non-zero reward, pay for the price request by transferring rewardToken from the requestor
        if (reward > 0) {
            //TransferHelper.safeTransferFrom(rewardToken, requestor, address(this), reward);

            // Approve the OO to transfer the reward token from the Adapter
            if (IERC20(rewardToken).allowance(address(this), address(optimisticOracle)) < type(uint256).max) {
                //TransferHelper.safeApprove(rewardToken, address(optimisticOracle), type(uint256).max);
            }
        }

        // Send a price request to the Optimistic oracle
        optimisticOracle.requestPrice(priceIdentifier, timestamp, ancillaryData, IERC20(rewardToken), reward);

        // Update the proposal bond on the Optimistic oracle if necessary
        if (bond > 0) {
            optimisticOracle.setBond(priceIdentifier, timestamp, ancillaryData, bond);
        }
    }


    
    function settleDispute(bytes32 _event) external {
        State state = _getState(_event);
        Event storage e = events[_event];
        //e.settled = true;
        blockAmount -= pledge;
        // if(state == State.Failed){
        //     //compensation for open dispute
        //     uint256 penalty = ((pledge * 1e16) / 1e18);
        //     availableAmount += pledge - penalty;
        //     (bool success, ) = e.disputer.call{value: pledge + penalty}("");
        //     require(success); 
        // } else if(state == State.Resolved) {
        //     if(e.disputerIsRight){
        //         (bool success, ) = e.disputer.call{value: pledge * 2}("");
        //         require(success);
        //     }else {
        //         availableAmount += pledge * 2;
        //     }
        // } else {
        //     revert("settleDispute: not settleable");
        // }
        //@todo: Event

    }

    //@TODO: add an event
    function initializeEvent(
        bytes32 _event, 
        Side[2] memory _sides,
        uint256 _estimatedStartTime
        ) external override onlyMatch {
        require(!(events[_event].estimatedStartTime > 0), "Adapter::initializeQuestion: Question already initialized");
        require(_estimatedStartTime > 0, "Adapter::initializeQuestion: resolutionTime must be positive");
        Event storage e = events[_event];
        e.sides[0] = _sides[0];
        e.sides[1] = _sides[1];
        e.estimatedStartTime = _estimatedStartTime;
    }

    function hasResult(bytes32 _event) public override returns(bool){

    }


    function getOutcome(bytes32 _event) external view returns(Outcome) {
        //require(hasOutcome(_event), "getOutcome:Event hasn't outcome");
        State state = _getState(_event);
        Event storage e = events[_event];
        // if(state == State.Expired){
        //     return e.proposedOutcome;
        // } else {
        //     return e.disputerIsRight ? e.disputerOutcome : e.proposedOutcome;
        // }

    }

    function hasOutcome(bytes32 _event) public returns(bool) {
        State state = _getState(_event);
        return state == State.Resolved || state == State.Expired;
    }

    function getOptimisticOracleAddress() internal view returns (address) {
        return IUmaFinder(umaFinder).getImplementationAddress("OptimisticOracle");
    }

    function getOptimisticOracle() internal view returns (IOptimisticOracle) {
        return IOptimisticOracle(getOptimisticOracleAddress());
    }


    
    function _getState(
        bytes32 _event
    ) internal view returns (State) {
        Event storage e = events[_event];
        if(e.estimatedStartTime == 0){
            return State.None;
        }
        // if(e.proposedTimestamp != 0){
        //     return;
        // }
    }
} 