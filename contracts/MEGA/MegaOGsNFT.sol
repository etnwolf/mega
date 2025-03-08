// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

interface IMintable {
    // Returns the price of a single mint in ETN 
    // (padded with 18 zeros due to decimals not being supported)
    function mintPrice() external view returns (uint256);

    // Returns the number of tokens that can be minted by an account 
    //(ensuring the returned count does not exceed the max supply)
    function mintableCount(address account) external view returns (uint256);

    // Mints the specified number of tokens
    function mint(uint256 mintCount) external payable;
}

contract MegaOGs is IMintable, Ownable, ERC721Enumerable, ERC721URIStorage {
    
    uint256 private maxTokens;
    uint256 private numTokens;
    string private baseTokenURI;

    uint256 public mintPrice;
    
    constructor(uint256 _price, string memory _baseTokenURI) ERC721("MEGA OGs", "OG") Ownable(msg.sender) {
        mintPrice = _price;
        baseTokenURI = _baseTokenURI;
        maxTokens = 365;
    }
    
    function mint(uint256 count) public payable {

        require(maxTokens > count + numTokens, "Cannot mint more than max supply");

        if(msg.sender != owner()){
            require(count * mintPrice == msg.value, "Invalid payment amount");
            payable(owner()).transfer(msg.value);
        }
        
        uint256[] memory nftIds = new uint256[](count);
        for(uint256 i = 0; i < count; i++){
            numTokens++;
            uint256 nftId = numTokens;
            nftIds[i] = nftId;
            _safeMint(msg.sender, nftId);
        }

    }

    function mintableCount(address addr) public view returns (uint256) {
        if(numTokens < maxTokens){
            return maxTokens - numTokens;
        }
        return 0;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override(ERC721, ERC721URIStorage) returns (string memory) {
        require(tokenId <= numTokens, "Non-existent token");
        string memory uri = super.tokenURI(tokenId);
        return string.concat(uri, ".json");
    }

    function _update(address dest, uint256 nftId, address auth) internal virtual override(ERC721Enumerable, ERC721) returns (address) {
        return super._update(dest, nftId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal virtual override(ERC721Enumerable, ERC721) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
    
    function updatePrice(uint256 _price) public onlyOwner {
        mintPrice = _price;
    }

    function updateMaxSupply(uint256 _newMax) public onlyOwner {
        require(_newMax > numTokens, "Must be greater than current supply");
        maxTokens = _newMax;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }
}
