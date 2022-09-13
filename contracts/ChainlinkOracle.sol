// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;


import "../external/chainlink/FeedRegistryInterface.sol";
import "../external/chainlink/Denominations.sol";


contract ChainlinkOracle is IPriceOracle {
    FeedRegistryInterface feedRegistry = FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);

    // default return type is USD price for collateral. Will fail if there deosn't exist a USD pair
    // ToDo: add eth pair mode as well
    function getUnderlyingPrice(address underlying) external view returns (uint256) {
        /*
        try feedRegistry.latestRoundData(underlying, Denominations.USD) returns (,int256 tokenUsdPrice,,,) {

        (underlyingPrice 10 ** uint256(feedRegistry.decimals(underlying, Denominations.USD))
        */
        (,int128 underlyingPrice,,,) = feedRegistry.latestRoundData(underlying, Denominations.USD);
        return uint256(underlyingPrice).mul(1e26).div(10 ** uint256(feedRegistry.decimals(underlying, Denominations.USD)));
        
    }

}