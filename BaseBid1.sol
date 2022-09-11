// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "/BaseBidding.sol";

interface IPriceOracle {
    uint256 underlyingPrice;    
}

contract BaseBid1 is BaseBidding {
    event log(string reason);

    address public immutable admin;
    address public immutable baseAsset;
    address public immutable baseAssetOracle;
    address public immutable LANcontracts;
    bool public windDown;
    uint16 public minAPR;
    uint256 public longestTerm;
    uint256 public immutable adminFee;
    ILan private constant Lan = ILan(); //insert deployment here
    IWrapper private constant Wrapper = IWrapper();
    constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        address _LANContract,
        uint16 _minAPR,
        uint256 _longestTerm,
        uint256 _adminFee
    ) BaseBidding(_admin, _baseAsset, _baseAssetOracle, _LANContract, _minAPR, _longestTerm, _adminFee){
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LANcontracts = _LANContract;
        minAPR = _minAPR;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
        windDown = false;
        //infinite token approval for LAN
        IERC20(baseAsset).approve(LANcontract, 0xFFFFFFFF);
    }
    
    mapping(address => Term) public whitelists;

    function addWhitelist(address _token, uint256 _LTV, address _oracle) external onlyOwner(){
        whitelists[_token] = Term({
            LTV: _LTV,
            oracle: _oracle
        });
    }
 
    function removeWhitelist(address _token) external onlyOwner(){
        delete whitelists[_token];
    }
    
    function deposit(uint256 _tokenAmount) public virtual shutdown() {
        IERC20(baseAsset).transferFrom(msg.sender, address(this), _tokenAmount);
    }

    function withdraw(uint256 _tokenAmount) public virtual {
        IERC20(baseAsset).transferFrom(msg.sender, address(this), _tokenAmount);
    }

    function pause() external onlyOwner() {
        windDown = true;
    }
    
    function liquidateAuction(uint256 _poolId) public virtual onlyOwner() {
            try Lan.liquidate(_poolId){
            (,,,address collectionAddress, uint256 nftId,,,,,) = readLoan(_poolId);
            IERC721(collectionAddress).approve(admin, nftId);
            // admin can transfer out at any time. note that admin isn't updated
        } catch(string memory reason) {
            emit log(reason);
        }
    }
    //function bidWithParams()
    function bidWithParams(uint256 _poolId, uint256 _borrowAmount, uint16 _apr) public shutdown() onlyOwner(){
        require(_apr >= minAPY, "BaseBid: APY below minAPY");
        (,address token,,address collectionAddress, uint256 nftId,,uint256 endTime,,,) = readLoan(_poolId);
        require(token == baseAsset, "BaseBid: different base asset");
        require(collectionAddress = Wrapper, "BaseBid: Collateral not in a wrapper");
        require(_calculateLTV(nftId, endTime, _apr) >= _borrowAmount; "BaseBid: Borrow Amount too high");
        // automatically set highest possible bid, same APR as previous loan
        try Lan.bid(_poolId, _borrowAmount, apr){
            emit newLoan(collectionAddress, apr, poolId, bidAmount);
        } catch(string memory reason) {
            emit log(reason);
        }
    }

    function _calculateLTV(uint256 nftId, uint256 endTime, uint16 apr) internal returns(uint maxBorrowable) {
        address[] memory tokens = Wrapper.getTokens(nftId);
        uint256[] memory amounts = Wrapper.getAmounts(nftId);
        whitelists[tokens[i]]
        // loop through all assets and calculate borrowable USD
        uint256 borrowableUSD; // 18 decimal places
        uint256 length = tokens.length;
        for (uint256 i=0; i < length;) {
            Whitelist memory whitelist = whitelists[tokens[i]];
            // Check if token is on whitelist - skip if not
            if(whitelist.oracle != address(0)){
                // getUnderlyingPrice returns price in 18 decimals and USD
                uint256 collateralPrice = IPriceOracle(whitelist.oracle).getUnderlyingPrice(tokens[i]);
                borrowableUSD += amounts[i] * whitelist[token].LTV * collateralPrice / 10**26;
            }
            unchecked{++i;}
        }
        uint256 elapsedTime = endTime - block.timestamp;
        uint256 basePrice = IPriceOracle(baseAssetOracle).getUnderlyingPrice(baseAsset);
        uint256 loanValue = _calculateLoanValue(borrowableUSD, elapsedTime, apr);
        uint256 maxBorrowable = loanValue/basePrice;
    }

    function automaticBid(uint256 _poolId) external shutdown() onlyOwner() {
        (,,,,uint256 nftId,,,uint16 apr,,) = readLoan(_poolId);
        // automatically set highest possible bid, same APR as previous loan
        bidWithParams(_poolId, _calculateLTV(nftId), apr);
    }
    


}
