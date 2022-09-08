pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
interface IChainlink {
  function latestRoundData() external view returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}

contract BaseBid{
    address public immutable admin;
    address public immutable baseAsset;
    address public immutable baseAssetOracle;
    uint256 public immutable adminFee;

    ILan private constant Lan = ILan(); //insert deployment here
    IWrapper private constant Wrapper = IWrapper();

    constructor(
        address _admin,
        address _baseAsset,
        address _baseAssetOracle,
        uint256 _adminFee
    ) {
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        adminFee = _adminFee;
    }

    struct Term {
            uint256 LTV;
            address oracle;
    }
    mapping(address => Term) public whitelists;

    function addWhitelist(address _token, uint256 _LTV, address _oracle) external {
        whitelists[_token] = Term({
            LTV: _LTV,
            oracle: _oracle
        });
    }

    function removeWhitelist(address _token) external {
        delete whitelists[_token];
    }

    function automaticBid(uint256 _poolId) external {
        (,address token, address collectionAddress, uint256 nftId,,,,) = readLoan(_poolId);
        require(token == baseAsset, "BaseBid: different base asset");
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
        Lan.bid(_poolId, borrowableToken);
    }

    function readLoan(uint256 _poolId) view returns(address owner, address token, address collectionAddress, uint256 nftId, uint256 startTime, uint256 endTime, uint256 apr, uint256 numBids) {
        return(Lan.loans(_poolId));
    }
}
