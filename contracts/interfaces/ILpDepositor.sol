// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.11;

interface ILpDepositor {
    struct Amounts {
        uint256 solid;
        uint256 sex;
    }

    function SEX() external view returns (address);

    function SOLID() external view returns (address);

    function SOLIDsex() external view returns (address);

    function bribeForPool(address) external view returns (address);

    function claimLockerRewards(
        address pool,
        address[] calldata gaugeRewards,
        address[] calldata bribeRewards
    ) external;

    function deposit(address pool, uint256 amount) external;

    function depositTokenImplementation() external view returns (address);

    function feeDistributor() external view returns (address);

    function gaugeForPool(address) external view returns (address);

    function getReward(address[] calldata pools) external;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenID,
        bytes calldata
    ) external returns (bytes4);

    function owner() external view returns (address);

    function pendingRewards(address account, address[] calldata pools) external view returns (Amounts[] memory pending);

    function renounceOwnership() external;

    function rewardIntegral(address) external view returns (uint256 solid, uint256 sex);

    function rewardIntegralFor(address, address) external view returns (uint256 solid, uint256 sex);

    function setAddresses(
        address _sex,
        address _solidsex,
        address _solidexVoter,
        address _feeDistributor,
        address _stakingRewards,
        address _tokenWhitelister,
        address _depositToken
    ) external;

    function solidlyVoter() external view returns (address);

    function stakingRewards() external view returns (address);

    function tokenForPool(address) external view returns (address);

    function tokenID() external view returns (uint256);

    function tokenWhitelister() external view returns (address);

    function totalBalances(address) external view returns (uint256);

    function transferDeposit(
        address pool,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transferOwnership(address newOwner) external;

    function userBalances(address, address) external view returns (uint256);

    function votingEscrow() external view returns (address);

    function whitelist(address token) external returns (bool);

    function whitelistProtocolTokens() external;

    function withdraw(address pool, uint256 amount) external;
}
