import pytest
from brownie import config, config

@pytest.fixture
def andre(accounts):
    # Andre, giver of tokens, and maker of yield
    yield accounts[0]


@pytest.fixture
def token(dai):
    yield dai


@pytest.fixture
def ntrump(interface):
    yield interface.nTrump('0x44Ea84a85616F8e9cD719Fc843DE31D852ad7240')
@pytest.fixture
def dai(interface):
    yield interface.ERC20('0x6b175474e89094c44da98b954eedeac495271d0f')
    

@pytest.fixture
def bpool(interface):
    yield interface.bPool('0xEd0413D19cDf94759bBE3FE9981C4bd085b430Cf')

@pytest.fixture
def gov(accounts):
    # yearn multis... I mean YFI governance. I swear!
    yield accounts[1]


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract


@pytest.fixture
def guardian(accounts):
    # YFI Whale, probably
    yield accounts[2]


@pytest.fixture
def vault(pm, gov, rewards, guardian, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = gov.deploy(Vault, token, gov, rewards, "", "")
    yield vault


@pytest.fixture
def strategist(accounts):
    # You! Our new Strategist!
    yield accounts[3]


@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    yield strategy


@pytest.fixture
def nocoiner(accounts):
    # Has no tokens (DeFi is a ponzi scheme!)
    yield accounts[5]


@pytest.fixture
def pleb(accounts, andre, token, vault):
    # Small fish in a big pond
    a = accounts[6]
    # Has 0.01% of tokens (heard about this new DeFi thing!)
    bal = token.totalSupply() // 10000
    token.transfer(a, bal, {"from": andre})
    # Unlimited Approvals
    token.approve(vault, 2 ** 256 - 1, {"from": a})
    # Deposit half their stack
    vault.deposit(bal // 2, {"from": a})
    yield a


@pytest.fixture
def chad(accounts, andre, token, vault):
    # Just here to have fun!
    a = accounts[7]
    # Has 0.1% of tokens (somehow makes money trying every new thing)
    bal = token.totalSupply() // 1000
    token.transfer(a, bal, {"from": andre})
    # Unlimited Approvals
    token.approve(vault, 2 ** 256 - 1, {"from": a})
    # Deposit half their stack
    vault.deposit(bal // 2, {"from": a})
    yield a


@pytest.fixture
def greyhat(accounts, andre, token, vault):
    # Chaotic evil, will eat you alive
    a = accounts[8]
    # Has 1% of tokens (earned them the *hard way*)
    bal = token.totalSupply() // 100
    token.transfer(a, bal, {"from": andre})
    # Unlimited Approvals
    token.approve(vault, 2 ** 256 - 1, {"from": a})
    # Deposit half their stack
    vault.deposit(bal // 2, {"from": a})
    yield a


@pytest.fixture
def whale(accounts, web3, dai, gov, chain):
    #big binance7 wallet
    acc = accounts.at('0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8', force=True)
    #big binance8 wallet
    #acc = accounts.at('0xf977814e90da44bfa03b6295a0616a897441acec', force=True)

    
    dai.transfer(gov, 10000 *1e18,{"from": acc} )

    yield acc

@pytest.fixture
def ntrumpWhale(accounts):
    #big binance7 wallet
    acc = accounts.at('0x228c1334fc57Eb6E02EcC448E749a041124321c1', force=True)
   
    yield acc


@pytest.fixture()
def strategy(strategist,gov, keeper, vault,  Strategy):
    strategy = strategist.deploy(Strategy,vault)
    strategy.setKeeper(keeper)

    vault.addStrategy(
        strategy,
        2 ** 256 - 1,2 ** 256 - 1, 
        1000,  # 0.5% performance fee for Strategist
        {"from": gov},
    )
    yield strategy


@pytest.fixture()
def running_strategy(gov, strategy, dai, vault, whale):

    amount = Wei('10000 ether')
    dai.approve(vault, amount, {'from': whale})
    vault.deposit(amount, {'from': whale})    

    strategy.harvest({'from': gov})
    
    yield strategy