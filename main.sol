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
        address collectionAddress;
        uint256 nftId;
        uint256 startTime;
        uint256 endTime;
        uint256 apr;
        uint256 numBids;
    }
    mapping(uint256 => Loan) public loans;

    struct Bid {
        uint256 bidTime;
        uint256 bidAmount;
        address user;
    }
    mapping(uint256 => mapping(uint256 => Bid)) public bids; // pool id, bid number

    uint256 private constant SECONDS_IN_ONE_YEAR = 60*60*24*365;

    modifier onlyOwner(uint256 _poolId){
        require(loans[_poolId].owner == msg.sender, "LAN: not owner");
        _;
    }

    function launch(address _token, address _collectionAddress, uint256 _nftId, uint256 _startTime, uint256 _endTime, uint256 _apr) public {
        require(_startTime >= block.timestamp, "LAN: start time in past");
        require(_endTime > _startTime, "LAN: start after end");
        loans[count] = Loan({
            owner: msg.sender,
            token: _token,
            collectionAddress: _collectionAddress,
            nftId: _nftId,
            endTime: _endTime,
            startTime: _startTime,
            apr: _apr,
            numBids: 0
        });
        bids[count][0].bidTime = block.timestamp;
        emit newPool(count, _collectionAddress, _nftId);
        count++;
    }

    function bid(uint256 _poolId, uint256 _amount) external {
        require(_started(_poolId), "LAN: not started");
        require(!_ended(_poolId), "LAN: already ended");
        Loan memory loan = loans[_poolId];

        // increment bids by 1
        uint256 numBids = loan.numBids + 1;

        loan.numBids = numBids;
        uint256 loanValue = _calculateLoanValue(_poolId);
        require(_amount > loanValue, "LAN: bid not higher");
        // send tokens to previous bidder
        IERC20(loan.token).transferFrom(msg.sender, bids[_poolId][numBids].user, loanValue);
        // send tokens to owner
        IERC20(loan.token).transferFrom(msg.sender, loan.owner, _amount - loanValue);
        // record data
        bids[_poolId][numBids] = Bid({
            bidTime: block.timestamp,
            bidAmount: _amount,
            user: msg.sender
        });
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
