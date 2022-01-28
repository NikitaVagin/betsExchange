// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import './libs/strings.sol';
import "./interfaces/IOracle.sol";
import "./interfaces/IMatch.sol";
import "hardhat/console.sol";

contract Match is IMatch {
    struct Side {
        uint256 id;
        Outcome outcome;
    }

    using strings for *;
    
    uint256 constant PCT_BASE = 1 ether;
    string constant STATUS_FINISHED = 'finished';
    string constant STATUS_CANCELED = 'canceled';
    string constant STATUS_NOT_STARTED = 'canceled';

    event CreateMarket (bytes32 indexed hashMarket);
    event CreateOffer (bytes32 indexed hashOffer);

    enum Status {
        PENDING,   
        UNDERWAY,         
        DECIDED,
        CANCELED,
        MOOT    
    }
    enum Stake {BACK, LAY}

    // PENDING - match has not been fought to decision
    // UNDERWAY - match has started & is underway
    // DRAW - anything other than a clear winner (e.g. cancelled)
    // DECIDED index of participant who is the winner 

    struct BetTaker {
        address taker;
        uint256 userID;
        uint256 userTips;
        Stake stake;
    }

    //inside library? 
    struct BetOffer {
        address creator;
        uint256[2] amounts; // 0 == Back 1 == lay
        address[2] lastStakers; // 0 == Back, 1 == lay
        uint256 rate; //Do it need a library for decimals 
        uint256 matched; //amount of matched
        uint256 minAmount;
        address lastStaker;
        uint256 takeCount;
        uint256 settleCount;
        Outcome outcome; //Is this necessary?
        uint256 winnerID;
        bytes32 offerHash;

    }

    struct Market {
        uint256 startTime;
        uint256  matchId;
        uint256 leagueId;
        uint256 offerCount;
        uint256 settleCount;
        uint256 claimedOffer; 
        uint8 gameId; //CS DOTA etc
        string matchResult;
        bytes32 marketHash;
        bytes32[] offers;
        Side[2] sides;
        Outcome outcome;
        Status status;
    }
    
    IOracle oracle;
    string private apiToken;
    string private urlApiBase;
    string public test;
    uint public price;
    bytes32 public test2;

    // hash bet => claimed
    mapping(bytes32 => bool) internal unclaimed;

    mapping(bytes32 => mapping(uint256 => BetTaker)) takers;
    //marketHash => marketHash => BetOffer
    mapping(bytes32 => mapping(bytes32 => BetOffer)) offers;
    //hash:market, offer or bet 
    mapping(bytes32 => bool) exist;
    
    //hash:market, offer or bet  => count;
    mapping(bytes32 => uint256) a;


    mapping(bytes32 => Market) public markets;
    //request hash => market;
    mapping(bytes32 => bytes32) requests;
    // User balances
    mapping (address => uint256) public totalBalances;
    //user => betOffer => prediction => balance
    mapping(address => mapping(bytes32 => mapping(Stake => uint256))) balanceForStake;
    mapping(address => mapping(bytes32 => uint256)) totalBalanceForOffer;
    mapping(address => mapping(bytes32 => bool)) claimOffer;
    mapping(address => bytes32[]) offersByUser;
    mapping(bytes32 => uint256) indexOfOffers;

    constructor(string memory _matchId, string memory _test) public {
        //add urlApiBase and 
        //do request to factory to know api base
        test = _test;
        //matchId = _matchId;
        urlApiBase = 'https://api.pandascore.co//matches/';
        apiToken = 'V8tUE0DEJ4Dew5QjhAi5tbgtUaoqSfFLk1padL2RAK1U0ED3B1Q';
        

    }
    fallback() external payable {}

    // modifier enoughEth {
    //     require(provable_getPrice('URL') < address(this).balance, 'not enough eth for request');
    //     _;
    // }
    
    function stringToUint(string memory _s) external pure returns(uint _return)   {
        //_return = parseInt(_s);
    }
    
   function submitOffer(Outcome _outcome, uint256 _rate, uint256 _minAmount, bytes32 _market) external payable{
        address sender = msg.sender;
        uint256 value = msg.value; 
        require(exist[_market], 'there is no such market');
        require(value > 0 && value >= _minAmount);
        bytes32 offerHash = offerHash(_outcome, _rate, _minAmount, _market, sender);
        require(!exist[offerHash], 'offer already exists');
        //checks rate (not great than)
        //checks minAmount
        Market storage market = markets[_market];
        exist[offerHash] = true;
        indexOfOffers[offerHash] = market.offers.length;
        market.offers.push(offerHash);
        BetOffer storage offer = offers[_market][offerHash];
        market.offerCount++;
        offer.minAmount = _minAmount;
        offer.creator = sender;
        offer.rate = _rate;
        offer.amounts[uint8(Stake.BACK)] = value;
        balanceForStake[sender][offerHash][Stake.BACK] += value;
        offer.outcome = _outcome;
        offer.offerHash = offerHash;
        _addOffer(msg.sender, offerHash);
        emit CreateOffer(offerHash);
   }

    function submitTake(Stake _stake, bytes32 _market, bytes32 _offer) external payable {
        address sender = msg.sender;
        uint256 value = msg.value;
        require(exist[_market] && exist[_offer], 'not exist');
        uint256 i = indexOfOffers[_offer];
        BetOffer storage o = offers[_market][markets[_market].offers[i]];
        require(_canTake(_stake, o.amounts), 'Cant submit take');
        uint8 st = uint8(_stake);
        uint8 op = uint8(_stake == Stake.BACK ? Stake.LAY : Stake.BACK);
        o.amounts[uint8(_stake)] += msg.value;
        o.matched = o.amounts[st] <= o.amounts[op] ? o.amounts[st] : o.amounts[op]; 
        o.takeCount +=1;
        _addOffer(msg.sender, _offer);
        //takers[_offer][o.takeCount] = BetTaker(msg.sender, _userID, msg.value, _stake);
        balanceForStake[sender][_offer][_stake] += value;
        //should be made emit
    }
    //оптимизировать
    function _canTake(Stake _stake, uint256[2] memory _amounts) internal pure returns(bool){
        if(_stake == Stake.BACK){
            return _amounts[uint8(Stake.BACK)] <= _amounts[uint8(Stake.LAY)] ? true : false;
        }
        return _amounts[uint8(Stake.LAY)] <= _amounts[uint8(Stake.BACK)] ? true : false;
    }

    function _difference(uint256[2] memory _amounts) internal pure returns(uint256[2] memory diff) {
        if(_amounts[0] > _amounts[1]){
            diff[0] = (_amounts[0] - _amounts[1]);
        }else {
            diff[1] = (_amounts[1] - _amounts[0]);
        }
    }

    // function _difference2(uint256[2] memory _amounts) internal pure returns(uint256) {
    //     if(_amounts[0] > _amounts[1]){
    //         return 
    //     }else {
    //         diff[1] = (_amounts[1] - _amounts[0]);
    //     }
    // }

    function _validateOffer(BetOffer memory _b) internal view {
         require(msg.sender == _b.creator, "Bet is not permitted for the msg.sender to take");
    }

    function marketHash (Market memory _m) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked('market', _m.matchId, _m.gameId, _m.leagueId));
    }

    function offerHash(Outcome _outcome, uint256 _rate, uint _minAmount, bytes32 _market, address _creator) internal pure returns(bytes32){
        //finish it
        return keccak256(abi.encodePacked('offer', _market, _outcome, _rate, _minAmount, _creator));

    }
    //It is necessary to finish this
    function takeHash(address _taker, bytes32 _offerHash) internal pure returns (bytes32){
        return keccak256(abi.encodePacked('take', _taker, _offerHash));

    }

   function changeBetRate(uint betId) external {

    }

    function compareStrings(string memory _a, string memory _b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((_a))) == keccak256(abi.encodePacked((_b))));
    }
    //onlyAdmin
   function createMarket(Market memory _m) external {
        bytes32 hashM = marketHash(_m);
        require(markets[hashM].marketHash[0]== 0, 'Market already exists');
        //_validateSides(_m.sides);
        _m.marketHash = hashM;
        //TODO: Copying of type struct memory to storage not yet supported. 
        //markets[hashM] = _m;
        //oracle.requestOutcome(hashM, _m.sides);
        emit CreateMarket(hashM);
   }

   function settleMarket(uint256 _betId, Outcome _variant, uint256 _amount) external {

   }

   function _validateSides(Side[2] memory _sides) internal pure {
       require(_sides[0].id != _sides[1].id, 'identical team ids');
       require(uint8(_sides[0].outcome) > 0 && uint8(_sides[1].outcome) > 0);
   }

    function claimAll() external {

    }
    function _addOffer(address _address, bytes32 _offer) internal {
        indexOfOffers[_offer] = offersByUser[_address].length;
        offersByUser[_address].push(_offer);
    }

    function _deleteOffer(address _address, bytes32 _offer) internal {
        bytes32[] storage o = offersByUser[_address];
        o[indexOfOffers[_offer]] = o[o.length - 1];
        indexOfOffers[o[o.length - 1]] = indexOfOffers[_offer];
        o.pop();
        delete indexOfOffers[_offer];
    }
   function claimByOffer(bytes32 _market, bytes32 _offer) external {
       require(exist[_offer]);// offer is exist
       require(totalBalanceForOffer[msg.sender][_offer] > 0, 'Caller has not placed any bet');
       require(!claimOffer[msg.sender][_offer], 'The offer is already claim');
       Market storage m = markets[_market];
       BetOffer storage o = offers[_market][_offer];
       require(uint8(m.status) > 1, 'incorrect time for claim');
       uint256 payout;
       uint256[2] memory diff;
       if(m.status == Status.DECIDED){
           if(o.lastStaker == msg.sender && o.amounts[0] != o.amounts[1]){
            diff = _difference(o.amounts);
            payout += diff[0] > 0 ? diff[0] : diff[1];
            }
           if(m.outcome == o.outcome && balanceForStake[msg.sender][_offer][Stake.BACK] > 0){
                uint256 bet = (balanceForStake[msg.sender][_offer][Stake.BACK] - diff[0]);
                payout += (bet * o.rate) / PCT_BASE;
           }else if(balanceForStake[msg.sender][_offer][Stake.LAY] > 0){
               uint256 bet = (balanceForStake[msg.sender][_offer][Stake.LAY] -  diff[1]);
               payout += (bet * ((o.rate * PCT_BASE) / (o.rate - PCT_BASE))) / PCT_BASE;
           }

       } else {
           payout = totalBalanceForOffer[msg.sender][_offer];
       }
        require(payout > 0,"payout amount should be > 0");
        claimOffer[msg.sender][_offer] = true;
        _deleteOffer(msg.sender, _offer);
        (bool success, ) = msg.sender.call{value:payout}("");
        require(success);
        //Event
   }

   function _validateMarket(Market memory _m) internal {
    //validate passed struct;
   }
}

