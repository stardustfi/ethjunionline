// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC721 {
    function transferFrom(
        address _from,
        address _to,
        uint256 _nftId
    ) external;
}

// Dirt simple dutch auction.

contract DutchAuction {
    uint256 private constant DURATION = 7 days;

    IERC20 public immutable token;
    address payable public constant SELLER = address(this);
    uint256 public auctionId;
    struct auction {
        uint256 startingPrice;
        uint256 startAt;
        uint256 expiresAt;
        uint256 discountRate;
        uint256 nftId;
        IERC721 nft;
    }

    // Map auctionId to Auction
    mapping(uint256 => auction) public Auctions;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function beginAuction(
        uint256 _startingPrice,
        uint256 _discountRate,
        address _nft,
        uint256 _nftId,
    ) public {
        require(
            _startingPrice >= _discountRate * DURATION,
            "starting price < min"
        );
        auctionId++;
        Auctions[auctionId] = auction(
            _startingPrice,
            block.timestamp,
            block.timestamp + DURATION,
            _discountRate,
            IERC721(_nft),
            nftId
        );
    }

    function getPrice(auction memory aAuction) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - aAuction.startAt;
        uint256 discount = aAuction.discountRate * timeElapsed;
        return startingPrice - discount;
    }

    function buy(uint256 _bidAmount, uint256 _auctionId) external payable {
        auction memory aAuction = Auctions[_auctionId];
        require(block.timestamp < aAuction.expiresAt, "auction ended");

        uint256 price = getPrice(aAuction);
        require(_bidAmount >= price, "Bid < price");

        token.transferFrom(msg.sender, address(this), _bidAmount);

        nft.transferFrom(SELLER, msg.sender, aAuction.nftId);

        delete Auctions[_auctionId];

        uint256 refund = _bidAmount - price;
        if (refund > 0) {
            token.transferFrom(SELLER, msg.sender, refund);
        }
    }
}
