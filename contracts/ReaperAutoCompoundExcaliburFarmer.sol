// SPDX-License-Identifier: MIT

import './abstract/ReaperBaseStrategy.sol';
import './interfaces/ILpDepositor.sol';
import './interfaces/IBaseV1Router01.sol';
import './interfaces/IBaseV1Pair.sol';
import './interfaces/IUniswapV2Router02.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

pragma solidity 0.8.11;

/**
 * @dev This strategy will farm LPs on Solidex and autocompound rewards
 */
contract ReaperAutoCompoundExcaliburFarmer is ReaperBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps. Also used to charge fees on yield.
     * {SOLIDLY} - One of the reward tokens
     * {SOLIDEX} - One of the reward tokens
     * {want} - The vault token the strategy is maximizing
     * {lpToken0} - Token 0 of the LP want token
     * {lpToken1} - Token 1 of the LP want token
     */
    address public constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public constant SOLIDLY = 0x888EF71766ca594DED1F0FA3AE64eD2941740A20;
    address public constant SOLIDEX = 0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7;
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Third Party Contracts:
     * {LP_DEPOSITOR} - Solidex contract for depositing LPs and claiming rewards
     * {SOLIDLY_ROUTER} - Solidly router for swapping tokens
     */
    address public constant LP_DEPOSITOR = 0x26E1A0d851CF28E697870e1b7F053B605C8b060F;
    address public constant SOLIDLY_ROUTER = 0xa38cd27185a464914D3046f0AB9d43356B34829D;
    address public constant SPOOKY_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    address public constant SPIRIT_ROUTER = 0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _want
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        want = _want;
        (lpToken0, lpToken1) = IBaseV1Pair(want).tokens();
        _giveAllowances();
    }

    /**
     * @dev Withdraws funds and sents them back to the vault.
     * It withdraws {want} from the Solidly LP Depositor
     * The available {want} minus fees is returned to the vault.
     */
    function withdraw(uint256 _withdrawAmount) external {
        require(msg.sender == vault, '!vault');

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBalance < _withdrawAmount) {
            ILpDepositor(LP_DEPOSITOR).withdraw(want, _withdrawAmount - wantBalance);
            wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        }

        if (wantBalance > _withdrawAmount) {
            wantBalance = _withdrawAmount;
        }

        uint256 withdrawFee = (_withdrawAmount * securityFee) / PERCENT_DIVISOR;
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance - withdrawFee);
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        address[] memory pools = new address[](1);
        pools[0] = want;
        ILpDepositor.Amounts[] memory pendingRewards = ILpDepositor(LP_DEPOSITOR).pendingRewards(address(this), pools);
        ILpDepositor.Amounts memory pending = pendingRewards[0];

        IBaseV1Router01 router = IBaseV1Router01(SOLIDLY_ROUTER);
        (uint256 fromSolid, ) = router.getAmountOut(pending.solid, SOLIDLY, WFTM);
        profit += fromSolid;

        (uint256 fromSex, ) = router.getAmountOut(pending.sex, SOLIDEX, WFTM);
        profit += fromSex;

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
            ILpDepositor(LP_DEPOSITOR).withdraw(want, poolBalance);
        }
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * @dev Pauses supplied. Withdraws all funds from the LP Depositor, leaving rewards behind.
     */
    function panic() external {
        _onlyStrategistOrOwner();
        ILpDepositor(LP_DEPOSITOR).withdraw(want, balanceOfPool());
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
     * It supplies {want} to farm {SOLIDLY} and {SOLIDEX}
     */
    function deposit() public whenNotPaused {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            ILpDepositor(LP_DEPOSITOR).deposit(want, wantBalance);
        }
    }

    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to Solidex.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     * @dev Calculates the total amount of {want} held in the Solidex LP Depositor
     */
    function balanceOfPool() public view returns (uint256) {
        return ILpDepositor(LP_DEPOSITOR).userBalances(address(this), want);
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. Claims {SOLIDLY} and {SOLIDEX} from the MasterChef.
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
        address[] memory pools = new address[](1);
        pools[0] = want;
        ILpDepositor(LP_DEPOSITOR).getReward(pools);
    }

    /**
     * @dev Core harvest function.
     * Swaps {SOLIDLY} and {SOLIDEX} to {WFTM}
     */
    function _swapRewardsToWftm() internal {
        uint256 solidlyBalance = IERC20Upgradeable(SOLIDLY).balanceOf(address(this));
        _swapTokens(SOLIDLY, WFTM, solidlyBalance, SOLIDLY_ROUTER);
        uint256 solidexBalance = IERC20Upgradeable(SOLIDEX).balanceOf(address(this));
        _swapTokens(SOLIDEX, WFTM, solidexBalance, SOLIDLY_ROUTER);
    }

    function _swapTokens(
        address _from,
        address _to,
        uint256 _amount,
        address routerAddress
    ) internal {
        if (_amount != 0) {
            if (routerAddress == SOLIDLY_ROUTER) {
                IBaseV1Router01 router = IBaseV1Router01(routerAddress);
                (, bool stable) = router.getAmountOut(_amount, _from, _to);
                router.swapExactTokensForTokensSimple(_amount, 0, _from, _to, stable, address(this), block.timestamp);
            } else {
                IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
                address[] memory path = new address[](2);
                path[0] = _from;
                path[1] = _to;
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
            }
        }
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
        uint256 wrapped = IERC20Upgradeable(WFTM).balanceOf(address(this));

        if (wrapped == 0) {
            return;
        }

        _swapTokens(WFTM, lpToken0, wrapped, SPIRIT_ROUTER);
        uint256 lp0Half = IERC20Upgradeable(lpToken0).balanceOf(address(this)) / 2;

        _swapTokens(lpToken0, lpToken1, lp0Half, SOLIDLY_ROUTER);

        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        IBaseV1Router01(SOLIDLY_ROUTER).addLiquidity(
            lpToken0,
            lpToken1,
            IBaseV1Pair(want).stable(),
            lp0Bal,
            lp1Bal,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /** @dev Returns address of router that would return optimum output for _from->_to swap. */
    function _findBestRouterForSwap(
        address _from,
        address _to,
        uint256 _amount
    ) internal view returns (address) {
        (uint256 fromSolid, ) = IBaseV1Router01(SOLIDLY_ROUTER).getAmountOut(_amount, _from, _to);

        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        uint256 fromSpooky = IUniswapV2Router02(SPOOKY_ROUTER).getAmountsOut(_amount, path)[1];

        return fromSolid > fromSpooky ? SOLIDLY_ROUTER : SPOOKY_ROUTER;
    }

    /**
     * @dev Gives the necessary allowances
     */
    function _giveAllowances() internal {
        // want -> LP_DEPOSITOR
        uint256 wantAllowance = type(uint256).max - IERC20Upgradeable(want).allowance(address(this), LP_DEPOSITOR);
        IERC20Upgradeable(want).safeIncreaseAllowance(LP_DEPOSITOR, wantAllowance);
        // rewardTokens -> SOLIDLY_ROUTER
        uint256 solidlyAllowance = type(uint256).max -
            IERC20Upgradeable(SOLIDLY).allowance(address(this), SOLIDLY_ROUTER);
        IERC20Upgradeable(SOLIDLY).safeIncreaseAllowance(SOLIDLY_ROUTER, solidlyAllowance);
        uint256 solidexAllowance = type(uint256).max -
            IERC20Upgradeable(SOLIDEX).allowance(address(this), SOLIDLY_ROUTER);
        IERC20Upgradeable(SOLIDEX).safeIncreaseAllowance(SOLIDLY_ROUTER, solidexAllowance);
        // WFTM -> SPIRIT_ROUTER
        uint256 wftmAllowance = type(uint256).max - IERC20Upgradeable(WFTM).allowance(address(this), SPIRIT_ROUTER);
        IERC20Upgradeable(WFTM).safeIncreaseAllowance(SPIRIT_ROUTER, wftmAllowance);
        // LP tokens -> SOLIDLY_ROUTER, SPOOKY_ROUTER
        uint256 lp0Allowance = type(uint256).max - IERC20Upgradeable(lpToken0).allowance(address(this), SOLIDLY_ROUTER);
        IERC20Upgradeable(lpToken0).safeIncreaseAllowance(SOLIDLY_ROUTER, lp0Allowance);
        uint256 lp1Allowance = type(uint256).max - IERC20Upgradeable(lpToken1).allowance(address(this), SOLIDLY_ROUTER);
        IERC20Upgradeable(lpToken1).safeIncreaseAllowance(SOLIDLY_ROUTER, lp1Allowance);
    }

    /**
     * @dev Removes all allowance that were given
     */
    function _removeAllowances() internal {
        IERC20Upgradeable(want).safeDecreaseAllowance(
            LP_DEPOSITOR,
            IERC20Upgradeable(want).allowance(address(this), LP_DEPOSITOR)
        );
        IERC20Upgradeable(SOLIDLY).safeDecreaseAllowance(
            SOLIDLY_ROUTER,
            IERC20Upgradeable(SOLIDLY).allowance(address(this), SOLIDLY_ROUTER)
        );
        IERC20Upgradeable(SOLIDEX).safeDecreaseAllowance(
            SOLIDLY_ROUTER,
            IERC20Upgradeable(SOLIDEX).allowance(address(this), SOLIDLY_ROUTER)
        );
        IERC20Upgradeable(WFTM).safeDecreaseAllowance(
            SPIRIT_ROUTER,
            IERC20Upgradeable(WFTM).allowance(address(this), SPIRIT_ROUTER)
        );
        IERC20Upgradeable(lpToken0).safeDecreaseAllowance(
            SOLIDLY_ROUTER,
            IERC20Upgradeable(lpToken0).allowance(address(this), SOLIDLY_ROUTER)
        );
        IERC20Upgradeable(lpToken1).safeDecreaseAllowance(
            SOLIDLY_ROUTER,
            IERC20Upgradeable(lpToken1).allowance(address(this), SOLIDLY_ROUTER)
        );
    }
}
