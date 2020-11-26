// SPDX-License-Identifier: GPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/Math.sol";


interface nTrump is IERC20{
    function claim(address _account) external;
    function shareToken() external view returns (IShareToken);
    function tokenId() external returns (uint256);
}

interface IShareToken {
    function isFinalized() external view returns (bool);
}

interface IMarket {
   
    function getEndTime() external view returns (uint256);
    function getWinningPayoutDistributionHash() external view returns (bytes32);
    function getFinalizationTime() external view returns (uint256);
    function getDisputePacingOn() external view returns (bool);
    function isFinalizedAsInvalid() external view returns (bool);
    function finalize() external returns (bool);
    function isFinalized() external view returns (bool);
}

interface bPool{
    function getSwapFee() external view returns (uint);
    
    function gulp(address token) external;
    function getDenormalizedWeight(address token) external view returns (uint);
    function getBalance(address token) external view returns (uint);

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    ) external returns (uint tokenAmountOut, uint spotPriceAfter);

    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    ) external pure returns (uint tokenAmountOut);

}

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public minBuy = 1.2 ether;
    uint256 public minSell = 1.01 ether;
    uint256 public lotSize = 500;


    uint256 public daiSpent = 0;

    nTrump public constant ntrump = nTrump(0x44Ea84a85616F8e9cD719Fc843DE31D852ad7240);
    bPool public bpool = bPool(0xEd0413D19cDf94759bBE3FE9981C4bd085b430Cf);

    constructor(address _vault) public BaseStrategy(_vault) {

        require(address(want) == 0x6B175474E89094C44Da98b954EedeAC495271d0F, "NOT DAI"); //DAI
        // You can set these parameters on deployment to whatever you want
        // minReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;

        want.safeApprove(address(bpool), uint256(-1));

    }
    modifier management() {
        require(msg.sender == governance() || msg.sender == strategist, "!management");
        _;
    }

    function setMinBuy(uint256 _minBuy) external management {
        minBuy = _minBuy;
    }
    function setMinSell(uint256 _minSell) external management {
        minSell = _minSell;
    }
    function setMinLot(uint256 _minLot) external management {
        lotSize = _minLot;
    }
    function setBalPool(address _bal) external management {
        want.safeApprove(_bal, uint256(-1));
        bpool =  bPool(_bal);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external override pure returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "NTrumpAcquirer";
    }

    /*
     * Provide an accurate estimate for the total amount of assets (principle + return)
     * that this strategy is currently managing, denominated in terms of `want` tokens.
     * This total should be "realizable" e.g. the total value that could *actually* be
     * obtained from this strategy if it were to divest it's entire position based on
     * current on-chain conditions.
     *
     * NOTE: care must be taken in using this function, since it relies on external
     *       systems, which could be manipulated by the attacker to give an inflated
     *       (or reduced) value produced by this function, based on current on-chain
     *       conditions (e.g. this function is possible to influence through flashloan
     *       attacks, oracle manipulations, or other DeFi attack mechanisms).
     *
     * NOTE: It is up to governance to use this function in order to correctly order
     *       this strategy relative to its peers in order to minimize losses for the
     *       Vault based on sudden withdrawals. This value should be higher than the
     *       total debt of the strategy and higher than it's expected value to be "safe".
     */
    function estimatedTotalAssets() public override view returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        return want.balanceOf(address(this));
    }

    function estimatedSettlementProfit() public view returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 assets = estimatedTotalAssets().add(nTrumpOwned());
        if(assets > debt){
            return assets - debt;
        }
        
    }

    function nTrumpOwned() public view returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        return ntrump.balanceOf(address(this));
    }

    /*
     * Perform any strategy unwinding or other calls necessary to capture the "free return"
     * this strategy has generated since the last time it's core position(s) were adjusted.
     * Examples include unwrapping extra rewards. This call is only used during "normal operation"
     * of a Strategy, and should be optimized to minimize losses as much as possible. This method
     * returns any realized profits and/or realized losses incurred, and should return the total
     * amounts of profits/losses/debt payments (in `want` tokens) for the Vault's accounting
     * (e.g. `want.balanceOf(this) >= _debtPayment + _profit - _loss`).
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`. It is okay for it
     *       to be less than `_debtOutstanding`, as that should only used as a guide for how much
     *       is left to pay back. Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _loss; //we dont lose

        
        uint256 debt = vault.strategies(address(this)).totalDebt;

        //if market is over. and we have ntrump. and ntrump has dai (means it won)
        if(isFinalized() && ntrump.balanceOf(address(this)) > 0)
        {
            //if we have ntokens and market is finalised and there is no dai in ntrump we lost
            if(want.balanceOf(address(ntrump)) > 0){
                ntrump.claim(address(this));
            }else{
                _loss = debt.sub(want.balanceOf(address(this)));
            }
        }


        uint256 wantBalance = want.balanceOf(address(this));

        if(wantBalance > debt){
            _profit = want.balanceOf(address(this)) - debt;
        }

        _debtPayment = Math.min(wantBalance - _profit, _debtOutstanding);

    }

    /*
     * Perform any adjustments to the core position(s) of this strategy given
     * what change the Vault made in the "investable capital" available to the
     * strategy. Note that all "free capital" in the strategy after the report
     * was made is available for reinvestment. Also note that this number could
     * be 0, and you should handle that scenario accordingly.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        _debtOutstanding;

        if(isFinalized())
        {
            return;
        }

        (bool buy, bool sell) = sellOrBuy();

        if(buy){
            swap(address(want), address(ntrump), lotSize);

        }else if (sell) {
            swap(address(ntrump), address(want), lotSize);
        }

    }

    function sellOrBuy() public view returns (bool _buy, bool _sell){
        uint256 weightD = bpool.getDenormalizedWeight(address(want));
        uint256 weightN = bpool.getDenormalizedWeight(address(ntrump));
        uint256 balanceD = bpool.getBalance(address(want));
        uint256 balanceN = bpool.getBalance(address(ntrump));
        uint256 swapFee = bpool.getSwapFee();

        //dai to ntrump
        uint256 outAmount = bpool.calcOutGivenIn(balanceD, weightD, balanceN, weightN, lotSize, swapFee);

        if(outAmount >= lotSize.mul(minBuy).div(1e18)){
            return(true,false);
        }

        //ntrump to dai
        outAmount = bpool.calcOutGivenIn(balanceN, weightN, balanceD, weightD, lotSize, swapFee);

        if(outAmount.mul(minSell).div(1e18) >=  lotSize){
             return(false, true);
        }


    }

    function isFinalized() public view returns (bool){
         IShareToken shareToken = IShareToken(ntrump.shareToken());
        
        return shareToken.isFinalized();
    }

    function swap(
        address _erc20ContractIn, address _erc20ContractOut, uint256 _numTokensToSupply
    ) private returns (uint256) {

        (uint256 a, ) = bpool.swapExactAmountIn(
            _erc20ContractIn,_numTokensToSupply,_erc20ContractOut, 0,uint256(-1));

        return a;
       
    }

    /*
     * Make as much capital as possible "free" for the Vault to take. Some slippage
     * is allowed, since when this method is called the strategist is no longer receiving
     * their performance fee. The goal is for the strategy to divest as quickly as possible
     * while not suffering exorbitant losses. This function is used during emergency exit
     * instead of `prepareReturn()`. This method returns any realized losses incurred, and
     * should also return the amount of `want` tokens available to repay outstanding debt
     * to the Vault.
     */
    function exitPosition()
        internal
        override
        returns (uint256 _loss, uint256 _debtPayment)
    {
        _loss;
        _debtPayment; //suppress
        require(false, "Emergency Exit Disallowed");
        // TODO: Do stuff here to free up as much as possible of all positions back into `want`
        // TODO: returns any realized losses incurred, and should also return the amount of `want` tokens available to repay back to the Vault.
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amountNeeded`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _amountFreed)
    {
        _amountFreed = Math.min(want.balanceOf(address(this)), _amountNeeded);
        

    }

    function harvestTrigger(uint256 callCost) public override view returns (bool) {
        if(isFinalized() && ntrump.balanceOf(address(this)) > 0 && want.balanceOf(address(ntrump)) > 0){
            return true;
        }

        return super.harvestTrigger(callCost);
    }

    function tendTrigger(uint256 callCost) public override view returns (bool) {
        if(isFinalized()){
            return false;
        }

        if(harvestTrigger(callCost)){
            return false;
        }
       
        (bool buy,bool sell) = sellOrBuy();

        if(buy || sell){
            return true;
        }
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    /*
     * Do anything necesseary to prepare this strategy for migration, such
     * as transfering any reserve or LP tokens, CDPs, or other tokens or stores of value.
     */
    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one

        want.safeTransfer(_newStrategy, want.balanceOf(address(this)));
        ntrump.transfer(_newStrategy, ntrump.balanceOf(address(this)));
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistant* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        override
        view
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(want);
        protected[1] = address(ntrump);
        return protected;

    }
}
