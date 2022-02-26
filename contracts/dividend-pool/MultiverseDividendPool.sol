// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../nft/MultiverseNFT.sol";

contract MultiverseDividendPoolUpgradeable is OwnableUpgradeable, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    struct AddressInfo {
        uint256 stakePower;
        EnumerableSet.UintSet nfts;
        uint256 harvestCycle;
        uint256 historyAward;
        uint256 ssrCount;
        uint256 srCount;
        uint256 harvestedAward;
    }

    struct PoolInfo {
        uint256 ssrCount;
        uint256 srCount;
        uint256 startBlock;
        uint256 endBlock;
        uint256 totalAward;
        uint256 totalPower;
        uint256 avgPowerAward;
    }

    struct UserInfoView {
        uint256 ssrCount;
        uint256 srCount;
        uint256 stakePower;
        uint256[] nfts;
        uint256[] bunnyIds;
        uint256 historyAward;
        uint256 predictAward;
        uint256 harvestedAward;
    }

    MultiverseNFT mvsNFT;

    uint256 public cycle;

    mapping(uint256 => PoolInfo) public getPoolInfo;

    mapping(address => AddressInfo) private addressToInfo;

    mapping(uint256 => uint256) public bunnyIdToPower;

    function initialize() public initializer {
        // owner
        __Ownable_init();
        mvsNFT = MultiverseNFT(0xF51Fb8De65F85Cb18A2558C1D3769835f526F36c);
        bunnyIdToPower[2] = 1;
        bunnyIdToPower[5] = 1;
        bunnyIdToPower[3] = 20;
        bunnyIdToPower[6] = 20;
    }

    receive() external payable {
        PoolInfo storage pool = getPoolInfo[cycle];
        require(block.number > pool.startBlock && block.number < pool.endBlock, "pool is not open");
        require(cycle > 0, "pool is not start");
        getPoolInfo[cycle].totalAward += msg.value;
    }

    function stake(uint256 _tokenId) public {
        PoolInfo storage pool = getPoolInfo[cycle];
        require(block.number > pool.startBlock && block.number < pool.endBlock, "pool is not open");
        mvsNFT.safeTransferFrom(msg.sender, address(this), _tokenId);
        uint256 bunnyId = mvsNFT.getBunnyId(_tokenId);
        uint256 power = bunnyIdToPower[bunnyId];
        require(power > 0, "bonnyId error");
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        if (power == 1) {
            pool.srCount += 1;
            addressInfo.srCount += 1;
        } else if (power == 20) {
            pool.ssrCount += 1;
            addressInfo.ssrCount += 1;
        } else {
            revert("power error");
        }
        if (addressInfo.nfts.length() == 0) {
            addressInfo.harvestCycle = cycle - 1;
        }
        addressInfo.stakePower += power;
        pool.totalPower += power;
        addressInfo.nfts.add(_tokenId);
        _updateAward();
    }

    function unStake(uint256 _tokenId) public {
        _updateAward();
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        PoolInfo storage pool = getPoolInfo[cycle];
        uint256 bunnyId = mvsNFT.getBunnyId(_tokenId);
        uint256 power = bunnyIdToPower[bunnyId];
        require(addressInfo.nfts.contains(_tokenId), "not token owner");
        mvsNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        if (power == 1) {
            pool.srCount -= 1;
            addressInfo.srCount -= 1;
        } else if (power == 20) {
            pool.ssrCount -= 1;
            addressInfo.ssrCount -= 1;
        } else {
            revert("power error");
        }
        addressInfo.stakePower -= power;
        pool.totalPower -= power;
        addressInfo.nfts.remove(_tokenId);
    }

    function emergencyWithdrawForNft(uint256 _tokenId) public {
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        PoolInfo storage pool = getPoolInfo[cycle];
        uint256 bunnyId = mvsNFT.getBunnyId(_tokenId);
        uint256 power = bunnyIdToPower[bunnyId];
        require(addressInfo.nfts.contains(_tokenId), "not token owner");
        mvsNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        if (addressInfo.stakePower > 0) {
            addressInfo.stakePower -= power;
        }
        if (pool.totalPower > 0) {
            pool.totalPower -= power;
        }
        if (power == 1 && pool.srCount > 0 && addressInfo.srCount > 0) {
            pool.srCount -= 1;
            addressInfo.srCount -= 1;
        } else if (power == 20 && pool.ssrCount > 0 && addressInfo.ssrCount > 0) {
            pool.ssrCount -= 1;
            addressInfo.ssrCount -= 1;
        }
        addressInfo.nfts.remove(_tokenId);
        addressInfo.harvestCycle = cycle;
        addressInfo.historyAward = 0;
    }

    function stakeList(uint256[] memory _tokenIds) public {
        PoolInfo storage pool = getPoolInfo[cycle];
        require(block.number > pool.startBlock && block.number < pool.endBlock, "pool is not open");
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        if (addressInfo.nfts.length() == 0) {
            addressInfo.harvestCycle = cycle - 1;
        }
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            mvsNFT.safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
            uint256 bunnyId = mvsNFT.getBunnyId(_tokenIds[i]);
            uint256 power = bunnyIdToPower[bunnyId];
            require(power > 0, "bonnyId error");
            if (power == 1) {
                pool.srCount += 1;
                addressInfo.srCount += 1;
            } else if (power == 20) {
                pool.ssrCount += 1;
                addressInfo.ssrCount += 1;
            } else {
                revert("power error");
            }
            addressInfo.stakePower += power;
            pool.totalPower += power;
            addressInfo.nfts.add(_tokenIds[i]);
        }
        _updateAward();
    }

    function unStakeList(uint256[] memory _tokenIds) public {
        _updateAward();
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        PoolInfo storage pool = getPoolInfo[cycle];
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 bunnyId = mvsNFT.getBunnyId(_tokenIds[i]);
            uint256 power = bunnyIdToPower[bunnyId];
            require(addressInfo.nfts.contains(_tokenIds[i]), "not token owner");
            mvsNFT.safeTransferFrom(address(this), msg.sender, _tokenIds[i]);
            if (power == 1) {
                pool.srCount -= 1;
                addressInfo.srCount -= 1;
            } else if (power == 20) {
                pool.ssrCount -= 1;
                addressInfo.ssrCount -= 1;
            } else {
                revert("power error");
            }
            addressInfo.stakePower -= power;
            pool.totalPower -= power;
            addressInfo.nfts.remove(_tokenIds[i]);
        }
    }

    function harvest() public {
        _updateAward();
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        uint256 amount = addressInfo.historyAward;
        addressInfo.historyAward = 0;
        addressInfo.harvestedAward += amount;
        payable(msg.sender).transfer(amount);
    }

    function _updateAward() internal {
        AddressInfo storage addressInfo = addressToInfo[msg.sender];
        if (addressInfo.nfts.length() == 0) {
            return;
        }
        for (uint256 i = addressInfo.harvestCycle + 1; i <= cycle; i++) {
            PoolInfo storage pool = getPoolInfo[i];

            if (i == cycle) {
                if (block.number > pool.endBlock) {
                    if (pool.avgPowerAward == 0) {
                        pool.avgPowerAward = pool.totalAward / pool.totalPower;
                    }
                    addressInfo.harvestCycle = i;
                    addressInfo.historyAward += pool.avgPowerAward * addressInfo.stakePower;
                }
            } else {
                addressInfo.harvestCycle = i;
                addressInfo.historyAward += pool.avgPowerAward * addressInfo.stakePower;
            }
        }
    }

    function addCycle(uint256 _startBlock, uint256 _endBlock) public onlyOwner {
        require(_startBlock < _endBlock, "The start block must be smaller than the end block");
        require(block.number < _endBlock, "The block number must be smaller than the end block");
        PoolInfo storage pool = getPoolInfo[cycle];
        require(_startBlock > pool.endBlock, "The start block must be greater than the cycle end block");
        cycle++;
        getPoolInfo[cycle] = PoolInfo(pool.ssrCount, pool.srCount, _startBlock, _endBlock, 0, pool.totalPower, 0);
    }

    function updateNowCycle(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _totalAward
    ) public onlyOwner {
        require(_startBlock < _endBlock, "The start block must be smaller than the end block");
        require(block.number < _endBlock, "The block number must be smaller than the end block");
        if (cycle == 1) {
            PoolInfo storage pool = getPoolInfo[cycle - 1];
            require(_startBlock > pool.endBlock, "The start block must be greater than the cycle end block");
        }
        getPoolInfo[cycle].startBlock = _startBlock;
        getPoolInfo[cycle].endBlock = _endBlock;
        getPoolInfo[cycle].totalAward = _totalAward;
    }

    function addBunnyIdToPower(uint256 _bunnyId, uint256 _power) public onlyOwner {
        bunnyIdToPower[_bunnyId] = _power;
    }

    function removeBunnyIdToPower(uint256 _bunnyId) public onlyOwner {
        delete bunnyIdToPower[_bunnyId];
    }

    function getHistoryAward(address _address) public view returns (uint256) {
        AddressInfo storage addressInfo = addressToInfo[_address];
        uint256 historyAward = addressInfo.historyAward;
        for (uint256 i = addressInfo.harvestCycle + 1; i <= cycle; i++) {
            PoolInfo memory pool = getPoolInfo[i];

            if (i == cycle) {
                if (block.number > pool.endBlock) {
                    if (pool.avgPowerAward == 0) {
                        historyAward += avgPowerAward(pool.totalAward, pool.totalPower) * addressInfo.stakePower;
                    } else {
                        historyAward = pool.avgPowerAward * addressInfo.stakePower;
                    }
                }
            } else {
                historyAward += pool.avgPowerAward * addressInfo.stakePower;
            }
        }
        return historyAward;
    }

    function getNowPredictAward(address _address) public view returns (uint256) {
        PoolInfo memory pool = getPoolInfo[cycle];
        AddressInfo storage addressInfo = addressToInfo[_address];
        if (addressInfo.historyAward == 0 && addressInfo.harvestCycle == cycle) {
            return 0;
        }
        if (pool.endBlock < block.number) {
            if (pool.avgPowerAward == 0) {
                return avgPowerAward(pool.totalAward, pool.totalPower) * addressInfo.stakePower;
            } else {
                return pool.avgPowerAward * addressInfo.stakePower;
            }
        } else {
            return avgPowerAward(pool.totalAward, pool.totalPower) * addressInfo.stakePower;
        }
    }

    function avgPowerAward(uint256 _totalAward, uint256 _totalPower) internal pure returns (uint256) {
        if (_totalPower == 0) {
            return 0;
        }
        return _totalAward / _totalPower;
    }

    function fullAddressInfo(address _address) external view returns (UserInfoView memory) {
        AddressInfo storage addressInfo = addressToInfo[_address];
        uint256 predictAward = getNowPredictAward(_address);
        uint256 historyAward = getHistoryAward(_address);
        (uint256[] memory tokenIds, uint256[] memory bunnyIds) = getNfts(_address);
        return
            UserInfoView(
                addressInfo.ssrCount,
                addressInfo.srCount,
                addressInfo.stakePower,
                tokenIds,
                bunnyIds,
                historyAward,
                predictAward,
                addressInfo.harvestedAward
            );
    }

    function getNfts(address _address) public view returns (uint256[] memory, uint256[] memory) {
        AddressInfo storage addressInfo = addressToInfo[_address];
        uint256 len = addressInfo.nfts.length();
        uint256[] memory ret = new uint256[](len);
        uint256[] memory bunnyIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            ret[i] = addressInfo.nfts.at(i);
            bunnyIds[i] = mvsNFT.getBunnyId(ret[i]);
        }
        return (ret, bunnyIds);
    }

    function onERC721Received(
        address operator,
        address, // from
        uint256, // tokenId
        bytes calldata // data
    ) external view override returns (bytes4) {
        require(operator == address(this), "received Nft from unauthenticated contract");

        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}
