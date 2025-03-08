// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MegaDistributionV2 is ReentrancyGuard, Ownable {

    mapping(uint256 => TokenReward) public rewardInfo;
    mapping(address => uint256) private tmpRewardsPerOwner;
    
    IERC721Enumerable public immutable megaOGsNft;
    IWETN public immutable WETN;
    
    uint256 public accRewardsPerToken;
    uint256 public accRewardsClaimed;
    uint256 public accRewardsReceived;
    
    constructor(address megaOGs, address wetn) Ownable(msg.sender) {
        megaOGsNft = IERC721Enumerable(megaOGs);
        WETN = IWETN(wetn);
    }
   
    function getTokenRewardAmount(uint256 tokenId) external view returns (uint256) {
        return (accRewardsPerToken - rewardInfo[tokenId].lastClaimRewards) / 1e18;
    }
    
    function distributeRewards() external nonReentrant {
        
        uint256[] memory tokenIds = new uint256[](365);
        
        for (uint256 tokenId = 1; tokenId <= 365; tokenId++) {
            tokenIds[tokenId - 1] = tokenId;
        }
        _distributeRewardsForTokens(tokenIds);
    }

    function distributeRewardsForTokens(uint256[] memory tokenIds) public nonReentrant {
        _distributeRewardsForTokens(tokenIds);
    }

    function _distributeRewardsForTokens(uint256[] memory tokenIds) internal {
        address[] memory owners = new address[](tokenIds.length);
        uint256 ownersCount = 0;
        uint256 mintedTokens = megaOGsNft.totalSupply();

        // Collect rewards per wallet
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            if(tokenId > 0 && tokenId <= mintedTokens){
                TokenReward storage rewardRecord = rewardInfo[tokenId];
            
                uint256 reward = accRewardsPerToken - rewardRecord.lastClaimRewards;

                if (reward > 0) {
                    rewardRecord.lastClaimRewards = accRewardsPerToken;

                    address tokenOwner = megaOGsNft.ownerOf(tokenId);
                    if (tmpRewardsPerOwner[tokenOwner] == 0) {
                        owners[ownersCount] = tokenOwner;
                        ownersCount++;
                    }
                    tmpRewardsPerOwner[tokenOwner] += reward;
                }
            }
        }

        assembly {
            mstore(owners, ownersCount)
        }

        uint256 totalToSend;

        // Distribute rewards to owners
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            uint256 ownerRewards = tmpRewardsPerOwner[owner] / 1e18;
            if (ownerRewards > 0) {
                totalToSend += ownerRewards;
                (bool success, ) = owner.call{value: ownerRewards}("");
                require(success, "Reward send failed");
            }
            tmpRewardsPerOwner[owner] = 0;
        }

        require(totalToSend > 0, "Nothing to send");
        accRewardsClaimed += totalToSend;
    }

    function _processIncomingFee(uint256 amount) internal nonReentrant {

        uint wetnBalance = WETN.balanceOf(address(this));

        if(wetnBalance > 0){
            WETN.withdraw(wetnBalance);
            amount = amount + wetnBalance;
        }

        uint256 perToken = (amount * 1e18) / 365;
        accRewardsPerToken += perToken;
        accRewardsReceived += amount;
    }

    struct TokenReward {
        uint256 lastClaimRewards;
    }

    receive() external payable {
        if(msg.sender != address(WETN)){
            _processIncomingFee(msg.value);
        }
    }

    fallback() external payable {
        if(msg.sender != address(WETN)){
            _processIncomingFee(msg.value);
        }
    }
}

interface IWETN {
    function withdraw(uint) external;
    function balanceOf(address addr) external returns (uint);
}
