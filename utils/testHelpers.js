const MoneyValues = {
  negative_5e17: "-" + web3.utils.toWei('500', 'finney'),
  negative_1e18: "-" + web3.utils.toWei('1', 'ether'),
  negative_10e18: "-" + web3.utils.toWei('10', 'ether'),
  negative_50e18: "-" + web3.utils.toWei('50', 'ether'),
  negative_100e18: "-" + web3.utils.toWei('100', 'ether'),
  negative_101e18: "-" + web3.utils.toWei('101', 'ether'),
  negative_eth: (amount) => "-" + web3.utils.toWei(amount, 'ether'),

  _zeroBN: web3.utils.toBN('0'),
  _1e18BN: web3.utils.toBN('1000000000000000000'),
  _10e18BN: web3.utils.toBN('10000000000000000000'),
  _100e18BN: web3.utils.toBN('100000000000000000000'),
  _100BN: web3.utils.toBN('100'),
  _110BN: web3.utils.toBN('110'),
  _150BN: web3.utils.toBN('150'),

  _MCR: web3.utils.toBN('1100000000000000000'),
  _ICR100: web3.utils.toBN('1000000000000000000'),
  _CCR: web3.utils.toBN('1500000000000000000'),
}

const TimeValues = {
  SECONDS_IN_ONE_MINUTE:  60,
  SECONDS_IN_ONE_HOUR:    60 * 60,
  SECONDS_IN_ONE_DAY:     60 * 60 * 24,
  SECONDS_IN_ONE_WEEK:    60 * 60 * 24 * 7,
  SECONDS_IN_SIX_WEEKS:   60 * 60 * 24 * 7 * 6,
  SECONDS_IN_ONE_MONTH:   60 * 60 * 24 * 30,
  SECONDS_IN_ONE_YEAR:    60 * 60 * 24 * 365,
  MINUTES_IN_ONE_WEEK:    60 * 24 * 7,
  MINUTES_IN_ONE_MONTH:   60 * 24 * 30,
  MINUTES_IN_ONE_YEAR:    60 * 24 * 365
}

class TestHelper {

  static dec(val, scale) {
    let zerosCount

    if (scale == 'ether') {
      zerosCount = 18
    } else if (scale == 'finney')
      zerosCount = 15
    else {
      zerosCount = scale
    }

    const strVal = val.toString()
    const strZeros = ('0').repeat(zerosCount)

    return strVal.concat(strZeros)
  }

  static squeezeAddr(address) {
    const len = address.length
    return address.slice(0, 6).concat("...").concat(address.slice(len - 4, len))
  }

  static getDifference(x, y) {
    const x_BN = web3.utils.toBN(x)
    const y_BN = web3.utils.toBN(y)

    return Number(x_BN.sub(y_BN).abs())
  }

  static assertIsApproximatelyEqual(x, y, error = 1000) {
    assert.isAtMost(this.getDifference(x, y), error)
  }

  static zipToObject(array1, array2) {
    let obj = {}
    array1.forEach((element, idx) => obj[element] = array2[idx])
    return obj
  }

  static getGasMetrics(gasCostList) {
    const minGas = Math.min(...gasCostList)
    const maxGas = Math.max(...gasCostList)

    let sum = 0;
    for (const gas of gasCostList) {
      sum += gas
    }

    if (sum === 0) {
      return {
        gasCostList: gasCostList,
        minGas: undefined,
        maxGas: undefined,
        meanGas: undefined,
        medianGas: undefined
      }
    }
    const meanGas = sum / gasCostList.length

    // median is the middle element (for odd list size) or element adjacent-right of middle (for even list size)
    const sortedGasCostList = [...gasCostList].sort()
    const medianGas = (sortedGasCostList[Math.floor(sortedGasCostList.length / 2)])
    return { gasCostList, minGas, maxGas, meanGas, medianGas }
  }

  static getGasMinMaxAvg(gasCostList) {
    const metrics = th.getGasMetrics(gasCostList)

    const minGas = metrics.minGas
    const maxGas = metrics.maxGas
    const meanGas = metrics.meanGas
    const medianGas = metrics.medianGas

    return { minGas, maxGas, meanGas, medianGas }
  }

  static getEndOfAccount(account) {
    const accountLast2bytes = account.slice((account.length - 4), account.length)
    return accountLast2bytes
  }

  static randDecayFactor(min, max) {
    const amount = Math.random() * (max - min) + min;
    const amountInWei = web3.utils.toWei(amount.toFixed(18), 'ether')
    return amountInWei
  }

  static randAmountInWei(min, max) {
    const amount = Math.random() * (max - min) + min;
    const amountInWei = web3.utils.toWei(amount.toString(), 'ether')
    return amountInWei
  }

  static randAmountInGWei(min, max) {
    const amount = Math.floor(Math.random() * (max - min) + min);
    const amountInWei = web3.utils.toWei(amount.toString(), 'gwei')
    return amountInWei
  }

  static makeWei(num) {
    return web3.utils.toWei(num.toString(), 'ether')
  }

  static appendData(results, message, data) {
    data.push(message + `\n`)
    for (const key in results) {
      data.push(key + "," + results[key] + '\n')
    }
  }

  static getRandICR(min, max) {
    const ICR_Percent = (Math.floor(Math.random() * (max - min) + min))

    // Convert ICR to a duint
    const ICR = web3.utils.toWei((ICR_Percent * 10).toString(), 'finney')
    return ICR
  }

  static async ICRbetween100and110(account, positionManager, price) {
    const ICR = await positionManager.getCurrentICR(account, price)
    return (ICR.gt(MoneyValues._ICR100)) && (ICR.lt(MoneyValues._MCR))
  }

  static async isUndercollateralized(account, positionManager, price) {
    const ICR = await positionManager.getCurrentICR(account, price)
    return ICR.lt(MoneyValues._MCR)
  }

  static toBN(num) {
    return web3.utils.toBN(num)
  }

  static gasUsed(tx) {
    const gas = tx.receipt.gasUsed
    return gas
  }

  static applyLiquidationFee(ethAmount) {
    return ethAmount.mul(this.toBN(this.dec(995, 15))).div(MoneyValues._1e18BN)
  }
  // --- Logging functions ---

  static logGasMetrics(gasResults, message) {
    console.log(
      `\n ${message} \n
      min gas: ${gasResults.minGas} \n
      max gas: ${gasResults.maxGas} \n
      mean gas: ${gasResults.meanGas} \n
      median gas: ${gasResults.medianGas} \n`
    )
  }

  static logAllGasCosts(gasResults) {
    console.log(
      `all gas costs: ${gasResults.gasCostList} \n`
    )
  }

  static logGas(gas, message) {
    console.log(
      `\n ${message} \n
      gas used: ${gas} \n`
    )
  }

  static logBN(label, x) {
    x = x.toString().padStart(18, '0')
    // TODO: thousand separators
    const integerPart = x.slice(0, x.length-18) ? x.slice(0, x.length-18) : '0'
    console.log(`${label}:`, integerPart + '.' + x.slice(-18))
  }

  // --- Gas compensation calculation functions ---

  // Given a composite debt, returns the actual debt  - i.e. subtracts the virtual debt.
  // Virtual debt = 50 R.
  static async getActualDebtFromComposite(compositeDebt, contracts) {
    const issuedDebt = await contracts.positionManager.getActualDebtFromComposite(compositeDebt)
    return issuedDebt
  }

  // Adds the gas compensation (50 R)
  static async getCompositeDebt(contracts, debt) {
    return contracts.math.getCompositeDebt(debt)
  }

  static async getPositionEntireColl(contracts, position) {
    return this.toBN((await contracts.positionManager.getEntireDebtAndColl(position))[1])
  }

  static async getPositionEntireDebt(contracts, position) {
    return this.toBN((await contracts.positionManager.getEntireDebtAndColl(position))[0])
  }

  static async getPositionStake(contracts, position) {
    return (await contracts.positionManager.positions(position))[2]
  }

  /*
   * given the requested R amomunt in openPosition, returns the total debt
   * So, it adds the gas compensation and the borrowing fee
   */
  static async getOpenPositionTotalDebt(contracts, rAmount) {
    const fee = await contracts.positionManager.getBorrowingFee(rAmount)
    const compositeDebt = await this.getCompositeDebt(contracts, rAmount)
    return compositeDebt.add(fee)
  }

  /*
   * given the desired total debt, returns the R amount that needs to be requested in openPosition
   * So, it subtracts the gas compensation and then the borrowing fee
   */
  static async getOpenPositionRAmount(contracts, totalDebt) {
    const actualDebt = await this.getActualDebtFromComposite(totalDebt, contracts)
    return this.getNetBorrowingAmount(contracts, actualDebt)
  }

  // Subtracts the borrowing fee
  static async getNetBorrowingAmount(contracts, debtWithFee) {
    const borrowingRate = await contracts.positionManager.getBorrowingRateWithDecay()
    const result = this.toBN(debtWithFee).mul(MoneyValues._1e18BN).div(MoneyValues._1e18BN.add(borrowingRate))

    if (borrowingRate.umod(MoneyValues._1e18BN).isZero()) {
      return result
    }

    return result.add(this.toBN('1'))
  }

  // Adds the borrowing fee
  static async getAmountWithBorrowingFee(contracts, rAmount) {
    const fee = await contracts.positionManager.getBorrowingFee(rAmount)
    return rAmount.add(fee)
  }

  // Adds the redemption fee
  static async getRedemptionGrossAmount(contracts, expected) {
    const redemptionRate = await contracts.positionManager.getRedemptionRate()
    return expected.mul(MoneyValues._1e18BN).div(MoneyValues._1e18BN.add(redemptionRate))
  }

  // Get's total collateral minus total gas comp, for a series of positions.
  static async getExpectedTotalCollMinusTotalGasComp(positionList, contracts) {
    let totalCollRemainder = web3.utils.toBN('0')

    for (const position of positionList) {
      const remainingColl = this.getCollMinusGasComp(position, contracts)
      totalCollRemainder = totalCollRemainder.add(remainingColl)
    }
    return totalCollRemainder
  }

  static getEmittedRedemptionValues(redemptionTx) {
    for (let i = 0; i < redemptionTx.logs.length; i++) {
      if (redemptionTx.logs[i].event === "Redemption") {

        const rAmount = redemptionTx.logs[i].args[0]
        const totalRRedeemed = redemptionTx.logs[i].args[1]
        const totalETHDrawn = redemptionTx.logs[i].args[2]
        const ETHFee = redemptionTx.logs[i].args[3]

        return [rAmount, totalRRedeemed, totalETHDrawn, ETHFee]
      }
    }
    throw ("The transaction logs do not contain a redemption event")
  }

  static getEmittedLiquidatedDebt(liquidationTx) {
    return this.getLiquidationEventArg(liquidationTx, 0)  // LiquidatedDebt is position 0 in the Liquidation event
  }

  static getEmittedLiquidatedColl(liquidationTx) {
    return this.getLiquidationEventArg(liquidationTx, 1) // LiquidatedColl is position 1 in the Liquidation event
  }

  static getEmittedGasComp(liquidationTx) {
    return this.getLiquidationEventArg(liquidationTx, 2) // GasComp is position 2 in the Liquidation event
  }

  static getLiquidationEventArg(liquidationTx, arg) {
    for (let i = 0; i < liquidationTx.logs.length; i++) {
      if (liquidationTx.logs[i].event === "Liquidation") {
        return liquidationTx.logs[i].args[arg]
      }
    }

    throw ("The transaction logs do not contain a liquidation event")
  }

  static getRfeeFromRBorrowingEvent(tx) {
    for (let i = 0; i < tx.logs.length; i++) {
      if (tx.logs[i].event === "RBorrowingFeePaid") {
        return (tx.logs[i].args[1]).toString()
      }
    }
    throw ("The transaction logs do not contain an RBorrowingFeePaid event")
  }

  static getEventArgByIndex(tx, eventName, argIndex) {
    for (let i = 0; i < tx.logs.length; i++) {
      if (tx.logs[i].event === eventName) {
        return tx.logs[i].args[argIndex]
      }
    }
    throw (`The transaction logs do not contain event ${eventName}`)
  }

  static getEventArgByName(tx, eventName, argName) {
    for (let i = 0; i < tx.logs.length; i++) {
      if (tx.logs[i].event === eventName) {
        const keys = Object.keys(tx.logs[i].args)
        for (let j = 0; j < keys.length; j++) {
          if (keys[j] === argName) {
            return tx.logs[i].args[keys[j]]
          }
        }
      }
    }

    throw (`The transaction logs do not contain event ${eventName} and arg ${argName}`)
  }

  static expectNoEventByName(tx, eventName) {
    for (let i = 0; i < tx.logs.length; i++) {
      if (tx.logs[i].event === eventName) {
        throw (`Found event with the name ${eventName}`)
      }
    }
  }

  static getAllEventsByName(tx, eventName) {
    const events = []
    for (let i = 0; i < tx.logs.length; i++) {
      if (tx.logs[i].event === eventName) {
        events.push(tx.logs[i])
      }
    }
    return events
  }

  static async getEntireCollAndDebt(contracts, account) {
    // console.log(`account: ${account}`)
    const rawColl = (await contracts.positionManager.positions(account))[1]
    const rawDebt = (await contracts.positionManager.positions(account))[0]
    const pendingETHReward = await contracts.positionManager.getPendingCollateralTokenReward(account)
    const pendingRDebtReward = await contracts.positionManager.getPendingRDebtReward(account)
    const entireColl = rawColl.add(pendingETHReward)
    const entireDebt = rawDebt.add(pendingRDebtReward)

    return { entireColl, entireDebt }
  }

  static async getCollAndDebtFromAddColl(contracts, account, amount) {
    const { entireColl, entireDebt } = await this.getEntireCollAndDebt(contracts, account)

    const newColl = entireColl.add(this.toBN(amount))
    const newDebt = entireDebt
    return { newColl, newDebt }
  }

  static async getCollAndDebtFromWithdrawColl(contracts, account, amount) {
    const { entireColl, entireDebt } = await this.getEntireCollAndDebt(contracts, account)
    // console.log(`entireColl  ${entireColl}`)
    // console.log(`entireDebt  ${entireDebt}`)

    const newColl = entireColl.sub(this.toBN(amount))
    const newDebt = entireDebt
    return { newColl, newDebt }
  }

  static async getCollAndDebtFromWithdrawR(contracts, account, amount) {
    const fee = await contracts.positionManager.getBorrowingFee(amount)
    const { entireColl, entireDebt } = await this.getEntireCollAndDebt(contracts, account)

    const newColl = entireColl
    const newDebt = entireDebt.add(this.toBN(amount)).add(fee)

    return { newColl, newDebt }
  }

  static async getCollAndDebtFromRepayR(contracts, account, amount) {
    const { entireColl, entireDebt } = await this.getEntireCollAndDebt(contracts, account)

    const newColl = entireColl
    const newDebt = entireDebt.sub(this.toBN(amount))

    return { newColl, newDebt }
  }

  static async getCollAndDebtFromAdjustment(contracts, account, ETHChange, RChange) {
    const { entireColl, entireDebt } = await this.getEntireCollAndDebt(contracts, account)

    // const coll = (await contracts.positionManager.positions(account))[1]
    // const debt = (await contracts.positionManager.positions(account))[0]

    const fee = RChange.gt(this.toBN('0')) ? await contracts.positionManager.getBorrowingFee(RChange) : this.toBN('0')
    const newColl = entireColl.add(ETHChange)
    const newDebt = entireDebt.add(RChange).add(fee)

    return { newColl, newDebt }
  }


  // --- positionManager gas functions ---

  static async openPosition(contracts, {
    maxFeePercentage,
    extraRAmount,
    upperHint,
    lowerHint,
    ICR,
    amount,
    extraParams
  }) {
    if (!maxFeePercentage) maxFeePercentage = this._100pct
    if (!extraRAmount) extraRAmount = this.toBN(0)
    else if (typeof extraRAmount == 'string') extraRAmount = this.toBN(extraRAmount)
    if (!upperHint) upperHint = this.ZERO_ADDRESS
    if (!lowerHint) lowerHint = this.ZERO_ADDRESS

    const MIN_DEBT = await this.getNetBorrowingAmount(contracts, await contracts.math.MIN_NET_DEBT())
    const rAmount = MIN_DEBT.add(extraRAmount)

    if (!ICR && !amount) ICR = this.toBN(this.dec(15, 17)) // 150%
    else if (typeof ICR == 'string') ICR = this.toBN(ICR)

    const totalDebt = await this.getOpenPositionTotalDebt(contracts, rAmount)
    const netDebt = await this.getActualDebtFromComposite(totalDebt, contracts)

    if (ICR) {
      const price = await contracts.priceFeedTestnet.getPrice()
      amount = ICR.mul(totalDebt).div(price)
    }

    await contracts.wstETHTokenMock.approve(contracts.positionManager.address, amount, extraParams)
    const tx = await contracts.positionManager.managePosition(amount, true, rAmount, true, upperHint, lowerHint, maxFeePercentage, extraParams)

    return {
      rAmount,
      netDebt,
      totalDebt,
      ICR,
      collateral: amount,
      tx
    }
  }

  static async withdrawR(contracts, {
    maxFeePercentage,
    rAmount,
    ICR,
    upperHint,
    lowerHint,
    extraParams
  }) {
    if (!maxFeePercentage) maxFeePercentage = this._100pct
    if (!upperHint) upperHint = this.ZERO_ADDRESS
    if (!lowerHint) lowerHint = this.ZERO_ADDRESS

    assert(!(rAmount && ICR) && (rAmount || ICR), "Specify either r amount or target ICR, but not both")

    let increasedTotalDebt
    if (ICR) {
      assert(extraParams.from, "A from account is needed")
      const { debt, coll } = await contracts.positionManager.getEntireDebtAndColl(extraParams.from)
      const price = await contracts.priceFeedTestnet.getPrice()
      const targetDebt = coll.mul(price).div(ICR)
      assert(targetDebt > debt, "ICR is already greater than or equal to target")
      increasedTotalDebt = targetDebt.sub(debt)
      rAmount = await this.getNetBorrowingAmount(contracts, increasedTotalDebt)
    } else {
      increasedTotalDebt = await this.getAmountWithBorrowingFee(contracts, rAmount)
    }

    await contracts.positionManager.managePosition(0, false, rAmount, true, upperHint, lowerHint, maxFeePercentage, extraParams)

    return {
      rAmount,
      increasedTotalDebt
    }
  }

  static async addColl_allAccounts(accounts, contracts, amount) {
    const gasCostList = []
    for (const account of accounts) {

      const { newColl, newDebt } = await this.getCollAndDebtFromAddColl(contracts, account, amount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.addColl(upperHint, lowerHint, { from: account, value: amount })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async addColl_allAccounts_randomAmount(min, max, accounts, contracts) {
    const gasCostList = []
    for (const account of accounts) {
      const randCollAmount = this.randAmountInWei(min, max)

      const { newColl, newDebt } = await this.getCollAndDebtFromAddColl(contracts, account, randCollAmount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.addColl(upperHint, lowerHint, { from: account, value: randCollAmount })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async withdrawColl_allAccounts(accounts, contracts, amount) {
    const gasCostList = []
    for (const account of accounts) {
      const { newColl, newDebt } = await this.getCollAndDebtFromWithdrawColl(contracts, account, amount)
      // console.log(`newColl: ${newColl} `)
      // console.log(`newDebt: ${newDebt} `)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(amount, false, 0, false, upperHint, lowerHint, 0, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async withdrawColl_allAccounts_randomAmount(min, max, accounts, contracts) {
    const gasCostList = []

    for (const account of accounts) {
      const randCollAmount = this.randAmountInWei(min, max)

      const { newColl, newDebt } = await this.getCollAndDebtFromWithdrawColl(contracts, account, randCollAmount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(randCollAmount, false, 0, false, upperHint, lowerHint, 0, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
      // console.log("gasCostlist length is " + gasCostList.length)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async withdrawR_allAccounts(accounts, contracts, amount) {
    const gasCostList = []

    for (const account of accounts) {
      const { newColl, newDebt } = await this.getCollAndDebtFromWithdrawR(contracts, account, amount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(0, false, amount, true, upperHint, lowerHint, this._100pct, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async withdrawR_allAccounts_randomAmount(min, max, accounts, contracts) {
    const gasCostList = []

    for (const account of accounts) {
      const randRAmount = this.randAmountInWei(min, max)

      const { newColl, newDebt } = await this.getCollAndDebtFromWithdrawR(contracts, account, randRAmount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(0, false, randRAmount, true, upperHint, lowerHint, this._100pct, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async repayR_allAccounts(accounts, contracts, amount) {
    const gasCostList = []

    for (const account of accounts) {
      const { newColl, newDebt } = await this.getCollAndDebtFromRepayR(contracts, account, amount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(0, false, amount, false, upperHint, lowerHint, 0, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static async repayR_allAccounts_randomAmount(min, max, accounts, contracts) {
    const gasCostList = []

    for (const account of accounts) {
      const randRAmount = this.randAmountInWei(min, max)

      const { newColl, newDebt } = await this.getCollAndDebtFromRepayR(contracts, account, randRAmount)
      const {upperHint, lowerHint} = await this.getBorrowerOpsListHint(contracts, newColl, newDebt)

      const tx = await contracts.positionManager.managePosition(0, false, randRAmount, false, upperHint, lowerHint, 0, { from: account })
      const gas = this.gasUsed(tx)
      gasCostList.push(gas)
    }
    return this.getGasMetrics(gasCostList)
  }

  static getLCAddressFromDeploymentTx(deployedLCTx) {
    return deployedLCTx.logs[0].args[0]
  }

  static async getLCFromDeploymentTx(deployedLCTx) {
    const deployedLCAddress = this.getLCAddressFromDeploymentTx(deployedLCTx)  // grab addr of deployed contract from event
    const LC = await this.getLCFromAddress(deployedLCAddress)
    return LC
  }

  // --- Time functions ---

  static async fastForwardTime(seconds, currentWeb3Provider) {
    await currentWeb3Provider.send({
      id: 0,
      jsonrpc: '2.0',
      method: 'evm_increaseTime',
      params: [seconds]
    },
      (err) => { if (err) console.log(err) })

    await currentWeb3Provider.send({
      id: 0,
      jsonrpc: '2.0',
      method: 'evm_mine'
    },
      (err) => { if (err) console.log(err) })
  }

  static async getLatestBlockTimestamp(web3Instance) {
    const blockNumber = await web3Instance.eth.getBlockNumber()
    const block = await web3Instance.eth.getBlock(blockNumber)

    return block.timestamp
  }

  static async getTimestampFromTx(tx, web3Instance) {
    return this.getTimestampFromTxReceipt(tx.receipt, web3Instance)
  }

  static async getTimestampFromTxReceipt(txReceipt, web3Instance) {
    const block = await web3Instance.eth.getBlock(txReceipt.blockNumber)
    return block.timestamp
  }

  static secondsToDays(seconds) {
    return Number(seconds) / (60 * 60 * 24)
  }

  static daysToSeconds(days) {
    return Number(days) * (60 * 60 * 24)
  }

  // --- Assert functions ---

  static async assertRevert(txPromise, message = undefined) {
    try {
      const tx = await txPromise
      // console.log("tx succeeded")
      assert.isFalse(tx.receipt.status) // when this assert fails, the expected revert didn't occur, i.e. the tx succeeded
    } catch (err) {
      console.log("tx failed: ", err.message)
      assert.include(err.message, "revert")
      // TODO !!!

      // if (message) {
      //   assert.include(err.message, message)
      // }
    }
  }

  static async assertAssert(txPromise) {
    try {
      const tx = await txPromise
      assert.isFalse(tx.receipt.status) // when this assert fails, the expected revert didn't occur, i.e. the tx succeeded
    } catch (err) {
      assert.include(err.message, "invalid opcode")
    }
  }

  // --- Misc. functions  ---

  static hexToParam(hexValue) {
    return ('0'.repeat(64) + hexValue.slice(2)).slice(-64)
  }

  static formatParam(param) {
    let formattedParam = param
    if (typeof param == 'number' || typeof param == 'object' ||
        (typeof param == 'string' && (new RegExp('[0-9]*')).test(param))) {
      formattedParam = web3.utils.toHex(formattedParam)
    } else if (typeof param == 'boolean') {
      formattedParam = param ? '0x01' : '0x00'
    } else if (param.slice(0, 2) != '0x') {
      formattedParam = web3.utils.asciiToHex(formattedParam)
    }

    return this.hexToParam(formattedParam)
  }
  static getTransactionData(signatureString, params) {
    /*
     console.log('signatureString: ', signatureString)
     console.log('params: ', params)
     console.log('params: ', params.map(p => typeof p))
     */
    return web3.utils.sha3(signatureString).slice(0,10) +
      params.reduce((acc, p) => acc + this.formatParam(p), '')
  }

  static async fillAccountsWithWstETH(contracts, accounts) {
    for (const account of accounts) {
      await contracts.wstETHTokenMock.mint(account, "1000000000000000000000000000000000000")
    }
  }
}

TestHelper.ZERO_ADDRESS = '0x' + '0'.repeat(40)
TestHelper.maxBytes32 = '0x' + 'f'.repeat(64)
TestHelper._100pct = '1000000000000000000'
TestHelper.latestRandomSeed = 31337

module.exports = {
  TestHelper,
  MoneyValues,
  TimeValues
}
