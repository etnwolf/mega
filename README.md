# MEGA Token and NFT Ecosystem

This repository contains the smart contracts for the MEGA token and MEGA OGs NFT ecosystem, built on the Electroneum blockchain. The ecosystem comprises three core contracts:

1. **`MegaOGs`**: An ERC721 NFT contract representing the "MEGA OGs" collection.
2. **`MegaToken`**: An ERC20 token contract with features like staking, governance vesting, and liquidity provision.
3. **`MegaDistributionV2`**: A contract for distributing ETN rewards to MEGA OGs NFT holders.

Together, these contracts create a cohesive system where NFT holders receive both MEGA ERC20 token airdrops and periodic ETN rewards, while the MEGA token supports staking and liquidity on ElectroSwap V3.

---

## MegaOGs NFT Contract

The `MegaOGs` contract is an ERC721-compliant NFT contract that allows users to mint and manage tokens in the "MEGA OGs" collection. It inherits from OpenZeppelin's `ERC721Enumerable` and `ERC721URIStorage` for enumeration and metadata support.

### Contract Address
`MegaOGs` is deployed on `Electroneum Mainnet` at address [0x56B33D971AfC1d2CEA35f20599E8EF5094Ffd399](https://blockexplorer.electroneum.com/token/0x56B33D971AfC1d2CEA35f20599E8EF5094Ffd399?tab=contract)

### Key Features
- **Minting**: Users can mint NFTs by paying a specified price in ETN, transferable to the contract owner. Example: `mint(uint256 count)` requires `count * mintPrice` ETN.
- **Supply Management**: Default maximum supply is 365 tokens, adjustable by the owner via `updateMaxSupply(uint256 _newMax)`.
- **Metadata**: Tokens have off-chain metadata accessible via a base URI (e.g., `baseTokenURI + tokenId + ".json"`), settable by the owner with `setBaseURI(string memory baseURI)`.
- **Enumeration**: Supports retrieving all tokens and their owners, critical for reward distribution in other contracts.
- **Ownership Controls**: The owner can update the mint price (`updatePrice(uint256 _price)`), maximum supply, and base URI.

### Purpose
The `MegaOGs` contract serves as the foundation for the ecosystem, defining NFT ownership that determines eligibility for rewards and airdrops.

### Links
The [MEGA OGs NFT Collection](https://app.electroswap.io/nfts/collection/0x56B33D971AfC1d2CEA35f20599E8EF5094Ffd399) can be found on ElectroSwap's NFT marketplace.

---

## MegaToken Contract

The `MegaToken` contract is an ERC20 token contract with advanced features for token distribution, staking, governance vesting, and liquidity provision on ElectroSwap V3.

### Contract Address
`MegaToken` is deployed on `Electroneum Mainnet` at address [0xB902acda576Bd66f6fedE70262D8964E5C5C1f49](https://blockexplorer.electroneum.com/token/0xB902acda576Bd66f6fedE70262D8964E5C5C1f49?tab=contract)

### Key Features

#### Token Allocations
- **Total Supply**: 210,000,000 MEGA tokens (with 18 decimals).
- **Dev Team**: 5% (10,500,000 tokens) transferred to the dev team upon launch.
- **NFT Airdrop**: 10% (21,000,000 tokens) distributed to MEGA OGs NFT holders.
- **Governance Vesting**: 12% (25,200,000 tokens) vested over 12 months for the dev team.
- **Staking Rewards**: 3% (6,300,000 tokens) allocated for staking rewards.
- **Liquidity Provision**: 70% (147,000,000 tokens) paired with ETN for ElectroSwap V3 liquidity.

#### Airdrop to NFT Holders
- During the `launch()` function, 10% of the supply is distributed to `MegaOGs` NFT holders starting from `startingAirdropToken`.
- Distribution is proportional to the number of NFTs owned, calculated in `_distributeToNFTHolders()`.

#### Staking
- **Deposit/Withdraw**: Users stake MEGA tokens with `stakingDeposit(uint256 amount)` and withdraw via `stakingWithdrawal(uint256 amount)`.
- **Rewards**: Calculated based on staking duration and share of total staked tokens, claimable with `stakingRewardsClaim()`.
- **Reward Pool**: Initialized with 3% of supply; the dev team can top it up using `stakingRewardsTopUp(uint256 addedAmount, uint256 newStakingPeriodInDays)`.

#### Governance Vesting
- 12% of the supply vests over 12 monthly periods, starting 30 days after launch.
- The dev team withdraws vested tokens with `governanceWithdrawVestedTokens()`.

#### Liquidity Provision
- During `launch()`, 70% of the supply is paired with ETN to create a full-range liquidity position on ElectroSwap V3 (0.3% fee tier).
- The position is locked for 270 days via the V3 Locker, with ownership transferred to the dev team.

### Purpose
The `MegaToken` contract manages the MEGA token economy, incentivizing NFT holders with airdrops, rewarding stakers, and ensuring liquidity for trading.

### Links
The [MEGA ERC-20 Token](https://app.electroswap.io/swap?inputCurrency=ETN&outputCurrency=0xB902acda576Bd66f6fedE70262D8964E5C5C1f49) has 100% locked liquidity and is tradeable on ElectroSwap.

---

## MegaDistributionV2 Contract

The `MegaDistributionV2` contract distributes ETN rewards to `MegaOGs` NFT holders based on accumulated rewards per token.

### Contract Address
`MegaDistributionV2` is deployed on `Electroneum Mainnet` at address [0x7B6E1F1d5783fFB4b1a9008107ceba30EA9CdBc6](https://blockexplorer.electroneum.com/address/0x7B6E1F1d5783fFB4b1a9008107ceba30EA9CdBc6?tab=contract)

### Key Features
- **Reward Accumulation**: ETN sent to the contract (via `receive()` or `fallback()`) increases `accRewardsPerToken` using `_processIncomingFee(uint256 amount)`.
- **Reward Distribution**: 
  - `distributeRewards()`: Distributes rewards to all 365 tokens (if minted).
  - `distributeRewardsForTokens(uint256[] memory tokenIds)`: Distributes rewards to specified token IDs.
- **Reward Tracking**: Uses `rewardInfo` mapping to store the last claimed rewards per token, ensuring no double-claiming.
- **Security**: Employs `ReentrancyGuard` to prevent reentrancy attacks during distribution.

### Purpose
This contract incentivizes holding `MegaOGs` NFTs by exposing a public function that distributes ETN rewards based on NFT ownership.

---

## Interactions Between Contracts

The contracts interact to form a unified ecosystem:

1. **MegaOGs and MegaToken**:
   - `MegaToken` queries `MegaOGs` via `IERC721Enumerable` to identify NFT owners for the airdrop in `_distributeToNFTHolders()`.
   - The airdrop occurs during `launch()`, linking NFT ownership to MEGA token rewards.

2. **MegaOGs and MegaDistributionV2**:
   - `MegaDistributionV2` uses `MegaOGs` to determine NFT owners during reward distribution in `_distributeRewardsForTokens(uint256[] memory tokenIds)`.
   - ETN rewards are sent to owners based on `accRewardsPerToken`.

3. **MegaToken and External Contracts**:
   - Interacts with `WETN` for wrapping ETN during liquidity provision.
   - Uses `nftPositionManager` and `v3Locker` to create and lock a liquidity pool on ElectroSwap V3.

**Key Distinction**: 
- `MegaToken` distributes MEGA ERC20 tokens as a one-time airdrop.
- `MegaDistributionV2` distributes ETN rewards periodically, based on incoming ETN.

There is no direct interaction between `MegaToken` and `MegaDistributionV2`; their connection is indirect through `MegaOGs` NFT ownership.

---

## Usage

### Deployment Steps
1. **Deploy MegaOGs**:
   - Constructor: `MegaOGs(uint256 _price, string memory _baseTokenURI)`.
   - Set initial mint price and base URI.

2. **Deploy MegaToken**:
   - Constructor: `MegaToken(address _wetn, address _nftPositionManager, address _v3Locker, address _megaOgsNft, uint _startingAirdropToken)`.
   - Provide addresses for WETN, ElectroSwap V3 contracts, `MegaOGs`, and the starting NFT ID for the airdrop.

3. **Deploy MegaDistributionV2**:
   - Constructor: `MegaDistributionV2(address megaOGs, address wetn)`.
   - Provide `MegaOGs` and WETN addresses.

4. **Launch MegaToken**:
   - Call `launch()` with sufficient ETN to cover liquidity and locker fees (e.g., `etnFlatFee * 1e18`).

5. **Distribute ETN Rewards**:
   - Send ETN to `MegaDistributionV2`, then call `distributeRewards()` or `distributeRewardsForTokens(uint256[] memory tokenIds)`.

### Example Workflow
- Users mint NFTs via `MegaOGs.mint(uint256 count)`.
- Deployer launches `MegaToken`, triggering the airdrop to NFT holders.
- ETN is sent to `MegaDistributionV2`, which distributes rewards to NFT holders when triggered.

For detailed function parameters, refer to the contract source code.

---

## Security Considerations

- **Reentrancy**: `MegaToken` and `MegaDistributionV2` use `ReentrancyGuard` to prevent reentrancy attacks.
- **Access Control**: Functions like `launch()`, `governanceWithdrawVestedTokens()`, and `updatePrice()` are restricted to the owner or dev team.
- **Token Approvals**: Ensure approvals are set for `WETN` and MEGA tokens when interacting with ElectroSwap or staking.
- **ETN Handling**: Verify sufficient ETN balances for minting, launching, and reward distribution.

---


