// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./TickMath.sol";

/**
 * MEGA ERC-20 token contract with NFT airdrop distribution, governance vesting, and ElectroSwap V3 liquidity provision & locking
 * 
 * Website: https://megaonetn.com
 * X: https://x.com/megatoken_etn
 * Telegram: https://t.me/MEGAonETN
 */
contract MegaToken is ERC20, ReentrancyGuard {
    
    // State variables
    address public devTeam;                 // Address of the development team
    uint256 public startingAirdropToken;    // First NFT token that will receive airdrop

    // Contract addresses
    address immutable WETN;                 // WETN address
    address immutable nftPositionManager;   // ElectroSwap V3 Position Manager
    address immutable v3Locker;             // ElectroSwap V3 Liquidity Locker
    address immutable megaOgsNft;           // Address of the MEGA OGs NFT contract
    
    // Token allocations (with 18 decimals)
    uint256 constant TOTAL_SUPPLY = 210_000_000 * 1e18;                 // 210 million tokens
    uint256 constant DEV_TEAM_ALLOCATION = (TOTAL_SUPPLY * 5) / 100;    // 5% for dev team
    uint256 constant NFT_AIRDROP = (TOTAL_SUPPLY * 10) / 100;           // 10% for NFT holders
    uint256 constant GOVERNANCE_TOKENS = (TOTAL_SUPPLY * 12) / 100;     // 12% for governance vesting
    uint256 constant STAKING_TOKENS = (TOTAL_SUPPLY * 3) / 100;         // 3% for staking
    uint256 constant LIQUIDITY_TOKENS = (TOTAL_SUPPLY * 70) / 100;      // 70% for liquidity pool

    // Governance Token Vesting 
    uint256 constant VESTING_START_OFFSET = 30 days;      // Vesting starts 1 month after deployment
    uint256 constant VESTING_PERIOD = 30 days;            // Monthly vesting periods
    uint256 constant VESTING_PERIODS = 12;                // Total of 12 vesting periods
    uint256 constant TOKENS_PER_PERIOD = GOVERNANCE_TOKENS / VESTING_PERIODS; // Tokens vested per period
    uint256 public launchTimestamp;                       // Timestamp of contract deployment
    uint256 public governanceTokensWithdrawn;             // Total governance tokens withdrawn by dev team
    
    // Staking
    uint256 constant BLOCKS_IN_ONE_YEAR = 6_307_200;    // 365 * 24 * 60 * 60 / 5
    mapping(address => uint256) public stakedTokensByUser;     // Tokens staked per user
    mapping(address => uint256) private userRewardPerTokenAcc; // Reward per token already accounted to user
    mapping(address => uint256) private rewards;        // Rewards accrued per user
    bool public stakingEnabled;                         // Determines if staking is enabled
    uint256 public stakedTotal;                         // Total tokens staked
    uint256 public stakingRewardPoolTokens;             // Total tokens in the reward pool
    uint256 public stakingTotalOwedRewards;             // Total unclaimed rewards across all stakers
    uint256 public stakingRewardPerToken;               // Accumulated reward per staked token
    uint256 public stakingLastUpdateBlock;              // Last block when rewards were updated
    uint256 public stakingRewardRate;                   // Reward per block in wei
    uint256 public stakingPeriodStartBlock;             // Block when staking period starts
    uint256 public stakingPeriodEndBlock;               // Block when staking period ends
    
    // Events
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Launched(uint256 launchTimestamp);
    event TokensAirdropped(uint256 totalDistributed, uint256 holderCount);
    event LiquidityAdded(uint256 tokenId, uint256 amount0, uint256 amount1);
    event LiquidityLocked(uint256 lockId, uint256 duration);
    event GovernanceTokensWithdrawn(address indexed user, uint256 amount);
    event StakingDeposit(address indexed user, uint256 amount);
    event StakingWithdrawal(address indexed user, uint256 amount);
    event StakingRewardClaimed(address indexed user, uint256 amount);
    event StakingRewardsUpdated(uint256 rewardPerToken, uint256 totalOwedRewards, uint256 lastBlockUpdate);
    event StakingRewardsPoolToppedUp(uint256 addedAmount, uint256 rewardPoolBalance, uint256 newRewardRate);
    event StakingEnabled(bool isEnabled);
    event ERC20Recovered(address tokenRecovered, uint256 tokenAmount, address to);

    constructor(address _wetn, address _nftPositionManager, address _v3Locker, address _megaOgsNft, uint _startingAirdropToken) ERC20("MEGA", "MEGA") {
        
        require(_startingAirdropToken > 0, "Invalid starting airdrop token");
        require(_wetn != address(0), "Invalid WETN contract address");
        require(_nftPositionManager != address(0), "Invalid Position Manager contract address");
        require(_megaOgsNft != address(0), "Invalid NFT contract address");

        devTeam = msg.sender;

        WETN = _wetn;
        nftPositionManager = _nftPositionManager;
        v3Locker = _v3Locker;
        megaOgsNft = _megaOgsNft;
        startingAirdropToken = _startingAirdropToken;

        _mint(address(this), TOTAL_SUPPLY);

        stakingRewardPoolTokens = STAKING_TOKENS;
        stakingRewardRate = stakingRewardPoolTokens / BLOCKS_IN_ONE_YEAR; // Initial reward rate
    }

    // Allows users to stake tokens
    function stakingDeposit(uint256 amount) external nonReentrant {

        require(stakingEnabled, "Staking is not enabled");

        // Initialize staking parameters upon first staker deposit
        if(stakingPeriodStartBlock == 0){
            stakingPeriodStartBlock = block.number;
            stakingLastUpdateBlock = stakingPeriodStartBlock;
            stakingPeriodEndBlock = stakingPeriodStartBlock + BLOCKS_IN_ONE_YEAR;
        }

        require(amount > 0, "Cannot stake 0");
        _updateReward(msg.sender);

        // TransferFrom requires prior approval
        bool success = IERC20(address(this)).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        stakedTokensByUser[msg.sender] += amount;
        stakedTotal += amount;
        emit StakingDeposit(msg.sender, amount);
    }

    // Allows users to unstake tokens
    function stakingWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        require(stakedTokensByUser[msg.sender] >= amount, "Insufficient staked amount");
        _updateReward(msg.sender);
        stakedTokensByUser[msg.sender] -= amount;
        stakedTotal -= amount;
        bool success = IERC20(address(this)).transfer(msg.sender, amount);
        require(success, "Transfer failed");
        emit StakingWithdrawal(msg.sender, amount);
    }

    // Calculates the total rewards earned by an account, returns total earned
    function stakingRewardsAvailable(address account) public view returns (uint256) {
        uint256 rewardPerTokenCurrent = stakingRewardPerToken;
        if (stakingEnabled && block.number > stakingLastUpdateBlock && stakedTotal > 0) {
            uint256 blockTo = block.number > stakingPeriodEndBlock ? stakingPeriodEndBlock : block.number;
            uint256 blocksPassed = blockTo - stakingLastUpdateBlock;
            rewardPerTokenCurrent += (stakingRewardRate * blocksPassed * 1e18) / stakedTotal ;
        }
        return ((stakedTokensByUser[account] * (rewardPerTokenCurrent - userRewardPerTokenAcc[account])) / 1e18) + rewards[account];
    }

    // Allows users to claim their accrued rewards
    function stakingRewardsClaim() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            require(stakingRewardPoolTokens >= reward, "Insufficient staking reward pool balance");
            stakingRewardPoolTokens -= reward;
            stakingTotalOwedRewards  -= reward;  // Reduce owed amount
            rewards[msg.sender] = 0;
            bool success = IERC20(address(this)).transfer(msg.sender, reward);
            require(success, "Transfer failed");
            emit StakingRewardClaimed(msg.sender, reward);
        }
    }

    // Updates the reward accumulator and user's rewards
    function _updateReward(address account) internal {
        if (stakingEnabled && block.number > stakingLastUpdateBlock && stakedTotal > 0) {
            uint256 blockTo = block.number > stakingPeriodEndBlock ? stakingPeriodEndBlock : block.number;
            uint256 blocksPassed = blockTo - stakingLastUpdateBlock;
            if (blocksPassed > 0) {
                uint256 newRewards = stakingRewardRate * blocksPassed;
                stakingRewardPerToken += (newRewards * 1e18) / stakedTotal ;
                stakingTotalOwedRewards  += newRewards;  // Accumulate new rewards
                stakingLastUpdateBlock = blockTo;

                emit StakingRewardsUpdated(stakingRewardPerToken, stakingTotalOwedRewards, stakingLastUpdateBlock);
            }
        }
        if (account != address(0)) {
            uint256 earnedAmount = stakingRewardsAvailable(account); // Assume earned() calculates rewards
            rewards[account] = earnedAmount;
            userRewardPerTokenAcc[account] = stakingRewardPerToken;
        }
    }

    function governanceTokensRemaining() external view returns (uint256){
        return GOVERNANCE_TOKENS - governanceTokensWithdrawn;
    }

    // Modifier to restrict functions to the dev team
    modifier onlyTeam() {
        require(msg.sender == devTeam, "Only dev team allowed");
        _;
    }

    function launch() external payable onlyTeam {

        require(launchTimestamp == 0, "Already launched");

        (uint256 etnFlatFee,,) = ILockerV3(v3Locker).fees();

        require(msg.value > etnFlatFee * 1e18, "Invalid ETN amount");
        
        launchTimestamp = block.timestamp;

        // Transfer 5% to dev team immediately
        _transfer(address(this), devTeam, DEV_TEAM_ALLOCATION);

        // Distribute 10% to NFT holders
        _distributeToNFTHolders();

        // Set up liquidity with 70% of tokens and received ETN
        _addLiquidity(etnFlatFee * 1e18);

        emit Launched(launchTimestamp);
    }

    function _distributeToNFTHolders() internal {
        IERC721Enumerable nft = IERC721Enumerable(megaOgsNft);
        uint256 totalNFTs = nft.totalSupply();
        if (totalNFTs == 0) return; // Skip if no NFTs exist

        // Arrays to track unique holders and their balances
        address[] memory uniqueHolders = new address[](totalNFTs);
        uint256[] memory balances = new uint256[](totalNFTs);
        uint256 holderCount = 0;

        // Iterate through all NFTs to aggregate balances per holder
        for (uint256 i = startingAirdropToken; i <= totalNFTs; i++) {
            address owner = nft.ownerOf(i);
            bool found = false;
            for (uint256 k = 0; k < holderCount; k++) {
                if (uniqueHolders[k] == owner) {
                    balances[k] += 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueHolders[holderCount] = owner;
                balances[holderCount] = 1;
                holderCount++;
            }
        }

        // Distribute tokens to each unique holder based on their NFT count
        for (uint256 j = 0; j < holderCount; j++) {
            address holder = uniqueHolders[j];
            uint256 share = (balances[j] * NFT_AIRDROP) / (totalNFTs - startingAirdropToken + 1);
            _transfer(address(this), holder, share);
        }

        emit TokensAirdropped(NFT_AIRDROP, holderCount);
    }

    function _addLiquidity(uint256 lockerFlatFee) internal {
        
        // Wrap received ETN to WETN
        uint256 etnAmount = msg.value - lockerFlatFee;
        if (etnAmount > 0) {
            IWETN(WETN).deposit{value: etnAmount}();
        }
        uint256 wetnAmount = IWETN(WETN).balanceOf(address(this));
        require(wetnAmount > 0, "No ETN provided for liquidity");

        // Determine token order for ElectroSwap (lower address is token0)
        address token0 = address(this) < WETN ? address(this) : WETN;
        address token1 = address(this) < WETN ? WETN : address(this);
        uint256 amount0Desired = token0 == address(this) ? LIQUIDITY_TOKENS : wetnAmount;
        uint256 amount1Desired = token1 == address(this) ? LIQUIDITY_TOKENS : wetnAmount;

        // Calculate initial price based on token amounts (simplified to exact ratio)
        uint256 P_fp = (amount1Desired * 1e18) / amount0Desired; // Price in fixed-point with 18 decimals
        uint256 sqrt_P_fp = Math.sqrt(P_fp);         // Square root of the price
        uint160 exactSqrtPriceX96 = uint160((sqrt_P_fp * (1 << 96)) / 1e9); // Scale to 2^96

        // Align sqrtPriceX96 with a valid tick
        int24 currentTick = TickMath.getTickAtSqrtRatio(exactSqrtPriceX96);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);

        // Create and initialize the pool if it doesn't exist
        INonfungiblePositionManager(nftPositionManager).createAndInitializePoolIfNecessary(
            token0,
            token1,
            3000, // 0.3% fee tier
            sqrtPriceX96
        );

        // Approve token spending by the position manager
        _approve(address(this), nftPositionManager, LIQUIDITY_TOKENS);
        IWETN(WETN).approve(nftPositionManager, wetnAmount);

        // Mint a full-range liquidity position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,              // 0.3% fee tier
            tickLower: -887220,     // Minimum tick for full range
            tickUpper: 887220,      // Maximum tick for full range
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,          // No slippage protection for simplicity
            amount1Min: 0,
            recipient: address(this), // Liquidity position owned by this contract
            deadline: block.timestamp + 1 hours
        });
        (uint tokenId,,uint256 amount0, uint256 amount1) = INonfungiblePositionManager(nftPositionManager).mint(params);

        emit LiquidityAdded(tokenId, amount0, amount1);

        // Transfer dust to dev team
        if(amount0Desired - amount0 > 0){
            IERC20(token0).transfer(devTeam, amount0Desired - amount0);
        }
        if(amount1Desired - amount1 > 0){
            IERC20(token1).transfer(devTeam, amount1Desired - amount1);
        }

        // Approve locker to transfer position NFT
        INonfungiblePositionManager(nftPositionManager).approve(v3Locker, tokenId);

        // Create lock and transfer ownership to dev team
        uint256 duration = 270 days;
        bool lockSuccess = ILockerV3(v3Locker).lockPosition{value: lockerFlatFee}(tokenId, duration, true);
        require(lockSuccess, "Locking failed");

        bool lockTransferSuccess = ILockerV3(v3Locker).transferLockOwner(tokenId, devTeam);
        require(lockTransferSuccess, "Lock transfer failed");

        emit LiquidityLocked(tokenId, duration);
    }

    // Allows dev team to top up staking rewards and recalculate reward per block
    function stakingRewardsTopUp(uint256 addedAmount, uint256 newStakingPeriodInDays) external nonReentrant onlyTeam {
        require(stakingEnabled, "Staking not enabled");
        require(addedAmount > 0, "Amount must be positive");

        _updateReward(address(0));  // Update global rewards

        // Transfer tokens into the contract
        IERC20(address(this)).transferFrom(msg.sender, address(this), addedAmount);
        stakingRewardPoolTokens += addedAmount;

        // Ensure pool covers all owed rewards
        require(stakingRewardPoolTokens >= stakingTotalOwedRewards , "Insufficient pool to cover owed rewards");

        // Calculate available tokens for new rewards
        uint256 availableForNewPeriod = stakingRewardPoolTokens - stakingTotalOwedRewards ;

        // Set new staking period and reward rate
        uint256 blocksInPeriod = newStakingPeriodInDays * 24 * 60 * 60 / 5; // Assuming 5-second blocks
        require(blocksInPeriod > 0, "Invalid staking period");

        stakingPeriodStartBlock = block.number;
        stakingPeriodEndBlock = block.number + blocksInPeriod;
        stakingRewardRate = availableForNewPeriod / blocksInPeriod;

        emit StakingRewardsPoolToppedUp(addedAmount, stakingRewardPoolTokens, stakingRewardRate);
    }

    // Allows the dev team to withdraw vested governance tokens
    function governanceWithdrawVestedTokens() external nonReentrant onlyTeam {
        uint256 vestingStart = launchTimestamp + VESTING_START_OFFSET;
        require(block.timestamp >= vestingStart, "Vesting not started");

        uint256 timeElapsed = block.timestamp - vestingStart;
        uint256 periodsPassed = timeElapsed / VESTING_PERIOD;
        if (periodsPassed > VESTING_PERIODS) periodsPassed = VESTING_PERIODS;

        uint256 totalVested = periodsPassed * TOKENS_PER_PERIOD;
        uint256 claimable = totalVested - governanceTokensWithdrawn;
        require(claimable > 0, "No tokens available to withdraw");

        governanceTokensWithdrawn += claimable;
        _transfer(address(this), devTeam, claimable);

        emit GovernanceTokensWithdrawn(devTeam, claimable);
    }

    function transferOwnership(address _newOwner) external onlyTeam {
        emit OwnershipTransferred(devTeam, _newOwner);
        devTeam = _newOwner;
    }

    function stakingEnable(bool _enabled) external onlyTeam {

        require(stakingEnabled != _enabled, "Already set");

        if(stakingEnabled){
            // Update latest earnings before disabling
            _updateReward(address(0));
        } 
        // Previously enabled, but not currently enabled - reset staking period using blocks remaining in previous period
        else if (stakedTotal > 0){
            uint blocksRemainingInPeriod = stakingPeriodEndBlock - stakingLastUpdateBlock;
            stakingPeriodStartBlock = block.number;
            stakingLastUpdateBlock = block.number;
            stakingPeriodEndBlock = block.number + blocksRemainingInPeriod;
        }

        stakingEnabled = _enabled;
        emit StakingEnabled(_enabled);
    }

    function recoverErc20(address ca, address to) external onlyTeam {
        require(ca != address(this), "Cannot recover MEGA");
        uint256 balance = IERC20(ca).balanceOf(address(this));
        bool success = IERC20(ca).transfer(to, balance);
        require(success, "Transfer failed");

        emit ERC20Recovered(ca, balance, to);
    }
}


interface IWETN {
    function deposit() external payable;
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface INonfungiblePositionManager {

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function approve(address to, uint256 tokenId) external;

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) external payable returns (address pool);

}

interface ILockerV3 {
    function fees() external view returns (uint256 etnFlatFee, uint256 boltFlatFee, uint256 lpPercentFee);
    function lockPosition(uint256 tokenId, uint256 lockDuration, bool _flatFeeInETN) external payable returns (bool success);
    function transferLockOwner(uint256 tokenId, address newOwner) external returns (bool success);
}


