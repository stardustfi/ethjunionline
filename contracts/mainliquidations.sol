// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "IPriceOracle.sol";

/// @title LAN: unopinianated lending infrastructure for literally any nft
/// @author William, Junion, Austin
/// @notice Code is really rough and likely contains bugs :)
interface IPriceOracle {
    uint256 price;
}

contract LAN{

    event newPool(
        uint256 indexed poolId,
        address collectionAddress,
        uint256 nftId
    );
    event loanCancelled(uint256 Id);

    event loanEnded(
        uint256 poolId
    )
    ///
    uint256 public count;


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

    mapping(uint256 => Loan) public loans;

    struct Bid {
        uint256 bidTime;
        uint256 bidAmount;
        address user;
        uint256 apr;
        uint16 ltv;
    }

    /// @notice Mapping from PoolID => Bid Number => Bid. Keep track of bids
    mapping(uint256 => mapping(uint256 => Bid)) public bids;

    /// @notice Mapping from PoolID => Bidder Address => bool. True = Whitelisted, False = not. Wh
    mapping(uint256 => mapping(address => bool)) public whitelistedAddresses;

    /// @notice Mapping from PoolID => User Funds. Tracks repayments from users. Funds aren't transferred to the borrower, but are kept.
    mapping(uint256 => uint256) public userPoolReserve;

    uint256 private constant SECONDS_IN_ONE_YEAR = 60*60*24*365;


    modifier onlyOwner(uint256 _poolId){
        require((loans[_poolId].owner == msg.sender)
        ||(loans[_poolId].operator == msg.sender), "LAN: not owner");
        _;
    }


    function launch(
        address _operator, 
        address _token, 
        address _collectionAddress, 
        address _oracleAddress,
        uint256 _nftId, 
        uint256 _startTime, 
        uint256 _endTime, 
        bool _liquidatable,
        bool _whitelisted) public {
        require(_startTime >= block.timestamp, "LAN: start time in past");
        require(_endTime > _startTime, "LAN: start after end");
        loans[count] = Loan({
            owner: IERC721(_collectionAddress).ownerOf(_nftId),
            operator: _operator,
            //operator can be msg.sender or address(0) if operator role isn't used
            token: _token,
            collectionAddress: _collectionAddress,
            oracleAddress: _oracleAddress,
            nftId: _nftId,
            startTime: _startTime,
            endTime: _endTime,
            apr: 0,
            numBids: 0,
            liquidatable = _liquidatable,
            whitelisted: _whitelisted
        });
        bids[count][0].bidTime = block.timestamp;
        emit newPool(count, _collectionAddress, _nftId);
        count++;
    }

    function bid(uint256 _poolId, uint256 _amount, uint256 _apr, uint16 _ltv) external {
        require(_started(_poolId), "LAN: not started");
        require(!_ended(_poolId), "LAN: already ended");
        Loan storage loan = loans[_poolId];
        // check if whitelisted
        require((loan.whitelisted) && (whitelistedAddresses[_poolId][msg.sender])
         || (loan.whitelisted == false), "LAN: Not Whitelisted");
        // check latest top bid
        uint currentTopBid = bids[_poolId][loan.numBids].bidAmount;
        require(_amount > currentTopBid, "LAN: bid not higher");
        uint loanValue = _calculateLoanValue(_poolId);
        // update with new APR
        loan.apr = _apr;
        // increment bids by 1
        uint256 numBids = loan.numBids + 1;
        // send tokens to previous bidder
        IERC20(loan.token).transferFrom(msg.sender, bids[_poolId][numBids].user, loanValue);
        
        // send tokens to owner
        IERC20(loan.token).transferFrom(msg.sender, loan.owner, _amount - loanValue);
        // record data
        loan.numBids = numBids;
        bids[_poolId][numBids] = Bid({
            bidTime: block.timestamp,
            bidAmount: _amount,
            user: msg.sender,
            apr: _apr,
            uint: _ltv
        });
    }
    // Update new owner of bid if the right is transferred. 
    // You could add this to an NFT and then it'd become a promissory note
    function setNewBidOwner(uint256 _poolId, address _newAddress) external {
        require(_started(_poolId), "LAN: not started");
        require(!_ended(_poolId), "LAN: already ended"); 
        Loan memory loan = loans[_poolId];
        Bid storage latestBid = bids[_poolId][loan.numBids];
        require(latestBid.user == msg.sender, "LAN: Not the latest bidder");
        latestBid.user = _newAddress;
    }
    
    // Enable/Disable Whitelist mode
    function whitelistStatusUpdate(uint256 _poolId, bool _whitelist) external onlyOwner() {
        Loan storage loan = loans[_poolId];
        loan.whitelisted = _whitelist;
    }

    // Change Whitelist members
    function changeWhitelist(uint256 _poolId, address _newAddress, bool _status) external {
        whitelistedAddresses[_poolId][_newAddress] = _status;
    }

    // cancel if loan hasn't started yet
    function cancel(uint256 _poolId) external onlyOwner(_poolId) {
        Loan memory loan = loans[_poolId];
        require(loan.startTime > block.timestamp, "LAN: already started");
        delete loan;
        emit loanCancelled(_poolId);
    }

    // allow for early repayments to restore HF or end the loan.
    function repay(uint256 _poolId, uint _amount) external onlyOwner(_poolId){
         // transfer tokens to latest bidder
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];

        IERC20(loan.token).transferFrom(msg.sender, address(this), _amount);
        if(_amount + userPoolReserve[_poolId] >= _calculateLoanValue(_poolId)) {
            // end the loan
            IERC721 NFT = IERC721(loan.collectionAddress);
            NFT.safeTransferFrom(address(this), latestBid.user, loan.nftId);
            emit loanEnded(_poolId);
            delete loan;
        }
        userPoolReserve[_poolId] += _amount;
    }

    // if loan ended without full repayment, last bidder can liquidate, or if the liquidatable param is turned on, and they can liquidate
    function liquidate(uint256 _poolId) external {
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];
        require(
            ((latestBid.user == msg.sender) && _ended(_poolId)) || 
            (loan.liquidatable && _liquidate(loan, latestBid, _poolId)), "LAN: not latest bidder/notover, or not liquidatable");
        // transfer NFT
        IERC721 NFT = IERC721(loan.collectionAddress);
        NFT.safeTransferFrom(address(this), latestBid.user, loan.nftId);
        emit loanEnded(_poolId);
        delete loan;
    }

    // Check if liquidated.
    function _liquidate(Loan calldata loan, Bid calldata latestBid, uint256 _poolId) internal returns (bool){
        uint256 currentPrice = ILiquidationOracle(loan.oracleAddress).getUnderlyingPrice(loan.collectionAddress)/ILiquidationOracle(loan.oracleAddress).getUnderlyingPrice(loan.token);
        if ((latestBid.bidAmount - userPoolReserve[_poolId])/(latestBid.ltv*currentPrice) >= 1){
            return false;
        }
        return true;
    }

    // if loan is ongoing, bidder can liquidate early and not worry about repayment
    // defend against trolling by high bids where pool is, might be excluded tbh
    function liquidateEarly(uint256 _poolId) external onlyOwner(_poolId) {
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];
        // transfer NFT
        IERC721 NFT = IERC721(loan.collectionAddress);
        NFT.safeTransferFrom(address(this), latestBid.user, loan.nftId);
        emit loanEnded(_poolId);
        delete loan;
    }
    
    // calculate latest bid + interest
    function _calculateLoanValue(uint256 _poolId) internal view returns (uint256){
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];
        uint256 timeElapsed;
        if(_ended(_poolId)){
            timeElapsed =  latestBid.bidTime - loan.endTime;
        } else {
            timeElapsed =  latestBid.bidTime - block.timestamp;
        }
        return latestBid.bidAmount + latestBid.bidAmount * loan.apr / 10 ** 18 * timeElapsed / SECONDS_IN_ONE_YEAR;
    }

    function _ended(uint256 _poolId) internal view returns (bool){
        return loans[_poolId].endTime <= block.timestamp;
    }
    function _started(uint256 _poolId) internal view returns (bool){
        return loans[_poolId].startTime < block.timestamp;
    }
}
