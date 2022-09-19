// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "usingtellor/contracts/UsingTellor.sol";

import "./IPriceOracle.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

interface IWrapper {
    function getAmounts(uint256 _nftId)
        external
        view
        returns (uint256[] memory);

    function getTokens(uint256 _nftId) external view returns (address[] memory);
}

contract TellorOracle is IPriceOracle, UsingTellor {
    using Math for uint256;
    /// @notice mapping the asset address to the bytes32 for tellor
    mapping(address => string) tAddressMapping;
    event Log(string message);
    address public immutable Wrapper;

    // _tellorAddress is the address of the Tellor oracle
    constructor(address payable _tellorAddress, address _wrapper)
        UsingTellor(_tellorAddress)
    {
        Wrapper = _wrapper;
    }

    function getBundlePrice(address wrapper, uint256 nftId)
        external view
        returns (uint256)
    {
        /// @notice If it's say a BAYC and not a wrapper, getUnderlyingPrice
        if (wrapper != Wrapper) return _getUnderlyingPrice(wrapper);
        address[] memory tokens = IWrapper(wrapper).getTokens(nftId);
        uint256[] memory amounts = IWrapper(wrapper).getAmounts(nftId);
        // loop through all assets and calculate borrowable USD
        uint256 totalPriceUSD; // 18 decimal places
        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; i++) {
            // getUnderlyingPrice returns price in 18 decimals and USD

            //the interface states that it should return zero when the price is unavailable.
            // function getUnderlyingPrice(address underlying,address quote) external view returns (uint256);

            uint256 underlyingPrice = _getUnderlyingPrice(tokens[i]);

            if (underlyingPrice == 0) {
                totalPriceUSD += underlyingPrice.mulDiv(amounts[i], 1e18);
            } 
        }
        return totalPriceUSD;
    }

    function getUnderlyingPrice(address _underlying)
        external
        view
        returns (uint256)
    {
        return _getUnderlyingPrice(_underlying);
    }

    // default return type is USD price for collateral. Will fail if there deosn't exist a USD price
    function setMapping(address tokenAddress, string calldata assetName) external {
        tAddressMapping[tokenAddress] = assetName;
    }

    function _getUnderlyingPrice(address _address)
        internal
        view
        returns (uint256 price)
    {
        string memory _asset = tAddressMapping[_address];
        bytes memory _queryData = abi.encode(
            "SpotPrice",
            abi.encode(_asset, "usd")
        );
        bytes32 _queryId = keccak256(_queryData);
        (bool ifRetrieve, bytes memory _value, ) = getCurrentValue(_queryId);
        if (!ifRetrieve) return 0;
        return toUint256(_value);
    }

    function toUint256(bytes memory _bytes)   
  internal
  pure
  returns (uint256 value) {

    assembly {
      value := mload(add(_bytes, 0x20))
    }
}
}
