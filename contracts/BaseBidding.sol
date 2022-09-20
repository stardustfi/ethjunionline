// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//import "/contracts/mainliquidations.sol";

interface ILan {
    struct Loan {
        address owner;
        address token;
        address operator;
        address oracleAddress;
        address collectionAddress;
        uint256 apr;
        uint256 nftId;
        uint256 startTime;
        uint256 endTime;
        uint256 numBids;
        // True if liquidatable, False if not
        bool liquidatable;
        // True if whitelisted mode on, False if not
        bool whitelisted;
    }
    function bid(
        uint256 _poolId,
        uint256 _amount,
        uint256 _apr,
        uint16 _ltv
    ) external;

    function liquidate(uint256 _poolId) external;
    
    function getLoan(uint256 _poolId) external view returns(
        address owner, 
        address token, 
        address operator,
        address oracleAddress,        
        address collectionAddress, 
        uint256 apr, 
        uint256 nftId, 
        uint256 startTime, 
        uint256 endTime, 
        uint256 numBids,
        bool liquidatable,
        bool whitelisted) ;
    
}

abstract contract BaseBidding {
    using Math for uint256;
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
    ILan public immutable LAN;
    // Can't figure out how to resolve this error
    bool public liquidationOnly;
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
    /// @notice Only Admin can operate
    modifier onlyOwner(){
        require(msg.sender == admin, "BaseBid: not owner");
        _;
    }
    /// @notice If shutdown is true, then the pool stops issuing new loans.
    modifier shutdown(){
        require(windDown == false, "BaseBid: shutdown");
        _;
    }

     constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        address _LANContract,
        bool _liquidationOnly,
        uint16 _minAPR,
        uint256 _longestTerm,
        uint256 _adminFee
    ) {
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LAN = ILan(_LANContract);
        liquidationOnly = _liquidationOnly;
        minAPR = _minAPR;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
    }

    /// @notice Deposit
    /// @param _tokenAmount is amount deposited    
    function deposit(uint256 _tokenAmount) public virtual {}
    
    /// @notice Withdraw
    /// @param _tokenAmount is amount withdrawn 
    function withdraw(uint256 _tokenAmount) public virtual onlyOwner(){}

    /// @notice Add whitelist asset to vault
    /// @param _token is token address
    /// @param _LTV is the LTV of the asset
    /// @param _oracle is the oracle that will be queried. Oracle should implement IPriceOracle
    function addWhitelist(address _token, uint256 _LTV, address _oracle) public virtual onlyOwner(){}
    

    /// @notice Liquidate Auction if the auction can be liquidated.
    /// @param _poolId The pool ID
    function liquidateAuction(uint256 _poolId) public virtual {}

    /// @notice Call the LAN contract and make a bid with specific parameters. LTV is determined inclusive of accrued interest.
    /// Update utilization when the loan is issued.
    /// @param _poolId The pool ID
    /// @param _borrowAmount The amount requested to borrow
    /// @param _apr The APR for the borrow
    function bidWithParams(uint256 _poolId, uint256 _borrowAmount, uint256 _apr) public virtual {}

    function automaticBid(uint256 _poolId) public virtual {}
    
    function pause() external virtual onlyOwner() {}

    /// @notice Sum the value of whitelisted assets contained in the NFT wrapper. Nonwhitelisted assets are 0.
    /// @param _poolId The pool ID
    function _calculateLTV(uint256 _poolId) internal virtual{}

    /// @notice Sum the value of whitelisted assets contained in the NFT wrapper. Nonwhitelisted assets are 0.
    /// @param _presentValue The loan amount
    /// @param _apr The APR of the loan
    /// @return futurevalue The final accrued value of the loan
    function _calculateLoanValue(uint256 _presentValue, uint256 _apr, uint256 _timeElapsed) public pure virtual returns(uint256) {
        return
            _presentValue +
            _presentValue.mulDiv(_apr, 10e18).mulDiv(_timeElapsed, SECONDS_IN_ONE_YEAR);

    }
     
    /// @notice Read LAN for Loan details
    /// @param _poolId The pool ID
    function readLoan(uint256 _poolId) view virtual external returns(
        address owner, 
        address token, 
        address operator,
        address oracleAddress,        
        address collectionAddress, 
        uint256 apr, 
        uint256 nftId, 
        uint256 startTime, 
        uint256 endTime, 
        uint256 numBids,
        bool liquidatable,
        bool whitelisted) 
        {
        return(LAN.getLoan(_poolId));
        //not sure how to read a struct through a mapping from another contract without inheritance
    }
}