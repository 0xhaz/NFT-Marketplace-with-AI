// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

error NftMarketplace__NotOwner();
error NftMarketplace__PriceHaveNoValue();
error NftMarketplace__ListingPriceIsNotMet();
error NftMarketplace__FraudDetected();
error NftMarketPlace__BiddingNotAllowed();
error NftMarketplace__ItemSold();
error NftMarketplace__TokenIdDoesNotExist();

contract NftMarketplace is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    address payable tokenOwner;
    uint256 private c_listingPrice = 0.025 ether;
    uint256 private c_creatorRoyaltyFee = 10;
    uint256 private c_contractFee = 2;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;

    mapping(uint256 => MarketItem) private s_idToMarketItem;
    mapping(address => mapping(uint256 => CartItem)) private s_cartItems;
    mapping(address => CartItem[]) private s_cartItemsByAddress;
    mapping(uint256 => bool) private s_tokenIdExist;

    // AI-based fraud detection system
    mapping(address => uint256) private s_purchaseCounts;
    mapping(address => uint256) private s_lastPurchaseTimestamps;
    uint256 private c_maxPurchasesPerMinute = 1;
    uint256 private c_purchaseCooldownSeconds = 60;

    struct CartItem {
        uint256 tokenId;
        uint256 quantity;
    }

    struct MarketItem {
        uint256 tokenId;
        address payable seller;
        address payable tokenOwner;
        uint256 price;
        bool sold;
        uint256 highestBid;
        address payable highestBidder;
        uint256 endTime;
        address payable creator;
        uint256 royaltyFee;
    }

    event MarketItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold
    );

    event MarketItemSold(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold
    );

    event MarketBidCreated(
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bidPrice
    );

    constructor() ERC721("BRZRK Token", "BRZRK") {
        tokenOwner = payable(msg.sender);
    }

    function createToken(
        string memory _tokenURI,
        uint256 _price
    ) public payable returns (uint256) {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);

        _createMarketItem(newTokenId, _price);

        return newTokenId;
    }

    function resellToken(uint256 _tokenId, uint256 _price) public payable {
        MarketItem storage item = s_idToMarketItem[_tokenId];

        if (item.seller != msg.sender) revert NftMarketplace__NotOwner();
        if (msg.value != c_listingPrice)
            revert NftMarketplace__ListingPriceIsNotMet();

        item.sold = false;
        item.price = _price;
        item.tokenOwner = payable(address(this));

        _itemsSold.decrement();

        _transfer(msg.sender, address(this), _tokenId);
    }

    function createMarketSale(uint256 _tokenId) public payable {
        MarketItem storage item = s_idToMarketItem[_tokenId];

        if (item.seller != msg.sender) revert NftMarketplace__NotOwner();
        if (msg.value != c_listingPrice)
            revert NftMarketplace__ListingPriceIsNotMet();
        if (!item.sold) revert NftMarketplace__ItemSold();

        address payable seller = item.seller;
        address payable creator = item.creator;
        uint256 royaltyFee = _calculateRoyaltyFee(item.price, item.royaltyFee);
        uint256 sellerProfit = item.price - royaltyFee;
        uint256 contractOwnerProfitShare = (item.price * c_contractFee) / 100;
        uint256 sellerRemainingProfit = sellerProfit - contractOwnerProfitShare;

        // Transfer the token to the buyer
        item.tokenOwner.transfer(item.price);
        seller.transfer(sellerRemainingProfit);
        creator.transfer(royaltyFee);
        tokenOwner.transfer(contractOwnerProfitShare);

        // Update market item status
        item.sold = true;
        item.highestBid = item.price;
        item.highestBidder = item.tokenOwner;
        item.endTime = block.timestamp;

        // Transfer NFT to the buyer
        _transfer(address(this), msg.sender, _tokenId);

        // Update purchase counts and timestamps for fraud detection
        s_purchaseCounts[msg.sender]++;
        s_lastPurchaseTimestamps[msg.sender] = block.timestamp;

        // Emit an event for the sale of the token
        emit MarketItemSold(
            _tokenId,
            item.seller,
            item.tokenOwner,
            item.price,
            item.sold
        );
    }

    function createBidMarketSale(
        uint256 _tokenId,
        uint256 _bidPrice
    ) public payable {
        MarketItem storage item = s_idToMarketItem[_tokenId];

        // check if auction is ongoing and bid price is higher than current highest bid
        if (
            item.sold ||
            block.timestamp > item.endTime ||
            _bidPrice <= item.highestBid
        ) {
            revert NftMarketPlace__BiddingNotAllowed();
        }

        // AI-based fraud detection system: check for suspicious activity
        if (
            s_purchaseCounts[msg.sender] >= c_maxPurchasesPerMinute &&
            block.timestamp - s_lastPurchaseTimestamps[msg.sender] <
            c_purchaseCooldownSeconds
        ) {
            payable(msg.sender).transfer(msg.value);
            revert NftMarketplace__FraudDetected();
        }

        if (item.highestBid > 0) {
            // Pay back the previous bidder
            item.highestBidder.transfer(item.highestBid);
        }

        // Set the new highest bid and bidder
        item.highestBid = _bidPrice;
        item.highestBidder = payable(msg.sender);

        // Reset the end time if a bid is made with less than 5 minutes remaining
        if (item.endTime - block.timestamp < 5 minutes) {
            item.endTime = block.timestamp + 5 minutes;
        }

        if (msg.value < _bidPrice) {
            // if the bid is not high enough, add the bid to the current highest bidder's balance
            item.highestBidder.transfer(msg.value);
        } else {
            // if the bid is high enough, transfer the NFT to the highest bidder and update market item
            item.tokenOwner = item.highestBidder;
            item.seller.transfer(item.price);

            // Calculate and distribute the royalty fee to the creator
            uint256 royaltyFee = _calculateRoyaltyFee(
                item.price,
                item.royaltyFee
            );
            payable(item.creator).transfer(royaltyFee);

            // calculate the profit for the seller
            uint256 sellerProfit = item.price - royaltyFee;

            // Calculate the profit share for the contract owner (c_contractFee % of the seller's profit)
            uint256 contractOwnerProfitShare = (sellerProfit * c_contractFee) /
                100;
            tokenOwner.transfer(contractOwnerProfitShare);

            // Calculate the remaining profit for the seller after the contract owner's share
            uint256 sellerRemainingProfit = sellerProfit -
                contractOwnerProfitShare;

            // Transfer the remaining profit to the seller
            item.seller.transfer(sellerRemainingProfit);

            // AI-based fraud detection system: update purchase counts and timestamps
            s_purchaseCounts[msg.sender]++;
            s_lastPurchaseTimestamps[msg.sender] = block.timestamp;
        }

        _itemsSold.increment();

        _transfer(address(this), item.highestBidder, _tokenId);

        emit MarketBidCreated(_tokenId, item.highestBidder, _bidPrice);
    }

    function addToCart(uint256 _tokenId, uint256 _quantity) public {
        if (!s_tokenIdExist[_tokenId])
            revert NftMarketplace__TokenIdDoesNotExist();
        if (!s_idToMarketItem[_tokenId].sold) revert NftMarketplace__ItemSold();

        // Add the item to the buyer's cart and update the quantity
        bool itemExists = false;
        for (uint256 i = 0; i < s_cartItemsByAddress[msg.sender].length; i++) {
            if (s_cartItemsByAddress[msg.sender][i].tokenId == _tokenId) {
                s_cartItemsByAddress[msg.sender][i].quantity += _quantity;
                itemExists = true;
                break;
            }
        }

        if (!itemExists) {
            s_cartItemsByAddress[msg.sender].push(
                CartItem(_tokenId, _quantity)
            );
        }
    }

    function removeFromCart(uint256 _tokenId) public {
        CartItem[] storage cart = s_cartItemsByAddress[msg.sender];

        // Find the index of the item in the cart
        uint256 index = _findCartItemIndex(cart, _tokenId);

        // Remove the item from the cart
        if (index < cart.length) {
            // Move the last item to the deleted item's index
            cart[index] = cart[cart.length - 1];
            // Remove the last item
            cart.pop();
        }
    }

    function _findCartItemIndex(
        CartItem[] storage cart,
        uint256 _tokenId
    ) private view returns (uint256) {
        for (uint256 i = 0; i < cart.length; i++) {
            if (cart[i].tokenId == _tokenId) {
                return i;
            }
        }

        return cart.length;
    }

    function purchaseItems() public payable {
        CartItem[] storage cart = s_cartItemsByAddress[msg.sender];

        // Iterate over the items in the cart
        for (uint256 i = 0; i < cart.length; i++) {
            uint256 tokenId = cart[i].tokenId;
            uint256 quantity = cart[i].quantity;

            // Purchase the item individually
            for (uint256 j = 0; j < quantity; j++) {
                createMarketSale(tokenId);
            }

            // Remove the item from the cart
            removeFromCart(tokenId);
        }
    }

    function updateListingPrice(uint256 _listingPrice) public payable {
        if (tokenOwner != msg.sender) revert NftMarketplace__NotOwner();
        c_listingPrice = _listingPrice;
    }

    function setRoyaltyFee(uint256 _royaltyFee) public onlyOwner {
        c_creatorRoyaltyFee = _royaltyFee;
    }

    function setContractFee(uint256 _contractFee) public onlyOwner {
        c_contractFee = _contractFee;
    }

    function getListingPrice() public view returns (uint256) {
        return c_listingPrice;
    }

    function getRoyaltyFee(uint256 _tokenId) public view returns (uint256) {
        return s_idToMarketItem[_tokenId].royaltyFee;
    }

    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint itemCount = _tokenIds.current();
        uint unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);

        for (uint i = 0; i < itemCount; i++) {
            if (s_idToMarketItem[i + 1].tokenOwner == address(this)) {
                uint currentId = i + 1;

                MarketItem storage currentItem = s_idToMarketItem[currentId];

                items[currentIndex] = currentItem;

                currentIndex += 1;
            }
        }

        return items;
    }

    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint totalItemCount = _tokenIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;

        for (uint i = 0; i < totalItemCount; i++) {
            if (s_idToMarketItem[i + 1].tokenOwner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);

        for (uint i = 0; i < totalItemCount; i++) {
            if (s_idToMarketItem[i + 1].tokenOwner == msg.sender) {
                uint currentId = i + 1;

                MarketItem storage currentItem = s_idToMarketItem[currentId];

                items[currentIndex] = currentItem;

                currentIndex += 1;
            }
        }

        return items;
    }

    function fetchMyBids() public view returns (MarketItem[] memory) {
        uint itemCount = _tokenIds.current();
        uint currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](_itemsSold.current());

        for (uint i = 0; i < itemCount; i++) {
            if (
                s_idToMarketItem[i + 1].highestBidder == msg.sender &&
                !s_idToMarketItem[i + 1].sold
            ) {
                uint currentId = i + 1;

                MarketItem storage currentItem = s_idToMarketItem[currentId];

                items[currentIndex] = currentItem;

                currentIndex += 1;
            }
        }

        return items;
    }

    function fetchItemsListed() public view returns (MarketItem[] memory) {
        uint totalItemCount = _tokenIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;

        for (uint i = 0; i < totalItemCount; i++) {
            if (s_idToMarketItem[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);

        for (uint i = 0; i < totalItemCount; i++) {
            if (s_idToMarketItem[i + 1].seller == msg.sender) {
                uint currentId = i + 1;

                MarketItem storage currentItem = s_idToMarketItem[currentId];

                items[currentIndex] = currentItem;

                currentIndex += 1;
            }
        }

        return items;
    }

    function _createMarketItem(uint256 _tokenId, uint256 _price) private {
        if (_price < 0) revert NftMarketplace__PriceHaveNoValue();
        if (msg.value != c_listingPrice)
            revert NftMarketplace__ListingPriceIsNotMet();

        s_idToMarketItem[_tokenId] = MarketItem(
            _tokenId,
            payable(msg.sender),
            payable(address(0)),
            _price,
            false,
            0,
            payable(address(0)),
            0,
            payable(msg.sender),
            c_creatorRoyaltyFee
        );

        _transfer(msg.sender, address(this), _tokenId);

        emit MarketItemCreated(
            _tokenId,
            msg.sender,
            address(this),
            _price,
            false
        );
    }

    function _calculateRoyaltyFee(
        uint256 _salePrice,
        uint256 _royaltyRate
    ) internal pure returns (uint256) {
        return (_salePrice * _royaltyRate) / 100;
    }
}
