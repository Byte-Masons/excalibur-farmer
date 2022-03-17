// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IMasterChef {
    function deposit(uint256 pid, uint256 amount) external;

    function depositOnLockSlot(
        uint256 pid,
        uint256 amount,
        uint256 lockDurationSeconds,
        bool fromRegularDeposit
    ) external;

    function emergencyWithdraw(uint256 pid) external;

    function emergencyWithdrawOnLockSlot(uint256 pid, uint256 slotId) external;

    function excToken() external view returns (address);

    function getPoolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 depositFeeBP,
            bool isGrailRewards,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier
        );

    function getUserInfo(uint256 pid, address userAddress) external view returns (uint256 amount, uint256 rewardDebt);

    function getUserLockSlotInfo(
        uint256 pid,
        address userAddress,
        uint256 slotId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 lockDurationSeconds,
            uint256 depositTime,
            uint256 multiplier,
            uint256 amountWithMultiplier,
            uint256 bonusRewards
        );

    function getUserSlotLength(uint256 pid, address account) external view returns (uint256);

    function grailToken() external view returns (address);

    function harvest(uint256 pid) external;

    function harvestOnLockSlot(uint256 pid, uint256 slotId) external;

    function isPoolClosed(uint256 pid) external view returns (bool);

    function pendingRewards(uint256 pid, address userAddress) external view returns (uint256 pending);

    function pendingRewardsOnLockSlot(
        uint256 pid,
        address userAddress,
        uint256 slotId
    )
        external
        view
        returns (
            uint256 pending,
            uint256 bonusRewards,
            bool canHarvestBonusRewards
        );

    function redepositOnLockSlot(
        uint256 pid,
        uint256 slotId,
        uint256 amountToAdd,
        bool fromRegularDeposit
    ) external;

    function renewLockSlot(
        uint256 pid,
        uint256 slotId,
        uint256 lockDurationSeconds
    ) external;

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);

    function userLockSlotInfo(
        uint256,
        address,
        uint256
    )
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 lockDurationSeconds,
            uint256 depositTime,
            uint256 multiplier,
            uint256 amountWithMultiplier,
            uint256 bonusRewards
        );

    function withdraw(uint256 pid, uint256 amount) external;

    function withdrawOnLockSlot(uint256 pid, uint256 slotId) external;
}
