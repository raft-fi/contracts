#!/bin/bash

certoraRun certora/contracts/PositionManagerHarness.sol:PositionManagerHarness \
                    contracts/ERC20Indexable.sol:ERC20Indexable \
                    contracts/RToken.sol:RToken \
            --verify PositionManagerHarness:certora/specs/PositionManagerManagePosition.spec \
            --solc_args "['--via-ir','--optimize']" \
            --link PositionManagerHarness:raftDebtToken=ERC20Indexable \
                    PositionManagerHarness:rToken=RToken \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts/
