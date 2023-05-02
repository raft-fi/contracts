#!/bin/bash

certoraRun certora/contracts/ERC20IndexableCertora.sol:ERC20IndexableCertora \
            --verify ERC20IndexableCertora:certora/specs/ERC20Indexable.spec \
            --optimistic_loop \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts/
