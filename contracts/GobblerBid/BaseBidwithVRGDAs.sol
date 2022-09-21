// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/ownable.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./contracts/DutchAuction.sol";
import "./contracts/ERC4626.sol";
import {toDaysWadUnsafe, toWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {LogisticVRGDA} from "./contracts/GobblerBid/LogisticVRGDA.sol";

/// @notice Base Bid + VRGDAs + Art Gobblers + ERC4626 - Unit Testing, because why not.
/// @title BaseBidwithVRGDAs
/// @author William, Junion
interface IPriceOracle {
    // Standardize oracle output
    // Return price of asset in WETH terms, (1e18)
    function getUnderlyingPrice(address underlying)
        external
        view
        returns (uint256);
}

interface ILan {
    function bid(
        uint256 _poolId,
        uint256 _amount,
        uint256 _apr,
        uint16 _ltv
    ) external {}

    function liquidate(uint256 _poolId) external {}
}

interface IWrapper {
    function getAmounts(uint256 _nftId)
        public
        view
        returns (uint256[] memory)
    {}

    function getTokens(uint256 _nftId) public view returns (address[] memory) {}
}

contract BaseBid1 is BaseBidding, ERC4626, DutchAuction, LogisticVRGDA {
    event newLoan(
        address collectionAddress,
        uint16 apr,
        uint256 poolId,
        uint256 bidAmount
    );
    event log(string reason);

    address public immutable aavePool;
    address public immutable admin;
    address public immutable baseAsset;
    address public immutable baseAssetOracle;
    uint256 public immutable startTime = block.timestamp; // When VRGDA sales begun
    ILan public immutable LAN;
    IPool public immutable pool;    
    uint16 public minAPY;
    uint16 public kink;
    bool public windDown;
    bool public liquidationOnly;
    uint256 public totalSold; // The total number of tokens sold so far.
    uint256 public minAPR;
    uint256 public cash;
    uint256 public longestTerm;
    uint256 public immutable adminFee;
    ILan private constant Lan = ILan(); //insert deployment here
    IWrapper private constant Wrapper = IWrapper();
    uint256 public constant MAX_MINTABLE = 100; // Max supply.
    uint256 public totalSold; // The total number of tokens sold so far.
    uint256 public immutable startTime = block.timestamp;

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
        address _pool
        bool _liquidationOnly,
        uint16 _kink,
        uint256 _minAPR,
        uint256 _longestTerm,
        uint256 _adminFee
    )
        BaseBidding(
            _admin,
            _baseAsset,
            _baseAssetOracle,
            _LANContract,
            _liquidationOnly,
            _minAPR,
            _longestTerm,
            _adminFee
        )
        ERC20(
            string.concat(_baseAsset._name, "LAN Pool Token"),
            string.concat(_baseAsset._symbol, "PT")
        )
        ERC4626(_baseAsset)
        DutchAuction(_baseAsset)
        LogisticVRGDA(
            69.42e18, // Target price.
            0.31e18, // Price decay percent.
            // Maximum # mintable/sellable.
            toWadUnsafe(MAX_MINTABLE),
            0.1e18 // Time scale.
        )
    {
        admin = _admin;
        baseAsset = _baseAsset;
        baseAssetOracle = _baseAssetOracle;
        LAN = ILan(_LANcontract);
        pool = IPool(_pool);
        kink = _kink;
        minAPY = _minAPY;
        windDown = false;
        liquidationOnly = _liquidationOnly;
        longestTerm = _longestTerm;
        adminFee = _adminFee;
        windDown = false;
        //infinite token approval for LAN
        IERC20(baseAsset).approve(_LANcontract, type(uint256).max);
        IERC20(baseAsset).approve(_LANcontract, type(uint256).max);
    }

    struct Term {
        uint256 LTV;
        address oracle;
    }

    // Mapping Token Address => Terms
    mapping(address => Term) public whitelists;

    // Mapping PoolId => amountPaid
    mapping(uint256 => uint256) public pricePaid;

    /// @notice Add whitelist asset to vault
    /// @param _token is token address
    /// @param _LTV is the LTV of the asset
    /// @param _oracle is the oracle that will be queried. Oracle should implement IPriceOracle
    function addWhitelist(
        address _token,
        uint256 _LTV,
        address _oracle
    ) external onlyOwner {
        whitelists[_token] = Term({LTV: _LTV, oracle: _oracle});
    }

    /// @notice Remove whitelist
    /// @param _token is token address
    function removeWhitelist(address _token) external onlyOwner {
        delete whitelists[_token];
    }

    /// @notice Deposit/withdraw is on ERC4626
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256)
    {
        uint256 price = getVRGDAPrice(
            toDaysWadUnsafe(block.timestamp - startTime),
            mintedId = totalSold++
        );
        require(assets >= price, "UNDERPAID");
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );

        uint256 shares = 1e18;
        _deposit(_msgSender(), receiver, assets, shares);
        _supplyToAave(assets);
        return shares;
    }

    /// @notice Pause, no new loans get issued.
    function pause() external onlyOwner {
        windDown = true;
    }

    /// @notice Liquidate Auction if the auction can be liquidated. Asset is kept in contract but approved to the owner
    /// Owner can withdraw at any time, but if admin is changed, the approval isn't updated.
    /// @param _poolId The pool ID
    function liquidateAuction(uint256 _poolId) public virtual {
        try LAN.liquidate(_poolId) {
            (
                ,
                ,
                ,
                address collectionAddress,
                uint256 nftId,
                ,
                ,
                ,
                ,
                ,

            ) = readLoan(_poolId);
        } catch (string memory reason) {
            emit log(reason);
        }
        beginAuction(amountPaid[_poolId], 10, collectionAddress, nftId);
    }

    /// @notice Call the LAN contract and make a bid with specific parameters. LTV is determined inclusive of accrued interest.
    /// Update utilization when the loan is issued.
    /// @param _poolId The pool ID
    /// @param _borrowAmount The amount requested to borrow
    /// @param _apr The APR for the borrow
    function bidWithParams(
        uint256 _poolId,
        uint256 _borrowAmount,
        uint256 _apr
    ) public shutdown onlyOwner {
        require(_apr >= minAPY, "BaseBid: APY below minAPY");
        (
            ,
            address token,
            ,
            address collectionAddress,
            uint256 nftId,
            ,
            uint256 endTime,
            ,
            bool liquidatable,

        ) = readLoan(_poolId);
        require(liquidatable == true, "Basebid: Liquidatable not true");
        require(token == baseAsset, "BaseBid: different base asset");
        require(
            collectionAddress = Wrapper,
            "BaseBid: Collateral not in a wrapper"
        );
        require(
            _calculateLTV(nftId, endTime, _apr) >= _borrowAmount,
            "BaseBid: Borrow Amount too high"
        );
        _withdrawFromAave(_borrowAmount);
        try LAN.bid(_poolId, _borrowAmount, apr) {
            emit newLoan(collectionAddress, apr, poolId, bidAmount);
            _utilization();
            amountPaid[_poolId] = _borrowAmount;
        } catch (string memory reason) {
            _supplyToAave(_borrowAmount);
            emit log(reason);
    }

    /// @notice Sum the value of whitelisted assets contained in the NFT wrapper. Nonwhitelisted assets are 0.
    /// @param nftId The ID of the NFT for the wrapper contract
    /// @param endTime The amount requested to borrow
    /// @param apr The APR for the borrow
    function _calculateLTV(
        uint256 nftId,
        uint256 endTime,
        uint256 apr
    ) internal returns (uint256) {
        address[] memory tokens = Wrapper.getTokens(nftId);
        uint256[] memory amounts = Wrapper.getAmounts(nftId);
        whitelists[tokens[i]];
        // loop through all assets and calculate borrowable USD
        uint256 borrowableUSD; // 18 decimal places
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ) {
            Whitelist memory whitelist = whitelists[tokens[i]];
            // Check if token is on whitelist - skip if not
            if (whitelist.oracle != address(0)) {
                // getUnderlyingPrice returns price in 18 decimals and USD
                uint256 collateralPrice = IPriceOracle(whitelist.oracle)
                    .getUnderlyingPrice(tokens[i]);
                borrowableUSD +=
                    (amounts[i] * whitelist[token].LTV * collateralPrice) /
                    10**26;
            }
            unchecked {
                ++i;
            }
        }
        uint256 elapsedTime = endTime - block.timestamp;
        uint256 basePrice = IPriceOracle(baseAssetOracle).getUnderlyingPrice(
            baseAsset
        );
        uint256 loanValue = _calculateLoanValue(
            borrowableUSD,
            elapsedTime,
            apr
        );
        return loanValue / basePrice;
    }

    /// @notice Automatically bid the highest possible bid, using bidWithParams
    /// @param _poolId Pool ID
    function automaticBid(uint256 _poolId) external shutdown onlyOwner {
        (, , , , , uint256 nftId, , , uint256 apr, , , ) = readLoan(_poolId);
        bidWithParams(_poolId, _calculateLTV(nftId), apr);
    }

    function _supplyToAave(uint256 _amount) internal {
        pool.supply(baseAsset, _amount, address(this), 0);
    }

    function _withdrawFromAave(uint256 _amount) internal {
        pool.withdraw(baseAsset, _amount, address(this));
    }
}
