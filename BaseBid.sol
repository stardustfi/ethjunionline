// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface IChainlink {
  function latestRoundData() external view returns (
    uint80 roundId, 
    int answer, 
    uint startedAt, 
    uint updatedAt, 
    uint80 answeredInRound);
}

interface ILan {
    //todo
}
interface IWrapper {
    //todo
}

contract BaseBid{
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
    uint256 public longestTerm;
    uint256 public immutable adminFee;


    modifier onlyOwner(){
        require(msg.sender == admin, "LAN: not owner");
        _;
    }

    constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        address _LANContract,
        uint16 _minAPY,
        uint256 _longestTerm,
        uint256 _adminFee
    ) {
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LAN = ILan(_LANcontract)
        minAPY = _minAPY;
        windDown = false;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
        //infinite token approval for LAN
        IERC20(baseAsset).approve(_LANcontract, type(uint256).max);
    }

    IWrapper private constant Wrapper = IWrapper(); //add address here

    struct Term {
        uint256 LTV;
        address oracle;
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

    function deposit(uint256 _tokenAmount) public {
        IERC20(baseAsset).transferFrom(msg.sender, address(this), _tokenAmount);
    }

    function withdraw(uint256 _tokenAmount) external onlyOwner(){
        IERC20(baseAsset).transfer(address(this), msg.sender, _tokenAmount);
    }

    function liquidateAuction(uint256 _poolId) external {
        try Lan.liquidate(_poolId){
            (,,,address collectionAddress, uint256 nftId,,,,,) = readLoan(_poolId);
            IERC721(collectionAddress).approve(admin, nftId);
            // admin can transfer out at any time. note that admin isn't updated
        } catch(string memory reason) {
            emit log(reason);
        }
        
    }

    function pause() external onlyOwner() {
        windDown = true;
    }

    //function bidWithParams()
    function bidWithParams(uint256 _poolId, uint256 _borrowAmount, uint16 _apr) public {
        
    }

    function automaticBid(uint256 _poolId) external {
        
        // Assumes the collateral is a wrapped asset
        (,address token,,address collectionAddress, uint256 nftId,,,uint16 apr,,) = readLoan(_poolId);
        require(token == baseAsset, "BaseBid: different base asset");
        require(apr >= minAPY, "BaseBid: APY below minAPY");
        require(windDown == false, "BaseBid: No new Bids");
        // implement erc165 logic to determine multicollateral or single collateral erc20, or erc721 @Junion
        address[] memory tokens = Wrapper.getTokens(nftId);
        uint256[] memory amounts = Wrapper.getAmounts(nftId);

        // loop through all assets and calculate borrowable USD
        uint256 borrowableUSD; // 18 decimal places
        uint256 length = tokens.length;
        for (uint256 i=0; i < length;) {
            Whitelist memory whitelist = whitelists[tokens[i]];
            // get chainlink price (8 decimals)
            (,int collateralPrice,,,) = IChainlink(whitelist.oracle).latestRoundData();
            borrowableUSD += amounts[i] * whitelist[token].LTV * collateralPrice / 10**26;
            unchecked{++i;}
        }

        // convert USD to baseToken
        // get chainlink price (8 decimals)
        (,int basePrice,,,) = IChainlink(baseAssetOracle).latestRoundData();
        uint256 borrowableToken;
        if(decimals > 18){
            borrowableToken = borrowableUSD / basePrice / 10**(18-decimals);
        } else {
            borrowableToken = borrowableUSD / basePrice * 10**(decimals-18);
        }
        // automatically set highest possible bid, same APR as previous loan
        try Lan.bid(_poolId, borrowableToken, apr){
            emit newLoan(collectionAddress, apr, poolId, bidAmount);
        } catch(string memory reason) {
            emit log(reason);
        }
    }
    
    function bid(uint256 _poolId) internal {
        
    }

    function readLoan(uint256 _poolId) view external returns(
        address owner, 
        address token, 
        address operator,
        address collectionAddress, 
        uint256 nftId, 
        uint256 startTime, 
        uint256 endTime, 
        uint16 apr, 
        uint256 numBids,
        bool whitelisted) 
        {
        return(Lan.loans(_poolId));
    }

}
