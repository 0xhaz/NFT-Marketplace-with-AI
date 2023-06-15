// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "hardhat/console.sol";

error NFTMarketplace__NotOwner();

contract NFTMarketplace is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;
    address payable private _owner;
    uint256 private c_listingPrice = 0.025 ether;
    address private _creator;
    uint256 private c_royaltyFee = 10;

    struct MarketItem {
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        address payable creator;
        uint256 royaltyFee;
        bool sold;
    }

    event MarketItemCreated(
        uint256 indexed tokenId,
        address payable seller,
        address payable owner,
        address indexed creator,
        uint256 royaltyFee
    );

    mapping(uint256 => MarketItem) private s_idToMarketItem;
    mapping(uint256 => bool) private s_tokenExist;
    mapping(uint256 => uint256) private s_tokenToRoyaltyFee;

    modifier onlyOwner() {
        if (msg.sender != _creator) revert NFTMarketplace__NotOwner();
        _;
    }

    modifier onlyCreator(uint256 _tokenId) {
        if (msg.sender != s_idToMarketItem[_tokenId].creator)
            revert NFTMarketplace__NotOwner();
        _;
    }

    constructor() ERC721("BRZRK Token", "BRZRK") {
        _creator = payable(msg.sender);
    }

    function createToken(
        string memory _tokenURI,
        uint256 _price
    ) public payable returns (uint) {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);

        createMarketItem(newTokenId, _price);

        return newTokenId;
    }

    function createMarketItem(uint256 _tokenId, uint256 _price) public payable {
        if (_price == 0) {
            _price = c_listingPrice;
        }

        if (msg.value <= c_listingPrice) {
            revert();
        }

        MarketItem storage item = s_idToMarketItem[_tokenId];

        item.tokenId = _tokenId;
        item.seller = payable(msg.sender);
        item.owner = payable(address(this));
        item.price = _price;
        item.creator = payable(msg.sender);
        item.royaltyFee = c_royaltyFee;
        item.sold = false;

        s_tokenExist[_tokenId] = true;

        s_tokenToRoyaltyFee[_tokenId] = _calculateRoyaltyFee(
            _price,
            c_royaltyFee
        );

        _transfer(msg.sender, address(this), _tokenId);

        emit MarketItemCreated(
            _tokenId,
            payable(msg.sender),
            payable(msg.sender),
            msg.sender,
            c_royaltyFee
        );
    }

    function setListingPrice(uint256 _newPrice) external onlyOwner {
        c_listingPrice = _newPrice;
    }

    function setRoyaltyFee(
        uint256 _newFee,
        uint256 _tokenId
    ) external onlyCreator(_tokenId) {
        c_royaltyFee = _newFee;
    }

    function getListingPrice() public view returns (uint256) {
        return c_listingPrice;
    }

    function getRoyaltyFeeForTokenId(
        uint _tokenId
    ) public view returns (uint256) {
        return s_tokenToRoyaltyFee[_tokenId];
    }

    function getRoyaltyFee() public view returns (uint256) {
        return c_royaltyFee;
    }

    function _calculateRoyaltyFee(
        uint256 _salePrice,
        uint256 _royaltyRate
    ) internal pure returns (uint256) {
        return (_salePrice * _royaltyRate) / 100;
    }
}
