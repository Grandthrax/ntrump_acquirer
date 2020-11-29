from itertools import count
from brownie import Wei, reverts
from useful_methods import genericStateOfStrat, genericStateOfVault
import random
import brownie

#passes on block 11336234
def test_deposit( live_strategy, bpool, live_vault,ntrumpWhale, samdev, whale, gov, dai, strategist,ntrump):
    genericStateOfStrat(live_strategy, dai, live_vault)
    genericStateOfVault(live_vault, dai)

    live_strategy.harvest({'from': samdev})