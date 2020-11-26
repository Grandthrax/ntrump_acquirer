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
    function tokenId() external view returns (uint256);
}

interface IShareToken {
    function getMarket(uint256 outcome) external view returns (address);    
}

interface IMarket {
   
    function getEndTime() external view returns (uint256);
    function getWinningPayoutDistributionHash() external view returns (bytes32);
    function getFinalizationTime() external view returns (uint256);
    function getDisputePacingOn() external view returns (bool);
    function isFinalizedAsInvalid() external view returns (bool);
    function finalize() external returns (bool);
    function isFinalized() external view returns (bool);
    function doInitialReport(uint256[] memory _payoutNumerators, string memory _description, uint256 _additionalStake) external returns (bool);
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


contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public minBuy = 1.2 ether;
    uint256 public minSell = 1.01 ether;
    uint256 public lotSizeBuy = 500 ether;
    uint256 public lotSizeSell = 500 *1e15;  //15 decimals


    uint256 public daiSpent = 0;

    nTrump public constant ntrump = nTrump(0x44Ea84a85616F8e9cD719Fc843DE31D852ad7240);
    bPool public bpool = bPool(0xEd0413D19cDf94759bBE3FE9981C4bd085b430Cf);

    constructor(address _vault) public BaseStrategy(_vault) {

        require(address(want) == 0x6B175474E89094C44Da98b954EedeAC495271d0F, "NOT DAI"); 
       
         minReportDelay = uint256(-1); // never call
         profitFactor = uint256(-1)/2; // never call
         debtThreshold = uint256(-1)/2;
        

        want.safeApprove(address(bpool), uint256(-1));
        ntrump.approve(address(bpool), uint256(-1));

    }
    modifier management() {
        require(msg.sender == governance() || msg.sender == strategist, "!management");
        _;
    }

    function setMinBuy(uint256 _minBuy) external management {
        minBuy = _minBuy;
        require(minSell < minBuy, "Below MinSell");
    }
    function setMinSell(uint256 _minSell) external management {
        minSell = _minSell;
        require(minSell < minBuy, "Above MinBuy");
    }
    function setLotBuy(uint256 _minLot) external management {
        lotSizeBuy = _minLot;
    }
    function setLotSell(uint256 _minLot) external management {
        lotSizeSell = _minLot;
    }
    function setBalPool(address _bal) external management {
        want.safeApprove(_bal, uint256(-1));
        bpool =  bPool(_bal);
    }

    function name() external override pure returns (string memory) {
        return "NTrumpAcquirer";
    }

    
    function estimatedTotalAssets() public override view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedSettlementProfit() public view returns (uint256) {
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 assets = estimatedTotalAssets().add(nTrumpOwned().mul(1e3));
        if(assets > debt){
            return assets - debt;
        }
        
    }

    function averagePrice() public view returns (uint256) {
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 left = want.balanceOf(address(this));
        if(left > debt) return 0;
        uint256 spent = debt.sub(left);
        uint256 assets = nTrumpOwned().mul(1e3);
        if(assets > spent){
            return assets.mul(1e18).div(spent);
        }
        
    }

    function nTrumpOwned() public view returns (uint256) {
        return ntrump.balanceOf(address(this));
    }

   
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

    function adjustPosition(uint256 _debtOutstanding) internal override {
        _debtOutstanding;

        if(isFinalized())
        {
            return;
        }

        (bool buy, bool sell) = sellOrBuy();

        uint256 ntrumpBal = ntrump.balanceOf(address(this));

        if(buy && want.balanceOf(address(this)) > lotSizeBuy){
            swap(address(want), address(ntrump), lotSizeBuy);

        }else if (sell && ntrumpBal > 0) {
            swap(address(ntrump), address(want), Math.min(ntrumpBal, lotSizeSell));
        }

    }

    function sellOrBuy() public view returns (bool _buy, bool _sell){
        uint256 weightD = bpool.getDenormalizedWeight(address(want));
        uint256 weightN = bpool.getDenormalizedWeight(address(ntrump));
        uint256 balanceD = bpool.getBalance(address(want));
        uint256 balanceN = bpool.getBalance(address(ntrump));
        uint256 swapFee = bpool.getSwapFee();

        //dai to ntrump
        uint256 outAmount = bpool.calcOutGivenIn(balanceD, weightD, balanceN, weightN, lotSizeBuy, swapFee);

        //decimal changes make this harder. 1e21 = 18 + 18 - 15
        if(outAmount >= lotSizeBuy.mul(minBuy).div(1e21)){
            _buy = true;
            //return(true,false);
        }

        //ntrump to dai
        outAmount = bpool.calcOutGivenIn(balanceN, weightN, balanceD, weightD, lotSizeSell, swapFee);

        //decimal changes make this harder. 1e21 = 18 + 18 - 15
        if(outAmount.mul(minSell).div(1e21) >=  lotSizeSell){
            _sell = true;
             //return(false, true);
        }
    }

    function isFinalized() public view returns (bool){
         IShareToken shareToken = IShareToken(ntrump.shareToken());
         IMarket market = IMarket(shareToken.getMarket(ntrump.tokenId()));
        
        return market.isFinalized();
    }

    function swap(
        address _erc20ContractIn, address _erc20ContractOut, uint256 _numTokensToSupply
    ) private returns (uint256) {

        (uint256 a, ) = bpool.swapExactAmountIn(
            _erc20ContractIn,_numTokensToSupply,_erc20ContractOut, 0,uint256(-1));

        return a;
       
    }

    
    function exitPosition()
        internal
        override
        returns (uint256 _loss, uint256 _debtPayment)
    {
        _loss;
        _debtPayment; //suppress
        require(false, "Emergency Exit Disallowed");
    }

    
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

        if(buy && want.balanceOf(address(this)) > lotSizeBuy){
            return true;
        }
        
        if (sell && ntrump.balanceOf(address(this)) > lotSizeSell){
            return true;
        }
    }

    
    function prepareMigration(address _newStrategy) internal override {
        

        want.safeTransfer(_newStrategy, want.balanceOf(address(this)));
        ntrump.transfer(_newStrategy, ntrump.balanceOf(address(this)));
    }

    
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
