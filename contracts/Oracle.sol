// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import './libs/strings.sol';
import "./interfaces/IOracle.sol";
import "./interfaces/IMatch.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";


contract Oracle is IOracle, Ownable, ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using strings for *;

    uint256 constant REQUEST_TIME = 100;
    bytes32 constant CANCELED = '0x63616e63656c6564';

    address public nodeOracle; 
    bytes32 public jobId;
    uint256 public nodeFee;
    string public apiBase;
    string public path;
    string private apiToken;

    uint8 constant LOL_ID = 1;
    uint8 constant CS_ID = 3;
    uint8 constant DOTA_ID = 4;

    uint256 public liveness;
    uint256 public bond;


    IMatch matchContract;

     enum State {
        None,
        Requested,
        Proposed,
        Expired,
        Disputed,
        Resolved,
        Settled,
        Failed
    }

    // Struct representing a price request.
    struct Event {
        address disputer; // Address of the disputer.
        bool settled; // True if the request is settled.
        bool refundOnDispute; // True if the requester should be refunded their reward on dispute.
        bool callback;
        bool disputerIsRight; //todo: rename
        uint256 startRequest; //todo: rename
        Outcome oracle;
        Outcome proposedOutcome; // Outcome that the proposer submitted.
        Outcome resolvedOutcome; // Outcome resolved once the request is settled.
        Outcome disputerOutcome;
        uint256 expirationTime; // Time at which the request auto-settles without a dispute..
        State state;
        Side[2] sides;
        uint256 muchId;
        uint256 gameID;
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

     constructor(address _match, address _node, bytes32 _jobId, uint256 _nodeFee) {
        setPublicChainlinkToken();
        nodeOracle = _node;
        jobId = _jobId;
        nodeFee = _nodeFee; // (Varies by network and job)
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

    function getGameName(uint256 _gameId) internal pure returns(string memory) {
        if(_gameId == LOL_ID) return 'lol';
        if(_gameId == CS_ID) return 'csgo';
        if(_gameId == DOTA_ID) return 'dota2';
        return '';
    }

    function _getUrl(uint256 _gameId, uint256 _matchId) internal view returns(string memory) {
        strings.slice[] memory parts = new strings.slice[](6);
        parts[0] =  apiBase.toSlice();
        parts[1] = getGameName(_gameId).toSlice();
        parts[2] = '/matches?filter[id]='.toSlice();
        parts[3] = uint2str(_matchId).toSlice();
        parts[4] = '&token='.toSlice();
        parts[5] = apiToken.toSlice();
        return ''.toSlice().join(parts);
    }
    
    //To do onlyAdmin or operator
    function getDataApi(string memory path, bytes32 _hashMarket) external payable {
        //проверка на то, что маркет существует
        //Market storage market = markets[_hashMarket];
        //string memory url = generateUrl(path, market.gameId, market.matchId);
        //json(https://api.pandascore.co//matches/csgo/matches?filter[id]=598397&token=V8tUE0DEJ4Dew5QjhAi5tbgtUaoqSfFLk1padL2RAK1U0ED3B1Q).0.[winner_id, rescheduled]
        //bytes32 queryId = provable_query("URL", 'json(htts://api.pandascore.co/csgo/matches?filter[id]=598397&token=V8tUE0DEJ4Dew5QjhAi5tbgtUaoqSfFLk1padL2RAK1U0ED3B1Q).0.[winner_id, rescheduled, status]');
        //requests[queryId] = _hashMarket;
    }
    
    //  function split(string memory _string, uint256 _part) external view returns(string memory) {
    //     strings.slice memory s  = _string.toSlice();
    //     s.beyond("[".toSlice()).until("]".toSlice());
    //     strings.slice memory separator = ",".toSlice();
    //     string[] memory parts = new string[](s.count(separator) + 1);
    //     for(uint i = 0; i < parts.length; i++) {
    //         parts[i] = s.split(separator).toString();
    //     }
    //     return parts[_part]; 
    // }
    function proposeOutcome(bytes32 _event, Outcome _outcome) external onlyOwner {
        require(_outcome != Outcome.NONE);
        require(_getState(_event) == State.Requested, "proposeOutcome: isn't requested");
        Event storage e = events[_event];
        e.proposedOutcome = _outcome;
        e.expirationTime = block.timestamp + liveness;
        //@todo: block fee
    
    }

    function _callback(bytes32 _requestId, uint256 _teamId) public {
        Event storage e = events[requests[_requestId]];
        e.callback = true;
        if(_teamId == e.sides[0].id) e.disputerIsRight = e.sides[0].outcome == e.disputerOutcome;            
        if(_teamId == e.sides[1].id) e.disputerIsRight = e.sides[1].outcome == e.disputerOutcome;  
         
    }
    function _callback(bytes32 _requestId, bool _draw) public {
        Event storage e = events[requests[_requestId]];
        e.callback = true;
        e.disputerIsRight = _draw;
    }
    function _callback(bytes32 _requestId, bytes32 _status) public {
        Event storage e = events[requests[_requestId]];
        e.callback = true;
        e.disputerIsRight = _status == CANCELED;
    }

    
    //disputeOutcome
    function openDispute(bytes32 _event, Outcome _outcome) external payable {
        require(_outcome != Outcome.NONE);
        require(msg.value >= bond);
        require(
            _getState(_event) == State.Proposed,
            "openDispute: isn't proposed"
        );
        Event storage e = events[_event];
        require(_outcome != e.proposedOutcome);
        //check whether the sender will be able to pay fee
        //run the request
        bytes32 requestId;
        if(_outcome == Outcome.REVERT){
            requestId = _makeRequest(e.gameID, e.muchId, jobId, bytes4(keccak256("_callback(bytes32,bytes32)")), path);
        }else if(_outcome == Outcome.DRAW){
            requestId = _makeRequest(e.gameID, e.muchId, jobId, bytes4(keccak256("_callback(bytes32,bool)")), path);
        } else{
            requestId = _makeRequest(e.gameID, e.muchId, jobId, bytes4(keccak256("_callback(bytes32,uint256)")), path);
        }   
       requests[requestId] = _event;
    }

    
    function _makeRequest(
        uint256 _gameId, 
        uint256 _matchId, 
        bytes32 _job, 
        bytes4 _selector, 
        string memory _path) internal returns (bytes32) {
        Chainlink.Request memory request = buildChainlinkRequest(
            _job, 
            address(this),
            _selector
        );
        
        // Set the URL to perform the GET request on
        request.add("get", _getUrl(_gameId, _matchId));
        request.add("path", _path);
        return sendChainlinkRequestTo(nodeOracle, request, nodeFee);
    }
    
    function settleDispute(bytes32 _event) external {
        Event storage e = events[_event];
        e.settled = true;
        //can open dispute on Draw Outcome 1 and Outcome 2

        // if timeTx > 100 сек
        //Outcome != set Outcome ? Outcome == OracleOutcome
        //

        //bool disputeSuccess = .resolvedPrice != request.proposedPrice;
        //uint256 bond = request.bond;

    }
    function _checkOutcome(uint256 _teamId, Side[2] memory _sides) internal returns(Outcome) {
        _teamId == _sides[0].id ? _sides[0].outcome : _teamId == _sides[1].id ? _sides[1].outcome : Outcome.REVERT;
    }
    function requestOutcome(bytes32 _event, Side[2] memory _sides) external override onlyMatch {
        //TODO: check that the event does not exist yet 
        Event storage e = events[_event];
        e.state = State.Requested;
        //e.sides = _sides;
        //Requested = true;
    }


    function hasOutcome(bytes32 _event) external returns(bool) {
        State state = _getState(_event);
        return state == State.Settled || state == State.Resolved || state == State.Expired;
    }

    function getUrl() external {

    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0){
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0){
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
    function _getState(
        bytes32 _event
    ) internal view returns (State) {
        Event storage e = events[_event];
        if (e.muchId == 0) {
            return State.None;
        }
        if (e.proposedOutcome != Outcome.NONE) {
            return State.Requested;
        }
        if (e.settled) {
            return State.Settled;
        }
        if (e.disputer == address(0)) {
            return e.expirationTime <= block.timestamp ? State.Expired : State.Proposed;
        }
        if(!e.callback){
            return (e.startRequest + REQUEST_TIME) <= block.timestamp ? State.Failed : State.Disputed;
        }
        return State.Resolved;
    }

} 