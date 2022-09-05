pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract LAN{
    event newPool(
        uint256 indexed poolId,
        address collectionAddress,
        uint256 nftId
    );
    event newBid(
        uint256 indexed bidAmount,
        address user,
        uint256 indexed bidNum
    );
    event sold(address newOwner, uint256 bidAmount);
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
        uint256 totalPoints;
    }
    mapping(uint256 => Loan) public loans;

    struct Bid {
        uint256 bidTime;
        uint256 bidAmount;
        address user;
        uint256 points;
        bool withdrawn;
    }
    mapping(uint256 => mapping(uint256 => Bid)) public bids; //pool id, bid number

    uint256 private constant SECONDS_IN_ONE_YEAR = 60*60*24*365;

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
            numBids: 0,
            totalPoints: 0
        });
        bids[count][0] = Bid({
            bidTime: block.timestamp,
            bidAmount: 0,
            user: msg.sender,
            points: 0,
            withdrawn: false
        });
        emit newPool(count, _collectionAddress, _nftId);
        count++;
    }
    
    //cancel if loan hasn't started yet
    function cancel(uint256 _poolId) external {
        Loan constant loan = loans[_poolId];
        require(loan.owner == msg.sender, "LAN: not owner");
        require(loan.startTime < block.timestamp, "LAN: already started");
        delete loan;
        emit loanCancelled(_poolId);
    }
    function bid(uint256 _poolId, uint256 _amount) external {
        Loan constant loan = loans[_poolId];
        require(loan.startTime <= block.timestamp, "LAN: not started");
        require(loan.endTime > block.timestamp, "LAN: already ended");

        //increment bids by 1
        uint256 numBids = loan.numBids + 1;

        loan.numBids = numBids;
        uint256 constant loanValue = _calculateLoanValue(_poolId);
        require(_amount > loanValue, "LAN: bid not higher");
        //send tokens to previous bidder
        IERC20(loan.token).transferFrom(msg.sender, bids[_poolId][numBids].user, loanValue);
        //send tokens to contract
        IERC20(loan.token).transferFrom(msg.sender, address(this), _amount - loanValue);
        //record data
        bids[_poolId][numBids] = Bid({
            bidTime: block.timestamp,
            bidAmount: _amount,
            user: msg.sender,
            points: 0, //will be calculated on next bid or _finalize
            withdrawn: false
        });
    }
    
    //calculate latest bid + interest
    function _calculateLoanValue(uint256 _poolId) internal view returns (uint256){
        Loan constant loan = loans[_poolId];
        uint256 constant apr = loan.apr;
        Bid constant latestBid = bids[_poolId][loan.numBids]
        uint256 constant bidTime = latestBid.bidTime;
        uint256 constant bidAmount = latestBid.bidAmount;
        return bidAmount + bidAmount * (bidTime - block.timestamp) / SECONDS_IN_ONE_YEAR
    }
}
