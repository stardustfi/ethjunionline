// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

abstract contract BaseBidding {
    event newLoan(
        address collectionAddress,
        uint16 apr,
        uint256 poolId,
        uint256 bidAmount
    );

    event log(string reason);
    address public immutable admin;
    address public immutable baseAsset;
    address public immutable baseAssetOracle;
    address public immutable LANcontracts;
    bool public windDown;
    uint256 public minAPR;
    uint256 public longestTerm;
    uint256 public immutable adminFee;
    uint256 private constant SECONDS_IN_ONE_YEAR = 60*60*24*365;

    struct Term {
            uint256 poolId;
            uint256 LTV;
            address oracle;
    }

    modifier onlyOwner(){
        require(msg.sender == admin, "BaseBid: not owner");
        _;
    }
    modifier shutdown(){
        require(windDown == false, "BaseBid: shutdown");
        _;
    }

     constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        address _LANContract,
        uint16 _minAPR,
        uint256 _longestTerm,
        uint256 _adminFee
    ) {
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LANcontracts = _LANContract;
        minAPR = _minAPR;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
    }
    
    function deposit(uint256 _tokenAmount) public virtual {}

    function withdraw(uint256 _tokenAmount) public virtual onlyOwner(){}

    function addWhitelist(address _token, uint256 _LTV, address _oracle) public virtual onlyOwner(){
        whitelists[_token] = Term({
            LTV: _LTV,
            oracle: _oracle
        });
    }
    
    function liquidateAuction(uint256 _poolId) public virtual {}

    function bidWithParams(uint256 _poolId, uint256 _borrowAmount, uint256 _apr) public virtual {}

    function automaticBid(uint256 _poolId) public virtual {}
    
    function pause() external virtual onlyOwner() {}
    
    function _calculateLTV(uint256 _poolId) internal virtual{}

    function _calculateLoanValue(uint256 _presentValue, uint256 _apr, uint256 _timeElapsed) public pure virtual returns(uint256) {
        return _presentValue + _presentValue * _apr / 10 ** 18 * _timeElapsed / SECONDS_IN_ONE_YEAR;
    }
    
    function readLoan(uint256 _poolId) view virtual external returns(
        address owner, 
        address token, 
        address operator,
        address oracleAddress;        
        address collectionAddress, 
        uint256 nftId, 
        uint256 startTime, 
        uint256 endTime, 
        uint256 apr, 
        uint256 numBids,
        bool liquidatable,
        bool whitelisted) 
        {
        return(Lan.loans(_poolId));
    }
}