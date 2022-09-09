// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract LAN{
    event newPool(
        uint256 indexed poolId,
        address collectionAddress,
        uint256 nftId
    );
    event loanCancelled(uint256 Id);

    uint256 public count;
    struct Loan {
        address owner;
        address token;
        address operator;
        // address oracleAddress
        uint16 apr;
        address collectionAddress;
        uint256 nftId;
        uint256 startTime;
        uint256 endTime;
        uint256 numBids;
        //bool liquidatable;
        bool whitelisted;
        
    }

    mapping(uint256 => Loan) public loans;

    struct Bid {
        uint256 bidTime;
        uint256 bidAmount;
        address user;
        uint16 apr;
        //uint256 ltv;
    }
    mapping(uint256 => mapping(uint256 => Bid)) public bids; // pool id, bid number

    //whitelist only mode auctionId => bidder address => bool 
    mapping(uint256 => mapping(address => bool)) public whitelistedAddresses;

    uint256 private constant SECONDS_IN_ONE_YEAR = 60*60*24*365;

    modifier onlyOwner(uint256 _poolId){
        require((loans[_poolId].owner == msg.sender)
        ||(loans[_poolId].operator == msg.sender), "LAN: not owner");
        _;
    }


    function launch(address _operator, address _token, address _collectionAddress, uint256 _nftId, uint256 _startTime, uint256 _endTime, bool _whitelisted) public {
        require(_startTime >= block.timestamp, "LAN: start time in past");
        require(_endTime > _startTime, "LAN: start after end");
        loans[count] = Loan({
            owner: IERC721(_collectionAddress).ownerOf(_nftId),
            operator: _operator,
            //operator can be msg.sender or address(0) if operator role isn't used
            token: _token,
            collectionAddress: _collectionAddress,
            nftId: _nftId,
            startTime: _startTime,
            endTime: _endTime,
            apr: 0,
            numBids: 0,
            whitelisted: _whitelisted
        });
        bids[count][0].bidTime = block.timestamp;
        emit newPool(count, _collectionAddress, _nftId);
        count++;
    }

    function bid(uint256 _poolId, uint256 _amount, uint16 _apr) external {
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
            apr: _apr
            //uint ltv
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
    
    //change whitelist
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

    // end loan by repaying debt
    function endLoan(uint256 _poolId) external onlyOwner(_poolId) {
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];
        // transfer tokens to latest bidder
        IERC20(loan.token).transferFrom(msg.sender, latestBid.user, _calculateLoanValue(_poolId));
        // transfer NFT back to owner
        IERC721 NFT = IERC721(loan.collectionAddress);
        NFT.safeTransferFrom(address(this), msg.sender, loan.nftId);
    }

    // if loan ended, last bidder can liquidate
    function liquidate(uint256 _poolId) external {
        Loan memory loan = loans[_poolId];
        require(_ended(_poolId), "LAN: loan not ended");
        Bid memory latestBid = bids[_poolId][loan.numBids];
        require(latestBid.user == msg.sender, "LAN: not latest bidder");
        // transfer NFT
        IERC721 NFT = IERC721(loan.collectionAddress);
        NFT.safeTransferFrom(address(this), msg.sender, loan.nftId);
    }

    // if loan is ongoing, bidder can liquidate early and not worry about repayment
    // defend against trolling by high bids where pool is, might be excluded tbh
    function liquidateEarly(uint256 _poolId) external onlyOwner(_poolId) {
        Loan memory loan = loans[_poolId];
        Bid memory latestBid = bids[_poolId][loan.numBids];
        // transfer NFT
        IERC721 NFT = IERC721(loan.collectionAddress);
        NFT.safeTransferFrom(address(this), latestBid.user, loan.nftId);
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
