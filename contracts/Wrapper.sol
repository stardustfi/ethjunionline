pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Wrapper is ERC721{
    /// @notice Internal count of wrappers
    uint256 public count;

    struct Container {
        address[] tokens,
        uint256[] amounts
    }
    
    /// @notice map count to Container struct
    mapping(uint256 => Container) public contained;

    constructor() public ERC721("LanBundle", "LAN") {}
    /// @notice No direct erc721 native support, just wrap 721 in an erc20 to support
    function wrap(address[] calldata _tokens, uint256[] calldata _amounts) external {
        require(_tokens.length == _amounts.length, "Wrapper: Not equal lengths");
        uint256 length = _tokens.length
        for (uint256 i=0; i < length;) {
            // getUnderlyingPrice returns price in 18 decimals and USD
            IERC20(_tokens[i]).transferFrom(msg.sender, address(this), _amounts[i]);
            unchecked{++i;}
        }
        contained[count] = Container(_token, _amounts);
        _mint(msg.sender, count++);
    }

    

    function getTokens(uint256 _nftId) public view returns (address[] memory) {
        return contained[_nftId].tokens;
    }
    
    function getAmounts(uint256 _nftId) public view returns (uint256[] memory) {
        return contained[_nftId].tokens;
    }

    function burnAndRedeem(uint256 _nftId) external {
        _burn(_nftId);
        _amounts = getAmounts(_nftId);
        _tokens = getTokens(_nftId);
        delete contained[_nftId];
        uint256 length = _tokens.length
        for (uint256 i=0; i < length;) {
            // getUnderlyingPrice returns price in 18 decimals and USD
            IERC20(_tokens[i]).transferFrom(address(this), msg.sender, _amounts[i]);
            unchecked{++i;}
        }

    }
}
