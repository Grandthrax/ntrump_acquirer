# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")
from itertools import count
from brownie import Wei, reverts
from useful_methods import genericStateOfStrat, genericStateOfVault
import random
import brownie

#passes on block 11336234
def test_deposit( strategy, bpool, vault,ntrumpWhale, whale, gov, dai, strategist,ntrump):
    dai.approve(vault, 2 ** 256 - 1, {'from': whale})
    dai.approve(bpool, 2 ** 256 - 1, {'from': whale})
    ntrump.approve(bpool, 2 ** 256 - 1, {'from': ntrumpWhale})

    amount = Wei('10000 ether')
    vault.deposit(amount, {'from': whale})    

    ##big buy to lower price
    bpool.swapExactAmountIn(dai,3000 * 1e18, ntrump, 0,2 ** 256 - 1, {'from': whale})

    strategy.harvest({'from': gov})
    print("dai in strat ", dai.balanceOf(strategy)/1e18)
    print("is finalised? ", strategy.isFinalized())

    sellOrBuy =strategy.sellOrBuy()
    

    assert sellOrBuy[0] == False
    assert sellOrBuy[1] == False
    print("buy or sell? ", sellOrBuy)


    assert strategy.harvestTrigger(1e10) == False
    assert strategy.tendTrigger(1e10) == False

    bpool.swapExactAmountIn(ntrump,10000 * 1e15, dai, 0,2 ** 256 - 1, {'from': ntrumpWhale})
    assert strategy.tendTrigger(1e10) == True
    assert ntrump.balanceOf(strategy) == 0
    strategy.harvest({'from': gov})
    assert ntrump.balanceOf(strategy) > (strategy.minBuy() / 1e18) * (strategy.lotSizeBuy()/1e3)
    

    print("dai in strat ", dai.balanceOf(strategy)/1e18)
    print("ntrump in strat ", ntrump.balanceOf(strategy)/1e15)
    
    while strategy.tendTrigger(1e10) == True:
        strategy.harvest({'from': gov})

    print("dai in strat ", dai.balanceOf(strategy)/1e18)
    print("ntrump in strat ", ntrump.balanceOf(strategy)/1e15)
    sellOrBuy =strategy.sellOrBuy()
    
    assert strategy.harvestTrigger(1e10) == False
    assert sellOrBuy[0] == False
    assert sellOrBuy[1] == False
    print("buy or sell? ", sellOrBuy)
    print("average price: ", strategy.averagePrice()/1e18)


    #now sell
    #whale dumps all ntrump. like there is an end
    bpool.swapExactAmountIn(dai,dai.balanceOf(bpool)/4-1, ntrump, 0,2 ** 256 - 1, {'from': whale})
    bpool.swapExactAmountIn(dai,dai.balanceOf(bpool)/4-1, ntrump, 0,2 ** 256 - 1, {'from': whale})
    sellOrBuy =strategy.sellOrBuy()
    
    print("buy or sell? ", sellOrBuy)
    assert sellOrBuy[0] == False
    assert sellOrBuy[1] == True
    assert strategy.tendTrigger(1e10) == True
    ntrumpBefore = ntrump.balanceOf(strategy)
    strategy.harvest({'from': gov})
    assert ntrumpBefore > ntrump.balanceOf(strategy)
    oldPrice = vault.pricePerShare()
    assert vault.pricePerShare() < 1e18
    

    while strategy.tendTrigger(1e10) == True:
        strategy.harvest({'from': gov})
    assert strategy.tendTrigger(1e10) == False
    #one more to sell dust ntrump
    strategy.harvest({'from': gov})
    
    genericStateOfStrat(strategy, dai, vault)
    genericStateOfVault(vault, dai)
    print("ntrump in strat ", ntrump.balanceOf(strategy)/1e15)

    assert ntrump.balanceOf(strategy) == 0
    assert vault.strategies(strategy)[5] < dai.balanceOf(strategy)
    #profit reported
    assert vault.pricePerShare() > oldPrice
    

def test_end_market( strategy,interface, bpool, vault,ntrumpWhale,chain, whale, gov, dai, strategist,ntrump):
    marketAddress = "0x1EBb89156091EB0d59603C18379C03A5c84D7355"
    market = interface.IMarket(marketAddress)

    chain.sleep(60*3600)
    payouts = [0,0,1000]
    #market.doInitialReport(payouts, "some", 0, {'from': whale})

