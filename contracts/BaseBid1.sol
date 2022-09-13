// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "/BaseBidding.sol";
import "/Utilization.sol";

/// @notice Base implementation of BaseBid, similar to Compound V3
/// @title BaseBid1
/// @author William, Junion
/// @notice Code is really rough and likely contains bugs :)
interface IPriceOracle {
    uint256 underlyingPrice;    
    
}

interface ILan {
    //todo
}
interface IWrapper {
    //todo
}
contract BaseBid1 is BaseBidding, Utilization {
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
    uint16 public minAPY;
    bool public windDown;
    bool public liquidationOnly;
    uint16 public kink;
    uint256 public minAPR;
    uint256 public cash;
    uint256 public longestTerm;
    uint256 public immutable adminFee;
    ILan private constant Lan = ILan(); //insert deployment here
    IWrapper private constant Wrapper = IWrapper();

    /// @notice Initialize contract, pass in data to BaseBidding parent
    /// @param _admin, controller of the contract
    /// @param _baseAsset, base asset address
    /// @param _baseAssetOracle, address for this base asset, needs to implement IPriceOracle
    /// @param _LANContract, LAN contract
    /// @param _liquidationOnly, True if liquidations are enabled, False if not. Liquidations default oracle is Chainlink
    /// @param _kink, Integer value. A kink of 80 would correspond to a kink at 80%
    /// @param _minAPR, the min APR for the loan before it'll get initiated
    /// @param _longestTerm, in blocks, the longest auction that the contract will participate in
    /// @param _adminFee, Admin Fee, charged on interest accrued.

    constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        address _LANContract,
        bool _liquidationOnly,
        uint16 _kink,
        uint256 _minAPR,
        uint256 _longestTerm,
        uint256 _adminFee
    ) BaseBidding(_admin, _baseAsset, _baseAssetOracle, _LANContract, _liquidationOnly, _minAPR, _longestTerm, _adminFee){
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LAN = ILan(_LANcontract)
        kink = _kink;
        minAPY = _minAPY;
        windDown = false;
        liquidationOnly = _liquidationOnly;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
        windDown = false;
        //infinite token approval for LAN
        IERC20(baseAsset).approve(_LANcontract, type(uint256).max);
    }

    IWrapper private constant Wrapper = IWrapper(); //add address here

    struct Term {
        uint256 LTV;
        address oracle;
    }
    mapping(address => Term) public whitelists;

    /// @notice Add whitelist asset to vault
    /// @param _token is token address
    /// @param _LTV is the LTV of the asset
    /// @param _oracle is the oracle that will be queried. Oracle should implement IPriceOracle
    function addWhitelist(address _token, uint256 _LTV, address _oracle) external onlyOwner(){
        whitelists[_token] = Term({
            LTV: _LTV,
            oracle: _oracle
        });
    }
    /// @notice Remove whitelist
    /// @param _token is token address
    function removeWhitelist(address _token) external onlyOwner(){
        delete whitelists[_token];
    }

    /// @notice Deposit
    /// @param _tokenAmount is amount deposited    
    function deposit(uint256 _tokenAmount) public virtual shutdown() {
        IERC20(baseAsset).transferFrom(msg.sender, address(this), _tokenAmount);
        cash += _tokenAmount;
    }

    /// @notice Withdraw
    /// @param _tokenAmount is amount withdrawn 
    function withdraw(uint256 _tokenAmount) public virtual onlyOwner() {
        IERC20(baseAsset).transferFrom(msg.sender, address(this), _tokenAmount);
        cash -= _tokenAmount;
    }

    /// @notice Pause, no new loans get issued.
    function pause() external onlyOwner() {
        windDown = true;
    }
    
    /// @notice Liquidate Auction if the auction can be liquidated. Asset is kept in contract but approved to the owner
    /// Owner can withdraw at any time, but if admin is changed, the approval isn't updated.
    /// @param _poolId The pool ID
    function liquidateAuction(uint256 _poolId) public virtual onlyOwner() {
            try Lan.liquidate(_poolId){
            (,,,address collectionAddress, uint256 nftId,,,,,,) = readLoan(_poolId);
            IERC721(collectionAddress).approve(admin, nftId);
        } catch(string memory reason) {
            emit log(reason);
        }
    }

    /// @notice Call the LAN contract and make a bid with specific parameters. LTV is determined inclusive of accrued interest.
    /// Update utilization when the loan is issued.
    /// @param _poolId The pool ID
    /// @param _borrowAmount The amount requested to borrow
    /// @param _apr The APR for the borrow
    function bidWithParams(uint256 _poolId, uint256 _borrowAmount, uint256 _apr) public shutdown() onlyOwner(){
        require(_apr >= minAPY, "BaseBid: APY below minAPY");
        (,address token,,address collectionAddress, uint256 nftId,,uint256 endTime,,bool liquidatable,) = readLoan(_poolId);
        require(liquidatable == true, "Basebid: Liquidatable not true")
        require(token == baseAsset, "BaseBid: different base asset");
        require(collectionAddress = Wrapper, "BaseBid: Collateral not in a wrapper");
        require(_calculateLTV(nftId, endTime, _apr) >= _borrowAmount; "BaseBid: Borrow Amount too high");
        try Lan.bid(_poolId, _borrowAmount, apr){
            emit newLoan(collectionAddress, apr, poolId, bidAmount);
            _utilization();
        } catch(string memory reason) {
            emit log(reason);
        }
    }

    /// @notice Sum the value of whitelisted assets contained in the NFT wrapper. Nonwhitelisted assets are 0.
    /// @param _nftID The ID of the NFT for the wrapper contract
    /// @param _borrowAmount The amount requested to borrow
    /// @param _apr The APR for the borrow
    function _calculateLTV(uint256 nftId, uint256 endTime, uint256 apr) internal returns(uint maxBorrowable) {
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

    /// @notice Automatically bid the highest possible bid, using bidWithParams
    /// @param _poolId Pool ID
    function automaticBid(uint256 _poolId) external shutdown() onlyOwner() {
        (,,,,,uint256 nftId,,,uint256 apr,,,) = readLoan(_poolId);
        bidWithParams(_poolId, _calculateLTV(nftId), apr);
    }
    
    /// @notice Change the minAPR based on the # of assets deposited (cash), and # of assets currently inside (reserves)
    function _utilization() internal {
        // compound Jump rate Model kinda
        uint256 reserves = IERC20(baseAsset).balanceOf(address(this);
        uint16 util = reserves/cash;
        if(util <= kink) {
            // Increase minAPR with utilization linearly
            minAPR += util * 10**19;
        } else {
            // Change linear slope by 10x
            minAPR += util * 10**20;
        }

    }

}

