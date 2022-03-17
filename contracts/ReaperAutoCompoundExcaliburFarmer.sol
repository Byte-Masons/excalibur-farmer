// SPDX-License-Identifier: MIT

import './abstract/ReaperBaseStrategy.sol';
import './interfaces/IExcaliburRouter.sol';
import './interfaces/IMasterChef.sol';
import './interfaces/IExcaliburV2Pair.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

pragma solidity 0.8.11;

/**
 * @dev This strategy will farm LPs on Excalibur and autocompound rewards
 */
contract ReaperAutoCompoundExcaliburFarmer is ReaperBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps. Also used to charge fees on yield.
     * {EXC} - Farm reward token
     * {want} - The vault token the strategy is maximizing
     * {lpToken0} - Token 0 of the LP want token
     * {lpToken1} - Token 1 of the LP want token
     */
    address public constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public constant EXC = 0x6e99e0676A90b2a5a722C44109db22220382cc9F;
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Third Party Contracts:
     * {MASTER_CHEF} - For depositing LP tokens and claiming farm rewards
     * {EXCALIBUR_ROUTER} - Router for swapping tokens
     */
    address public constant MASTER_CHEF = 0x70B9611f3cd33e686ee7535927cE420C2A111005;
    address public constant EXCALIBUR_ROUTER = 0xc8Fe105cEB91e485fb0AC338F2994Ea655C78691;

    /**
     * @dev Strategy variables:
     * {poolId} - For interacting with the MasterChef
     */
    uint256 public poolId;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _want,
        uint256 _poolId
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        want = _want;
        poolId = _poolId;
        lpToken0 = IExcaliburV2Pair(want).token0();
        lpToken1 = IExcaliburV2Pair(want).token1();
        _giveAllowances();
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {want} from the Excalibur MasterChef
     * The available {want} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, '!vault');
        require(_amount != 0, '0 amount');
        require(_amount <= balanceOf(), 'invalid amount');

        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMasterChef(MASTER_CHEF).withdraw(poolId, _amount - wantBal);
        }

        uint256 withdrawFee = (_amount * securityFee) / PERCENT_DIVISOR;
        IERC20Upgradeable(want).safeTransfer(vault, _amount - withdrawFee);
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IMasterChef(MASTER_CHEF).pendingRewards(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(EXC).balanceOf(address(this));

        if (totalRewards != 0) {
            address[] memory rewardToWftmPath = new address[](2);
            rewardToWftmPath[0] = EXC;
            rewardToWftmPath[1] = WFTM;
            uint256[] memory amountOutMins = IExcaliburRouter(EXCALIBUR_ROUTER).getAmountsOut(
                totalRewards,
                rewardToWftmPath
            );
            profit += amountOutMins[1];
        }

        profit += IERC20Upgradeable(WFTM).balanceOf(address(this));

        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function retireStrat() external {
        _onlyStrategistOrOwner();

        _claimRewards();
        _swapRewardsToWftm();
        _addLiquidity();

        uint256 poolBalance = balanceOfPool();
        if (poolBalance != 0) {
            IMasterChef(MASTER_CHEF).withdraw(poolId, poolBalance);
        }
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * @dev Pauses supplied. Withdraws all funds from the LP Depositor, leaving rewards behind.
     */
    function panic() external {
        _onlyStrategistOrOwner();
        IMasterChef(MASTER_CHEF).emergencyWithdraw(poolId);
        pause();
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external {
        _onlyStrategistOrOwner();
        _unpause();
        _giveAllowances();
        deposit();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public {
        _onlyStrategistOrOwner();
        _pause();
        _removeAllowances();
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone supplied in the strategy's vault contract.
     * It supplies {want} to farm {EXC}
     */
    function deposit() public whenNotPaused {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IMasterChef(MASTER_CHEF).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to Excalibur.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     * @dev Calculates the total amount of {want} held in the Excalibur MasterChef
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IMasterChef(MASTER_CHEF).getUserInfo(poolId, address(this));
        return _amount;
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. Claims {EXC} from the MasterChef.
     * 2. Swaps rewards to {WFTM}.
     * 3. Claims fees for the harvest caller and treasury.
     * 4. Swaps the {WFTM} token for {want}
     * 5. Deposits.
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapRewardsToWftm();
        _chargeFees();
        _addLiquidity();
        deposit();
    }

    /**
     * @dev Core harvest function.
     * Get rewards from the MasterChef
     */
    function _claimRewards() internal {
        IMasterChef(MASTER_CHEF).harvest(poolId);
    }

    /**
     * @dev Core harvest function.
     * Swaps {EXC} to {WFTM}
     */
    function _swapRewardsToWftm() internal {
        uint256 rewardBalance = IERC20Upgradeable(EXC).balanceOf(address(this));
        if (rewardBalance == 0) {
            return;
        }
        _swapTokens(EXC, WFTM, rewardBalance);
    }

    function _swapTokens(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == _to || _amount == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        IExcaliburRouter(EXCALIBUR_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            address(this), // Send part of the swap fees back to the strategy
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     * Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        uint256 wftmFee = (IERC20Upgradeable(WFTM).balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            IERC20Upgradeable(WFTM).safeTransfer(msg.sender, callFeeToUser);
            IERC20Upgradeable(WFTM).safeTransfer(treasury, treasuryFeeToVault);
            IERC20Upgradeable(WFTM).safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /** @dev Converts WFTM to both sides of the LP token and builds the liquidity pair */
    function _addLiquidity() internal {
        uint256 wrappedHalf = IERC20Upgradeable(WFTM).balanceOf(address(this)) / 2;

        if (wrappedHalf == 0) {
            return;
        }

        _swapTokens(WFTM, lpToken0, wrappedHalf);
        _swapTokens(WFTM, lpToken1, wrappedHalf);

        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        IExcaliburRouter(EXCALIBUR_ROUTER).addLiquidity(
            lpToken0,
            lpToken1,
            lp0Bal,
            lp1Bal,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Gives the necessary allowances
     */
    function _giveAllowances() internal {
        // want -> MASTER_CHEF
        uint256 wantAllowance = type(uint256).max - IERC20Upgradeable(want).allowance(address(this), MASTER_CHEF);
        IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantAllowance);
        // // rewardTokens -> EXCALIBUR_ROUTER
        uint256 excAllowance = type(uint256).max -
            IERC20Upgradeable(EXC).allowance(address(this), EXCALIBUR_ROUTER);
        IERC20Upgradeable(EXC).safeIncreaseAllowance(EXCALIBUR_ROUTER, excAllowance);
        // // WFTM -> EXCALIBUR_ROUTER
        uint256 wftmAllowance = type(uint256).max - IERC20Upgradeable(WFTM).allowance(address(this), EXCALIBUR_ROUTER);
        IERC20Upgradeable(WFTM).safeIncreaseAllowance(EXCALIBUR_ROUTER, wftmAllowance);
        // // LP tokens -> EXCALIBUR_ROUTER
        uint256 lp0Allowance = type(uint256).max - IERC20Upgradeable(lpToken0).allowance(address(this), EXCALIBUR_ROUTER);
        IERC20Upgradeable(lpToken0).safeIncreaseAllowance(EXCALIBUR_ROUTER, lp0Allowance);
        uint256 lp1Allowance = type(uint256).max - IERC20Upgradeable(lpToken1).allowance(address(this), EXCALIBUR_ROUTER);
        IERC20Upgradeable(lpToken1).safeIncreaseAllowance(EXCALIBUR_ROUTER, lp1Allowance);
    }

    /**
     * @dev Removes all allowance that were given
     */
    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeDecreaseAllowance(
            MASTER_CHEF,
            IERC20Upgradeable(want).allowance(address(this), MASTER_CHEF)
        );
        IERC20Upgradeable(EXC).safeDecreaseAllowance(
            EXCALIBUR_ROUTER,
            IERC20Upgradeable(EXC).allowance(address(this), EXCALIBUR_ROUTER)
        );
        IERC20Upgradeable(WFTM).safeDecreaseAllowance(
            EXCALIBUR_ROUTER,
            IERC20Upgradeable(WFTM).allowance(address(this), EXCALIBUR_ROUTER)
        );
        IERC20Upgradeable(lpToken0).safeDecreaseAllowance(
            EXCALIBUR_ROUTER,
            IERC20Upgradeable(lpToken0).allowance(address(this), EXCALIBUR_ROUTER)
        );
        IERC20Upgradeable(lpToken1).safeDecreaseAllowance(
            EXCALIBUR_ROUTER,
            IERC20Upgradeable(lpToken1).allowance(address(this), EXCALIBUR_ROUTER)
        );
    }
}
