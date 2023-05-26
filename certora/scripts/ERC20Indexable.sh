#!/bin/bash

certoraRun certora/contracts/ERC20IndexableHarness.sol:ERC20IndexableHarness \
            --verify ERC20IndexableHarness:certora/specs/ERC20Indexable.spec \
            --optimistic_loop \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts
