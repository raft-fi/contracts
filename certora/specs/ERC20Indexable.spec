/*
    This is a specification file for the verification of ERC20Indexable
    smart contract using the Certora prover.
*/

////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/
methods {
    totalSupply()                         returns (uint256)   envfree
    balanceOf(address)                    returns (uint256)   envfree
    allowance(address,address)            returns (uint256)   envfree
    name()                                returns (string)    envfree
    symbol()                              returns (string)    envfree
    currentIndex()                        returns (uint256)   envfree
    totalSupplyERC20()                    returns (uint256)   envfree
    balanceOfERC20(address)               returns (uint256)   envfree
    setIndex(uint256)
    increaseAllowance(address, uint256)
    decreaseAllowance(address, uint256)
    transfer(address,uint256)
    transferFrom(address,address,uint256)
    mint(address,uint256)
    burn(address,uint256)
}

// Check functions that change the balance of the user
rule CheckFunctionsThatChangeBalance(method f) filtered {
		f -> f.selector != mint(address,uint256).selector && 
            f.selector != burn(address,uint256).selector &&
            f.selector != setIndex(uint256).selector
	}
{
    env e;

    uint256 balanceOfUserBefore = balanceOf(e.msg.sender);

    calldataarg args;
    f(e, args);

    assert balanceOfUserBefore == balanceOf(e.msg.sender);
}

// Check currentIndex cannot be zero
rule CheckCurrentIndexCannotBeZero(uint256 backingAmount) {
    require currentIndex() != 0;
    // TODO Create a rule in PositionManager that backingAmount cannot be zero (with ERC20.totalSupply is not zero )
    require backingAmount != 0;

    env e;
    setIndex(e, backingAmount);

    assert currentIndex() != 0;
}

// Check total supply is greater or equal to sum of user balances
rule CheckTotalSupplyMustBeGreaterOrEqualThanSumOfUserBalances(method f, address user, uint256 amount) {
    address user1;
    require user != user1;
    require balanceOfERC20(user) + balanceOfERC20(user1) == totalSupplyERC20();
    
    env e;
    if (f.selector == mint(address,uint256).selector) {
        mint(e, user, amount);
    } else if (f.selector == burn(address,uint256).selector) {
        burn(e, user, amount); 
    } else {
        calldataarg args;
        f(e, args);
    }

    assert balanceOf(user) + balanceOf(user1) <= totalSupply();
}
