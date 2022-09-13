// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../external/chainlink/FeedRegistryInterface.sol";
import "../external/chainlink/Denominations.sol";

contract ChainlinkOracle is IPriceOracle {
    FeedRegistryInterface feedRegistry = FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    address immutable wrapper = address(0);
    event Log(string message);

    // todo implement interface with Wrapper @junion
    // rejigger CL stuff, the link to the imports above is https://raw.githubusercontent.com/Rari-Capital/fuse-contracts/master/contracts/external/chainlink/AggregatorInterface.sol
    
    function getUnderlyingPrice(address _underlying) external view returns (uint256) {
        if(underlying == WRAPPER){
            address[] memory tokens = Wrapper.getTokens(nftId);
            uint256[] memory amounts = Wrapper.getAmounts(nftId);
            // loop through all assets and calculate borrowable USD
            uint256 totalPriceUSD; // 18 decimal places
            uint256 length = tokens.length;
            for (uint256 i=0; i < length;) {
                // getUnderlyingPrice returns price in 18 decimals and USD
                try _getUnderlyingPrice(address) returns (uint256 memory underlyingPrice){
                    totalPriceUSD += underlyingPrice;
                } catch {
                    emit Log("Chainlink call failed for this asset");
                }
                unchecked{++i;}
            }
            return totalPriceUSD;
        } else {
            return _getUnderlyingPrice(_underlying);
        }
        
    }

    // default return type is USD price for collateral. Will fail if there deosn't exist a USD pair
    // ToDo: add eth pair mode as well
    function _getUnderlyingPrice(address underlying) internal view returns (uint256) {
        
        /*
        try feedRegistry.latestRoundData(underlying, Denominations.USD) returns (,int256 tokenUsdPrice,,,) {

        (underlyingPrice 10 ** uint256(feedRegistry.decimals(underlying, Denominations.USD))
        */
        (,int128 underlyingPrice,,,) = feedRegistry.latestRoundData(underlying, Denominations.USD);
        return uint256(underlyingPrice).mul(1e26).div(10 ** uint256(feedRegistry.decimals(underlying, Denominations.USD)));
        
    }

}