// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract MultiversePool is Ownable, IERC721Receiver, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  struct UserInfo {
    uint256 userRewardDebt;
    uint256 userAccReward;
    EnumerableSet.UintSet userNfts;
    uint256 userHarvestedReward;
  }

  struct UserInfoView {
    uint256 allShare;
    uint256[] nfts;
    uint256 accReward;
    uint256 unharvestReward;
    uint256 userDebt;
  }

  struct PoolView {
    address tokenAddress;
    address nftAddress;
    uint256 bscBlockTime;
    uint256 blocksPerYear;
    uint256 halvingPeriod;
    uint256 rewardPerBlock;
    uint256 totalNftsInPool;
    uint256 totalShareInPool;
    uint256 totalRewardsInPool;
    uint256 lockRewardsInPool;
    uint256 totalMiningInPool;
    uint256 resetRewardsInPool;
    uint256 startBlock;
    uint256 endBlock;
    uint256 lastUpdatedBlock;
    uint256 lastRewardBlock;
    uint256 accRewardPerShare;
  }

  address public INITIAL_ADDRESS;
  address public REWARD_TOKEN_ADDRESS;
  address public MVS_NFT_ADDRESS;
  uint256 public MVS_NFT_HASH_RATE = 1;
  uint256 public BSC_BLOCK_TIME = 3;
  uint256 public BLOCKS_PER_YEAR = 10512000;
  uint256 public MVS_HALVING_PREIOD = BLOCKS_PER_YEAR * 4;

  bool public isInitialized;
  bool public isFinished;

  uint256 public startBlock;
  uint256 public bonusEndBlock;
  uint256 public lastRewardBlock;
  uint256 public rewardPerBlock;
  uint256 public resetRewardsInPool;
  uint256 public totalRewardsInPool;
  uint256 public lockRewardsInPool;
  uint256 public totalShareInPool;
  uint256 public totalMiningInPool;

  uint256 public lastUpdatedBlock;
  uint256 public accRewardPerShare;

  mapping(address => UserInfo) private userInfo;

  event Stake(address indexed user, uint256 amount);
  event UnStake(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 amount);

  constructor() public {
    INITIAL_ADDRESS = msg.sender;
  }

  function initialize(
    address _mvsNFTAddress,
    address _rewardTokenAddress,
    uint256 _rewardPerBlock,
    uint256 _startBlock,
    uint256 _bonusEndBlock,
    uint256 _totalRewardsInPool,
    uint256 _lockRewardsInPool,
    uint256 _originalNFTTokenId
  ) external {
    require(!isInitialized, "Already initialized");
    require(msg.sender == INITIAL_ADDRESS, "Not owner");

    MVS_NFT_ADDRESS = _mvsNFTAddress;
    REWARD_TOKEN_ADDRESS = _rewardTokenAddress;

    rewardPerBlock = _rewardPerBlock;
    startBlock = _startBlock;
    bonusEndBlock = _bonusEndBlock;

    lastRewardBlock = startBlock;

    IERC20(REWARD_TOKEN_ADDRESS).safeTransferFrom(
      msg.sender,
      address(this),
      _totalRewardsInPool
    );

    IERC20(REWARD_TOKEN_ADDRESS).safeTransferFrom(
      msg.sender,
      address(this),
      _lockRewardsInPool
    );

    resetRewardsInPool = _totalRewardsInPool;
    totalRewardsInPool = _totalRewardsInPool;
    lockRewardsInPool = _lockRewardsInPool;

    isInitialized = true;
    isFinished = false;
    stake(_originalNFTTokenId);
  }

  function harvest() external nonReentrant {
    require(isInitialized == true, "The mining pool is not initialized");

    UserInfo storage user = userInfo[msg.sender];

    _updatePool();

    uint256 pending =
      user.userNfts.length().mul(accRewardPerShare).div(1e12).sub(
        user.userRewardDebt
      ); // 1e12
    totalMiningInPool = user.userAccReward.add(pending);
    if (totalMiningInPool > 0) {
      IERC20(REWARD_TOKEN_ADDRESS).safeTransfer(
        address(msg.sender),
        totalMiningInPool
      );
      user.userAccReward = 0;
      user.userHarvestedReward = user.userHarvestedReward.add(
        totalMiningInPool
      );
      user.userRewardDebt = user.userNfts.length().mul(accRewardPerShare).div(
        1e12
      );
    }

    emit Harvest(msg.sender, totalMiningInPool);
  }

  function stake(uint256 _tokenId) public {
    require(isInitialized == true, "The mining pool is not initialized");
    require(isFinished == false, "The mining pool has stopped");
    require(resetRewardsInPool > 0, "The mining pool reward is 0");
    require(block.number < bonusEndBlock, "The mining pool ended");

    UserInfo storage user = userInfo[msg.sender];

    _updatePool();

    if (user.userNfts.length() > 0) {
      uint256 pending =
        user.userNfts.length().mul(accRewardPerShare).div(1e12).sub(
          user.userRewardDebt
        ); // 1e12
      if (pending > 0) {
        user.userAccReward = user.userAccReward.add(pending);
      }
    }

    IERC721(MVS_NFT_ADDRESS).safeTransferFrom(
      address(msg.sender),
      address(this),
      _tokenId
    );

    user.userNfts.add(_tokenId);
    totalShareInPool = totalShareInPool.add(MVS_NFT_HASH_RATE);
    user.userRewardDebt = user.userNfts.length().mul(accRewardPerShare).div(
      1e12
    );

    emit Stake(msg.sender, _tokenId);
  }

  function batchStake(uint256[] memory tokenIds) public {
    require(isInitialized == true, 'The mining pool is not initialized');
    for (uint256 i = 0; i < tokenIds.length; i++) {
      stake(tokenIds[i]);
    }
  }

  function unStake(uint256 _tokenId) public {
    UserInfo storage user = userInfo[msg.sender];
    require(user.userNfts.length() > 0, "Amount to withdraw too high");
    require(user.userNfts.contains(_tokenId), "withdraw: not token owner");

    _updatePool();

    uint256 pending =
      user.userNfts.length().mul(accRewardPerShare).div(1e12).sub(
        user.userRewardDebt
      ); // 1e12

    IERC721(MVS_NFT_ADDRESS).safeTransferFrom(
      address(this),
      address(msg.sender),
      _tokenId
    );

    user.userNfts.remove(_tokenId);

    totalShareInPool = totalShareInPool.sub(MVS_NFT_HASH_RATE);
    if (pending > 0) {
      user.userAccReward = user.userAccReward.add(pending);
    }
    user.userRewardDebt = user.userNfts.length().mul(accRewardPerShare).div(
      1e12
    );

    emit UnStake(msg.sender, _tokenId);
  }

  function batchUnStake(uint256[] memory tokenIds) public {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      unStake(tokenIds[i]);
    }
  }

  function _updatePool() internal {
    if (block.number < lastRewardBlock) {
      return;
    }
    if (totalShareInPool == 0) {
      bonusEndBlock = bonusEndBlock.add(block.number.sub(lastRewardBlock));
      lastRewardBlock = _getCorrectBlock(block.number);
      return;
    }

    uint256 blockReward = getRewardTokenBlockReward(lastRewardBlock);

    if (blockReward <= 0) {
      return;
    }
    resetRewardsInPool = resetRewardsInPool.sub(blockReward);
    accRewardPerShare = accRewardPerShare.add(
      blockReward.mul(1e12).div(totalShareInPool)
    );

    lastUpdatedBlock = _getCorrectBlock(block.number);
    lastRewardBlock = _getCorrectBlock(block.number);
  }

  function getRewardTokenBlockReward(uint256 _lastRewardBlock)
    public
    view
    returns (uint256)
  {
    uint256 blockReward = 0;
    uint256 lastRewardPhase = _phase(_lastRewardBlock);
    uint256 currentPhase = _phase(_getCorrectBlock(block.number));
    while (lastRewardPhase < currentPhase) {
      lastRewardPhase++;
      uint256 height = lastRewardPhase.mul(MVS_HALVING_PREIOD).add(startBlock);
      blockReward = blockReward.add(
        (height.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(height))
      );
      _lastRewardBlock = height;
    }
    blockReward = blockReward.add(
      (_getCorrectBlock(block.number).sub(_lastRewardBlock)).mul(
        getRewardTokenPerBlock(_getCorrectBlock(block.number))
      )
    );
    return blockReward;
  }

  function getRewardTokenPerBlock(uint256 blockNumber)
    public
    view
    returns (uint256)
  {
    uint256 _phase = _phase(blockNumber);
    return rewardPerBlock.div(2**_phase);
  }

  function _phase(uint256 blockNumber) internal view returns (uint256) {
    if (MVS_HALVING_PREIOD == 0) {
      return 0;
    }
    if (blockNumber > startBlock) {
      return (blockNumber.sub(startBlock).sub(1)).div(MVS_HALVING_PREIOD);
    }
    return 0;
  }

  function _getCorrectBlock(uint256 blockNumber)
    internal
    view
    returns (uint256)
  {
    require(blockNumber > startBlock, "blockNumber Error");
    if (blockNumber <= bonusEndBlock) {
      return blockNumber;
    }
    return bonusEndBlock;
  }

  function pendingReward(address _user) public view returns (uint256) {
    UserInfo storage user = userInfo[_user];

    if (block.number > lastRewardBlock && user.userNfts.length() != 0) {
      uint256 blockReward = getRewardTokenBlockReward(lastRewardBlock);

      uint256 adjustedTokenPerShare =
        accRewardPerShare.add(blockReward.mul(1e12).div(totalShareInPool));
      uint256 pending =
        user.userNfts.length().mul(adjustedTokenPerShare).div(1e12).sub(
          user.userRewardDebt
        );
      return pending.add(user.userAccReward);
    }

    uint256 pending =
      user.userNfts.length().mul(accRewardPerShare).div(1e12).sub(
        user.userRewardDebt
      );
    return pending.add(user.userAccReward);
  }

  function getPoolInfo() public view returns (PoolView memory) {
    return
      PoolView({
        tokenAddress: address(REWARD_TOKEN_ADDRESS),
        nftAddress: address(MVS_NFT_ADDRESS),
        bscBlockTime: BSC_BLOCK_TIME,
        blocksPerYear: BLOCKS_PER_YEAR,
        halvingPeriod: MVS_HALVING_PREIOD,
        rewardPerBlock: rewardPerBlock,
        totalNftsInPool: totalShareInPool,
        totalShareInPool: totalShareInPool,
        totalRewardsInPool: totalRewardsInPool,
        lockRewardsInPool: lockRewardsInPool,
        totalMiningInPool: totalMiningInPool,
        resetRewardsInPool: resetRewardsInPool,
        startBlock: startBlock,
        endBlock: bonusEndBlock,
        lastUpdatedBlock: lastUpdatedBlock,
        lastRewardBlock: lastRewardBlock,
        accRewardPerShare: accRewardPerShare
      });
  }

  function getNfts(address _user) public view returns (uint256[] memory ids) {
    UserInfo storage user = userInfo[_user];
    uint256 len = user.userNfts.length();

    uint256[] memory ret = new uint256[](len);
    for (uint256 i = 0; i < len; i++) {
      ret[i] = user.userNfts.at(i);
    }
    return ret;
  }

  function getFullUserInfo(address _user)
    public
    view
    returns (UserInfoView memory)
  {
    UserInfo storage user = userInfo[_user];
    return
      UserInfoView({
        allShare: user.userNfts.length(),
        nfts: getNfts(_user),
        accReward: user.userHarvestedReward,
        unharvestReward: pendingReward(_user),
        userDebt: user.userRewardDebt
      });
  }

  function onERC721Received(
    address operator,
    address, // from
    uint256, // tokenId
    bytes calldata // data
  ) public override nonReentrant returns (bytes4) {
    require(
      operator == address(this),
      "received Nft from unauthenticated contract"
    );

    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }
}
