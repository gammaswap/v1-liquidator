import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

const UniswapV2FactoryJSON = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairJSON = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const TestCPMMMathJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/libraries/TestCPMMMath.sol/TestCPMMMath.json");
const TestERC20WithFeeJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/TestERC20WithFee.sol/TestERC20WithFee.json");
const TestGammaPoolFactoryJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/TestGammaPoolFactory.sol/TestGammaPoolFactory.json");
const TestCPMMLiquidationStrategyJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/strategies/cpmm/TestCPMMLiquidationStrategy.sol/TestCPMMLiquidationStrategy.json");
const TestCPMMLiquidationStrategyWithLPJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/strategies/cpmm/TestCPMMLiquidationWithLPStrategy.sol/TestCPMMLiquidationWithLPStrategy.json");

describe("CPMMLiquidationStrategy", function () {
  let TestERC20: any;
  let TestCPMMMath: any;
  let TestERC20WithFee: any;
  let TestStrategy: any;
  let TestStrategyWithLP: any;
  let TestGammaPoolFactory: any;
  let UniswapV2Factory: any;
  let UniswapV2Pair: any;
  let tokenA: any;
  let tokenB: any;
  let tokenAFee: any;
  let tokenBFee: any;
  let cfmm: any;
  let cfmmFee: any;
  let uniFactory: any;
  let gsFactory: any;
  let strategy: any;
  let strategyWithLP: any;
  let strategyFee: any;
  let cpmmMath: any;
  let owner: any;
  let addr1: any;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    [owner, addr1] = await ethers.getSigners();
    TestERC20 = await ethers.getContractFactory("TestERC20");
    TestCPMMMath = new ethers.ContractFactory(
        TestCPMMMathJSON.abi,
        TestCPMMMathJSON.bytecode,
        owner
    );
    TestERC20WithFee = new ethers.ContractFactory(
        TestERC20WithFeeJSON.abi,
        TestERC20WithFeeJSON.bytecode,
        owner
    );
    UniswapV2Factory = new ethers.ContractFactory(
      UniswapV2FactoryJSON.abi,
      UniswapV2FactoryJSON.bytecode,
      owner
    );
    UniswapV2Pair = new ethers.ContractFactory(
      UniswapV2PairJSON.abi,
      UniswapV2PairJSON.bytecode,
      owner
    );
    TestGammaPoolFactory = new ethers.ContractFactory(
        TestGammaPoolFactoryJSON.abi,
        TestGammaPoolFactoryJSON.bytecode,
        owner
    );
    TestStrategy = new ethers.ContractFactory(
        TestCPMMLiquidationStrategyJSON.abi,
        TestCPMMLiquidationStrategyJSON.bytecode,
        owner
    );
    TestStrategyWithLP = new ethers.ContractFactory(
        TestCPMMLiquidationStrategyWithLPJSON.abi,
        TestCPMMLiquidationStrategyWithLPJSON.bytecode,
        owner
    );
    tokenA = await TestERC20.deploy("Test Token A", "TOKA");
    tokenB = await TestERC20.deploy("Test Token B", "TOKB");

    uniFactory = await UniswapV2Factory.deploy(owner.address);

    cfmm = await createPair(tokenA, tokenB);
    cpmmMath = await TestCPMMMath.deploy();

    // because Uniswap's CFMM reorders tokenA and tokenB in increasing order
    const token0addr = await cfmm.token0();
    const token1addr = await cfmm.token1();

    tokenA = await TestERC20.attach(
      token0addr // The deployed contract address
    );
    tokenB = await TestERC20.attach(
      token1addr // The deployed contract address
    );

    const ONE = BigNumber.from(10).pow(18);
    const maxTotalApy = ONE.mul(10);
    const baseRate = ONE.div(100);
    const factor = ONE.mul(4).div(100);
    const maxApy = ONE.mul(75).div(100);

    strategy = await TestStrategy.deploy(
      cpmmMath.address,
      maxTotalApy,
      2252571,
      997,
      1000,
      baseRate,
      factor,
      maxApy
    );

    strategyWithLP = await TestStrategyWithLP.deploy(
        cpmmMath.address,
        maxTotalApy,
        2252571,
        997,
        1000,
        baseRate,
        factor,
        maxApy
    );
    // address _feeToSetter, uint16 _fee
    gsFactory = await TestGammaPoolFactory.deploy(owner.address, 10000);

    await (
      await strategy.initialize(
        gsFactory.address,
        cfmm.address,
        [tokenA.address, tokenB.address],
        [18, 18]
      )
    ).wait();

    await (await strategy.setPoolParams(250, 50)).wait();

    await (
        await strategyWithLP.initialize(
            gsFactory.address,
            cfmm.address,
            [tokenA.address, tokenB.address],
            [18, 18]
        )
    ).wait();

    await (await strategyWithLP.setPoolParams(250, 50)).wait();
  });

  async function createStrategy(tok0Fee: any, tok1Fee: any, feePerc: any) {
    const _tokenAFee = await TestERC20WithFee.deploy(
      "Test Token A Fee",
      "TOKAF",
      0
    );
    const _tokenBFee = await TestERC20WithFee.deploy(
      "Test Token B Fee",
      "TOKBF",
      0
    );

    cfmmFee = await createPair(_tokenAFee, _tokenBFee);

    // because Uniswap's CFMM reorders tokenA and tokenB in increasing order
    const token0addr = await cfmmFee.token0();
    const token1addr = await cfmmFee.token1();

    tokenAFee = await TestERC20WithFee.attach(
      token0addr // The deployed contract address
    );

    tokenBFee = await TestERC20WithFee.attach(
      token1addr // The deployed contract address
    );

    const fee = feePerc || BigNumber.from(10).pow(15); // 16
    const ONE = BigNumber.from(10).pow(18);

    if (tok0Fee) {
      await (await tokenAFee.setFee(fee)).wait();
    }

    if (tok1Fee) {
      await (await tokenBFee.setFee(fee)).wait();
    }

    const maxTotalApy = ONE.mul(10);
    const baseRate = ONE.div(100);
    const factor = ONE.mul(4).div(100);
    const maxApy = ONE.mul(75).div(100);

    strategyFee = await TestStrategy.deploy(
      cpmmMath.address,
      maxTotalApy,
      2252571,
      997,
      1000,
      baseRate,
      factor,
      maxApy
    );

    await (
      await strategyFee.initialize(
        gsFactory.address,
        cfmmFee.address,
        [tokenAFee.address, tokenBFee.address],
        [18, 18]
      )
    ).wait();

    await (await strategyFee.setPoolParams(250, 50)).wait();
  }


  async function createStrategyWithLP(tok0Fee: any, tok1Fee: any, feePerc: any) {
    const _tokenAFee = await TestERC20WithFee.deploy(
        "Test Token A Fee",
        "TOKAF",
        0
    );
    const _tokenBFee = await TestERC20WithFee.deploy(
        "Test Token B Fee",
        "TOKBF",
        0
    );

    cfmmFee = await createPair(_tokenAFee, _tokenBFee);

    // because Uniswap's CFMM reorders tokenA and tokenB in increasing order
    const token0addr = await cfmmFee.token0();
    const token1addr = await cfmmFee.token1();

    tokenAFee = await TestERC20WithFee.attach(
        token0addr // The deployed contract address
    );

    tokenBFee = await TestERC20WithFee.attach(
        token1addr // The deployed contract address
    );

    const fee = feePerc || BigNumber.from(10).pow(15); // 16
    const ONE = BigNumber.from(10).pow(18);

    if (tok0Fee) {
      await (await tokenAFee.setFee(fee)).wait();
    }

    if (tok1Fee) {
      await (await tokenBFee.setFee(fee)).wait();
    }

    const maxTotalApy = ONE.mul(10);
    const baseRate = ONE.div(100);
    const factor = ONE.mul(4).div(100);
    const maxApy = ONE.mul(75).div(100);

    strategyFee = await TestStrategyWithLP.deploy(
        cpmmMath.address,
        maxTotalApy,
        2252571,
        997,
        1000,
        baseRate,
        factor,
        maxApy
    );

    await (
        await strategyFee.initialize(
            gsFactory.address,
            cfmmFee.address,
            [tokenAFee.address, tokenBFee.address],
            [18, 18]
        )
    ).wait();

    await (await strategyFee.setPoolParams(250, 50)).wait();
  }

  async function createPair(token1: any, token2: any) {
    await uniFactory.createPair(token1.address, token2.address);
    const uniPairAddress: string = await uniFactory.getPair(
      token1.address,
      token2.address
    );

    return await UniswapV2Pair.attach(
      uniPairAddress // The deployed contract address
    );
  }

  async function setUpStrategyAndCFMM2(tokenId: any, hasFee: any) {
    const ONE = BigNumber.from(10).pow(18);

    if (hasFee) {
      strategy = strategyFee;
      tokenA = tokenAFee;
      tokenB = tokenBFee;
      cfmm = cfmmFee;
    }

    const collateral0 = ONE.mul(2);
    const collateral1 = ONE.mul(1);
    const balance0 = ONE.mul(10);
    const balance1 = ONE.mul(20);

    await (await tokenA.transfer(strategy.address, balance0)).wait();
    await (await tokenB.transfer(strategy.address, balance1)).wait();

    await (
      await strategy.setTokenBalances(
        tokenId,
        collateral0,
        collateral1,
        balance0,
        balance1
      )
    ).wait();

    await (await tokenA.transfer(cfmm.address, ONE.mul(5000))).wait();
    await (await tokenB.transfer(cfmm.address, ONE.mul(10000))).wait();
    await (await cfmm.mint(addr1.address)).wait();

    const rez = await cfmm.getReserves();
    const reserves0 = rez._reserve0;
    const reserves1 = rez._reserve1;

    await (await strategy.setCFMMReserves(reserves0, reserves1, 0)).wait();

    return { res0: reserves0, res1: reserves1 };
  }

  async function setUpStrategyAndCFMM(tokenId: any, hasFee: any) {
    const ONE = BigNumber.from(10).pow(18);

    if (hasFee) {
      strategy = strategyFee;
      tokenA = tokenAFee;
      tokenB = tokenBFee;
      cfmm = cfmmFee;
    }

    const collateral0 = ONE.mul(1);
    const collateral1 = ONE.mul(2);
    const balance0 = ONE.mul(10);
    const balance1 = ONE.mul(20);

    await (await tokenA.transfer(strategy.address, balance0)).wait();
    await (await tokenB.transfer(strategy.address, balance1)).wait();

    await (
      await strategy.setTokenBalances(
        tokenId,
        collateral0,
        collateral1,
        balance0,
        balance1
      )
    ).wait();

    await (await tokenA.transfer(cfmm.address, ONE.mul(5000))).wait();
    await (await tokenB.transfer(cfmm.address, ONE.mul(10000))).wait();
    await (await cfmm.mint(addr1.address)).wait();

    const rez = await cfmm.getReserves();
    const reserves0 = rez._reserve0;
    const reserves1 = rez._reserve1;

    await (await strategy.setCFMMReserves(reserves0, reserves1, 0)).wait();

    return { res0: reserves0, res1: reserves1 };
  }

  async function setUpLoanableLiquidity(tokenId: any, hasFee: any) {
    const ONE = BigNumber.from(10).pow(18);

    if (hasFee) {
      strategy = strategyFee;
      tokenA = tokenAFee;
      tokenB = tokenBFee;
      cfmm = cfmmFee;
    }

    await (await tokenA.transfer(cfmm.address, ONE.mul(5))).wait();
    await (await tokenB.transfer(cfmm.address, ONE.mul(10))).wait();
    await (await cfmm.mint(strategy.address)).wait();

    await (await strategy.depositLPTokens(tokenId)).wait();
  }

  const sqrt = (y: BigNumber): BigNumber => {
    let z = BigNumber.from(0);
    if (y.gt(3)) {
      z = y;
      let x = y.div(2).add(1);
      while (x.lt(z)) {
        z = x;
        x = y.div(x).add(x).div(2);
      }
    } else if (!y.isZero()) {
      z = BigNumber.from(1);
    }
    return z;
  };

  async function getBalanceChanges(
    lpTokensBorrowed: BigNumber,
    feeA: any,
    feeB: any
  ) {
    const rezerves = await cfmmFee.getReserves();
    const cfmmTotalInvariant = sqrt(rezerves._reserve0.mul(rezerves._reserve1));
    const cfmmTotalSupply = await cfmmFee.totalSupply();
    const liquidityBorrowed = lpTokensBorrowed
      .mul(cfmmTotalInvariant)
      .div(cfmmTotalSupply);
    const tokenAChange = lpTokensBorrowed
      .mul(rezerves._reserve0)
      .div(cfmmTotalSupply);
    const tokenBChange = lpTokensBorrowed
      .mul(rezerves._reserve1)
      .div(cfmmTotalSupply);

    const ONE = BigNumber.from(10).pow(18);
    const feeAmt0 = tokenAChange.mul(feeA).div(ONE);
    const feeAmt1 = tokenBChange.mul(feeB).div(ONE);

    return {
      liquidityBorrowed: liquidityBorrowed,
      tokenAChange: tokenAChange.sub(feeAmt0),
      tokenBChange: tokenBChange.sub(feeAmt1),
      cfmmTotalInvariant: cfmmTotalInvariant,
      cfmmTotalSupply: cfmmTotalSupply,
      cfmmReserve0: rezerves._reserve0,
      cfmmReserve1: rezerves._reserve1,
    };
  }

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    it("Check Init Params", async function () {
      expect(await strategy.tradingFee1()).to.equal(997);
      expect(await strategy.tradingFee2()).to.equal(1000);
      const ONE = BigNumber.from(10).pow(18);
      const baseRate = ONE.div(100);
      const factor = ONE.mul(4).div(100);
      const maxApy = ONE.mul(75).div(100);
      expect(await strategy.liquidationFee()).to.equal(250);
      expect(await strategy.ltvThreshold()).to.equal(9500);
      expect(await strategy.baseRate()).to.equal(baseRate);
      expect(await strategy.factor()).to.equal(factor);
      expect(await strategy.maxApy()).to.equal(maxApy);
      expect(await strategy.BLOCKS_PER_YEAR()).to.equal(2252571);
      expect(await strategy.MAX_TOTAL_APY()).to.equal(ONE.mul(10));
    });
  });

  describe("Liquidate Loans", function () {
    it("Liquidate with collateral, no write down", async function () {
      await createStrategy(false, false, null);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(1);
      const tokensHeld1 = ONE.mul(2);

      await setUpStrategyAndCFMM(tokenId, true);
      await setUpLoanableLiquidity(tokenId, true);

      const loan0 = await strategyFee.getLoan(tokenId);
      expect(loan0.initLiquidity).to.equal(0);
      expect(loan0.liquidity).to.equal(0);
      expect(loan0.lpTokens).to.equal(0);
      expect(loan0.tokensHeld.length).to.equal(2);
      expect(loan0.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan0.tokensHeld[1]).to.equal(tokensHeld1);

      const lpTokensBorrowed = ONE;
      const res = await getBalanceChanges(lpTokensBorrowed, 0, 0);
      const bal0 = await strategyFee.getPoolData();
      expect(bal0.lpTokenBalance).gt(0);
      expect(bal0.lpTokenBorrowed).to.equal(0);
      expect(bal0.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal0.borrowedInvariant).to.equal(0);
      expect(bal0.lpInvariant).gt(0);
      expect(bal0.lastCFMMInvariant).gt(0);
      expect(bal0.lastCFMMTotalSupply).gt(0);
      expect(bal0.tokenBalance.length).to.equal(2);
      expect(bal0.tokenBalance[0]).to.equal(ONE.mul(10));
      expect(bal0.tokenBalance[1]).to.equal(ONE.mul(20));

      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      // Pool balances changes after borrowing liquidity
      const bal1 = await strategyFee.getPoolData();

      expect(bal1.borrowedInvariant).gt(bal0.borrowedInvariant);
      expect(bal1.borrowedInvariant).to.equal(
        bal0.borrowedInvariant.add(loan1.liquidity)
      );
      expect(bal1.lpTokenBorrowedPlusInterest).to.equal(
        bal0.lpTokenBorrowedPlusInterest.add(lpTokensBorrowed)
      );
      expect(bal1.lpTokenBorrowed).to.equal(
        bal0.lpTokenBorrowed.add(lpTokensBorrowed)
      );
      expect(bal1.lpInvariant).to.equal(bal0.lpInvariant.sub(loan1.liquidity));
      expect(bal1.lpTokenBalance).to.equal(
        bal0.lpTokenBalance.sub(lpTokensBorrowed)
      );
      expect(bal1.tokenBalance[0]).to.equal(
        bal0.tokenBalance[0].add(res.tokenAChange)
      );
      expect(bal1.tokenBalance[1]).to.equal(
        bal0.tokenBalance[1].add(res.tokenBChange)
      );
      // expect(bal1.lastCFMMTotalSupply).to.equal(
      //   bal0.lastCFMMTotalSupply.sub(lpTokensBorrowed)
      // );
      // expect(bal1.lastCFMMInvariant).to.equal(
      //   bal0.lastCFMMInvariant.sub(loan1.liquidity)
      // );

      // about a month and a half 0x4CFE0, 0x4BAF0
      await ethers.provider.send("hardhat_mine", ["0x493E0"]);

      await (await strategyFee.updateLoanData(tokenId)).wait();

      // Pool balances changes after rate upate
      const bal2 = await strategyFee.getPoolData();
      const loan2 = await strategyFee.getLoan(tokenId);
      expect(bal2.borrowedInvariant).gt(bal1.borrowedInvariant);
      expect(bal2.lpTokenBorrowedPlusInterest).gt(
        bal1.lpTokenBorrowedPlusInterest
      );
      expect(bal2.lpTokenBorrowed).to.equal(bal1.lpTokenBorrowed);
      expect(bal2.lpInvariant).to.equal(bal1.lpInvariant);
      expect(bal2.lpTokenBalance).to.equal(bal1.lpTokenBalance);
      expect(bal2.tokenBalance[0]).to.equal(bal1.tokenBalance[0]);
      expect(bal2.tokenBalance[1]).to.equal(bal1.tokenBalance[1]);
      // expect(bal2.lastCFMMTotalSupply).to.equal(bal1.lastCFMMTotalSupply);
      // expect(bal2.lastCFMMInvariant).to.equal(bal1.lastCFMMInvariant.add(1)); // add 1 because loss of precision

      const collateral = sqrt(loan2.tokensHeld[0].mul(loan2.tokensHeld[1]));
      expect(loan2.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan2.liquidity).gt(res.liquidityBorrowed);
      expect(loan2.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));
      expect(
        await strategyFee.canLiquidate(loan2.liquidity, collateral)
      ).to.equal(true);

      const token0bal0 = await tokenAFee.balanceOf(owner.address);
      const token1bal0 = await tokenBFee.balanceOf(owner.address);
      const cfmmBalance0 = await cfmm.balanceOf(owner.address);

      const resp = await (await strategyFee._liquidate(tokenId)).wait();

      const len = resp.events.length;
      const liquidationEvent = resp.events[len - 3];
      expect(liquidationEvent.event).to.equal("Liquidation");
      expect(liquidationEvent.args.writeDownAmt).to.equal(0);
      expect(liquidationEvent.args.tokenId).to.equal(tokenId);
      expect(liquidationEvent.args.liquidity.div(ONE.div(10000))).to.equal(
        loan2.liquidity.div(ONE.div(10000))
      );
      expect(liquidationEvent.args.collateral).to.equal(collateral);
      expect(liquidationEvent.args.txType).to.equal(11);

      const loanUpdateEvent = resp.events[len - 2];
      expect(loanUpdateEvent.event).to.equal("LoanUpdated");
      expect(loanUpdateEvent.args.tokenId).to.equal(tokenId);
      expect(loanUpdateEvent.args.tokensHeld.length).to.equal(2);
      expect(loanUpdateEvent.args.tokensHeld[0]).to.lt(loan2.tokensHeld[0]);
      expect(loanUpdateEvent.args.tokensHeld[1]).to.lt(loan2.tokensHeld[1]);
      expect(loanUpdateEvent.args.liquidity).to.equal(0);
      expect(loanUpdateEvent.args.initLiquidity).to.equal(0);
      expect(loanUpdateEvent.args.lpTokens).to.equal(0);
      expect(loanUpdateEvent.args.rateIndex).to.equal(0);
      expect(loanUpdateEvent.args.txType).to.equal(11);

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.rateIndex).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).to.equal(loanUpdateEvent.args.tokensHeld[0]);
      expect(loan3.tokensHeld[1]).to.equal(loanUpdateEvent.args.tokensHeld[1]);

      const cfmmBalance1 = await cfmm.balanceOf(owner.address);
      expect(cfmmBalance1).gt(cfmmBalance0);

      const token0bal1 = await tokenAFee.balanceOf(owner.address);
      const token1bal1 = await tokenBFee.balanceOf(owner.address);
      expect(token0bal1).eq(token0bal0);
      expect(token1bal1).eq(token1bal0);

      // Pool balances changes after rate upate
      const bal3 = await strategyFee.getPoolData();
      expect(bal3.borrowedInvariant).to.equal(0);
      expect(bal3.borrowedInvariant).lt(bal2.borrowedInvariant);
      expect(bal3.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal3.lpTokenBorrowedPlusInterest).lt(
        bal2.lpTokenBorrowedPlusInterest
      );
      expect(bal3.lpTokenBorrowed).to.equal(0);
      expect(bal3.lpTokenBorrowed).to.equal(bal0.lpTokenBorrowed);
      expect(bal3.lpTokenBorrowed).lt(bal2.lpTokenBorrowed);
      expect(bal3.lpInvariant).gt(bal0.lpInvariant);
      expect(bal3.lpInvariant).gt(bal1.lpInvariant);
      expect(bal3.lpInvariant).gt(bal2.lpInvariant);
      expect(bal3.lpTokenBalance).gt(bal0.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal1.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal2.lpTokenBalance);
      expect(bal3.tokenBalance[0]).lt(bal2.tokenBalance[0]);
      expect(bal3.tokenBalance[1]).lt(bal2.tokenBalance[1]);
      expect(bal3.tokenBalance[0]).to.equal(
        bal2.tokenBalance[0].sub(loan2.tokensHeld[0].sub(loan3.tokensHeld[0]))
      );
      expect(bal3.tokenBalance[1]).to.equal(
        bal2.tokenBalance[1].sub(loan2.tokensHeld[1].sub(loan3.tokensHeld[1]))
      );
      // expect(bal3.lastCFMMTotalSupply).gt(bal0.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMTotalSupply).gt(bal1.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMTotalSupply).gt(bal2.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMInvariant).gt(bal0.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).gt(bal1.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).gt(bal2.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).to.equal(
      //   bal2.lastCFMMInvariant.add(liquidationEvent.args.liquidity).add(1)
      // );

      const poolUpdateEvent = resp.events[len - 1];
      expect(poolUpdateEvent.event).to.equal("PoolUpdated");
      expect(poolUpdateEvent.args.lpTokenBalance).to.equal(bal3.lpTokenBalance);
      expect(poolUpdateEvent.args.lpTokenBorrowed).to.equal(
        bal3.lpTokenBorrowed
      );
      expect(poolUpdateEvent.args.lastBlockNumber).to.equal(
        bal3.lastBlockNumber
      );
      expect(poolUpdateEvent.args.accFeeIndex).to.equal(bal3.accFeeIndex);
      expect(poolUpdateEvent.args.lpTokenBorrowedPlusInterest).to.equal(
        bal3.lpTokenBorrowedPlusInterest
      );
      expect(poolUpdateEvent.args.lpInvariant).to.equal(bal3.lpInvariant);
      expect(poolUpdateEvent.args.borrowedInvariant).to.equal(
        bal3.borrowedInvariant
      );
      expect(poolUpdateEvent.args.txType).to.equal(11);
    });

    it("Liquidate with collateral, write down", async function () {
      await createStrategy(false, false, null);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(1);
      const tokensHeld1 = ONE.mul(2);

      await setUpStrategyAndCFMM(tokenId, true);
      await setUpLoanableLiquidity(tokenId, true);

      const loan0 = await strategyFee.getLoan(tokenId);
      expect(loan0.initLiquidity).to.equal(0);
      expect(loan0.liquidity).to.equal(0);
      expect(loan0.lpTokens).to.equal(0);
      expect(loan0.tokensHeld.length).to.equal(2);
      expect(loan0.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan0.tokensHeld[1]).to.equal(tokensHeld1);

      const lpTokensBorrowed = ONE;
      const res = await getBalanceChanges(lpTokensBorrowed, 0, 0);
      const bal0 = await strategyFee.getPoolData();
      expect(bal0.lpTokenBalance).gt(0);
      expect(bal0.lpTokenBorrowed).to.equal(0);
      expect(bal0.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal0.borrowedInvariant).to.equal(0);
      expect(bal0.lpInvariant).gt(0);
      expect(bal0.lastCFMMInvariant).gt(0);
      expect(bal0.lastCFMMTotalSupply).gt(0);
      expect(bal0.tokenBalance.length).to.equal(2);
      expect(bal0.tokenBalance[0]).to.equal(ONE.mul(10));
      expect(bal0.tokenBalance[1]).to.equal(ONE.mul(20));

      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      // Pool balances changes after borrowing liquidity
      const bal1 = await strategyFee.getPoolData();

      expect(bal1.borrowedInvariant).gt(bal0.borrowedInvariant);
      expect(bal1.borrowedInvariant).to.equal(
        bal0.borrowedInvariant.add(loan1.liquidity)
      );
      expect(bal1.lpTokenBorrowedPlusInterest).to.equal(
        bal0.lpTokenBorrowedPlusInterest.add(lpTokensBorrowed)
      );
      expect(bal1.lpTokenBorrowed).to.equal(
        bal0.lpTokenBorrowed.add(lpTokensBorrowed)
      );
      expect(bal1.lpInvariant).to.equal(bal0.lpInvariant.sub(loan1.liquidity));
      expect(bal1.lpTokenBalance).to.equal(
        bal0.lpTokenBalance.sub(lpTokensBorrowed)
      );
      expect(bal1.tokenBalance[0]).to.equal(
        bal0.tokenBalance[0].add(res.tokenAChange)
      );
      expect(bal1.tokenBalance[1]).to.equal(
        bal0.tokenBalance[1].add(res.tokenBChange)
      );
      // expect(bal1.lastCFMMTotalSupply).to.equal(
      //   bal0.lastCFMMTotalSupply.sub(lpTokensBorrowed)
      // );
      // expect(bal1.lastCFMMInvariant).to.equal(
      //   bal0.lastCFMMInvariant.sub(loan1.liquidity)
      // );

      // about a month and a half
      await ethers.provider.send("hardhat_mine", ["0x4CFE0"]);

      await (await strategyFee.updateLoanData(tokenId)).wait();

      // Pool balances changes after rate upate
      const bal2 = await strategyFee.getPoolData();
      const loan2 = await strategyFee.getLoan(tokenId);
      expect(bal2.borrowedInvariant).gt(bal1.borrowedInvariant);
      expect(bal2.lpTokenBorrowedPlusInterest).gt(
        bal1.lpTokenBorrowedPlusInterest
      );
      expect(bal2.lpTokenBorrowed).to.equal(bal1.lpTokenBorrowed);
      expect(bal2.lpInvariant).to.equal(bal1.lpInvariant);
      expect(bal2.lpTokenBalance).to.equal(bal1.lpTokenBalance);
      expect(bal2.tokenBalance[0]).to.equal(bal1.tokenBalance[0]);
      expect(bal2.tokenBalance[1]).to.equal(bal1.tokenBalance[1]);
      // expect(bal2.lastCFMMTotalSupply).to.equal(bal1.lastCFMMTotalSupply);
      // expect(bal2.lastCFMMInvariant).to.equal(bal1.lastCFMMInvariant.add(1)); // add 1 because loss of precision

      const collateral = sqrt(loan2.tokensHeld[0].mul(loan2.tokensHeld[1]));
      expect(loan2.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan2.liquidity).gt(res.liquidityBorrowed);
      expect(loan2.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));
      expect(
        await strategyFee.canLiquidate(loan2.liquidity, collateral)
      ).to.equal(true);

      const token0bal0 = await tokenAFee.balanceOf(owner.address);
      const token1bal0 = await tokenBFee.balanceOf(owner.address);
      const cfmmBalance0 = await cfmm.balanceOf(owner.address);

      const resp = await (await strategyFee._liquidate(tokenId)).wait();
      const writeDownAmt = BigNumber.from("46157136933282181");
      const len = resp.events.length;
      const liquidationEvent = resp.events[len - 3]; // 46157136933282181
      expect(liquidationEvent.event).to.equal("Liquidation");
      expect(liquidationEvent.args.writeDownAmt).to.equal(writeDownAmt);
      expect(liquidationEvent.args.tokenId).to.equal(tokenId);
      expect(liquidationEvent.args.liquidity.div(ONE.div(10000))).to.equal(
        loan2.liquidity.sub(writeDownAmt).div(ONE.div(10000))
      );
      expect(liquidationEvent.args.collateral).to.equal(collateral);
      expect(liquidationEvent.args.txType).to.equal(11);

      const loanUpdateEvent = resp.events[len - 2];
      expect(loanUpdateEvent.event).to.equal("LoanUpdated");
      expect(loanUpdateEvent.args.tokenId).to.equal(tokenId);
      expect(loanUpdateEvent.args.tokensHeld.length).to.equal(2);
      expect(loanUpdateEvent.args.tokensHeld[0]).to.equal(1);
      expect(loanUpdateEvent.args.tokensHeld[1]).to.equal(1);
      expect(loanUpdateEvent.args.liquidity).to.equal(0);
      expect(loanUpdateEvent.args.initLiquidity).to.equal(0);
      expect(loanUpdateEvent.args.lpTokens).to.equal(0);
      expect(loanUpdateEvent.args.rateIndex).to.equal(0);
      expect(loanUpdateEvent.args.txType).to.equal(11);

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.rateIndex).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).to.equal(1);
      expect(loan3.tokensHeld[1]).to.equal(1);

      const token0bal1 = await tokenAFee.balanceOf(owner.address);
      const token1bal1 = await tokenBFee.balanceOf(owner.address);
      const cfmmBalance1 = await cfmm.balanceOf(owner.address);
      expect(token0bal1).eq(token0bal0);
      expect(token1bal1).eq(token1bal0);
      expect(cfmmBalance1).gt(cfmmBalance0);

      // Pool balances changes after rate upate
      const bal3 = await strategyFee.getPoolData();
      expect(bal3.borrowedInvariant).to.equal(0);
      expect(bal3.borrowedInvariant).lt(bal2.borrowedInvariant);
      expect(
        bal2.borrowedInvariant.sub(writeDownAmt).div(ONE.div(10000))
      ).to.equal(liquidationEvent.args.liquidity.div(ONE.div(10000)));
      expect(bal3.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal3.lpTokenBorrowedPlusInterest).lt(
        bal2.lpTokenBorrowedPlusInterest
      );
      expect(bal3.lpTokenBorrowed).to.equal(0);
      expect(bal3.lpTokenBorrowed).to.equal(bal0.lpTokenBorrowed);
      expect(bal3.lpTokenBorrowed).lt(bal2.lpTokenBorrowed);
      expect(bal3.lpInvariant).gt(bal0.lpInvariant);
      expect(bal3.lpInvariant).gt(bal1.lpInvariant);
      expect(bal3.lpInvariant).gt(bal2.lpInvariant);
      expect(bal3.lpTokenBalance).gt(bal0.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal1.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal2.lpTokenBalance);
      expect(bal3.tokenBalance[0]).lt(bal2.tokenBalance[0]);
      expect(bal3.tokenBalance[1]).lt(bal2.tokenBalance[1]);
      expect(bal3.tokenBalance[0]).to.equal(
        bal2.tokenBalance[0].sub(loan2.tokensHeld[0].sub(loan3.tokensHeld[0]))
      );
      expect(bal3.tokenBalance[1]).to.equal(
        bal2.tokenBalance[1].sub(loan2.tokensHeld[1].sub(loan3.tokensHeld[1]))
      );
      // expect(bal3.lastCFMMTotalSupply).gt(bal0.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMTotalSupply).gt(bal1.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMTotalSupply).gt(bal2.lastCFMMTotalSupply);
      // expect(bal3.lastCFMMInvariant).gt(bal0.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).gt(bal1.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).gt(bal2.lastCFMMInvariant);
      // expect(bal3.lastCFMMInvariant).to.equal(
      //   bal2.lastCFMMInvariant.add(liquidationEvent.args.liquidity).add(1)
      // );

      const poolUpdateEvent = resp.events[len - 1];
      expect(poolUpdateEvent.event).to.equal("PoolUpdated");
      expect(poolUpdateEvent.args.lpTokenBalance).to.equal(bal3.lpTokenBalance);
      expect(poolUpdateEvent.args.lpTokenBorrowed).to.equal(
        bal3.lpTokenBorrowed
      );
      expect(poolUpdateEvent.args.lastBlockNumber).to.equal(
        bal3.lastBlockNumber
      );
      expect(poolUpdateEvent.args.accFeeIndex).to.equal(bal3.accFeeIndex);
      expect(poolUpdateEvent.args.lpTokenBorrowedPlusInterest).to.equal(
        bal3.lpTokenBorrowedPlusInterest
      );
      expect(poolUpdateEvent.args.lpInvariant).to.equal(bal3.lpInvariant);
      expect(poolUpdateEvent.args.borrowedInvariant).to.equal(
        bal3.borrowedInvariant
      );
      expect(poolUpdateEvent.args.txType).to.equal(11);
    });

    it("Liquidate with collateral, swap", async function () {
      await createStrategy(false, false, null);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(2);
      const tokensHeld1 = ONE.mul(1);

      await setUpStrategyAndCFMM2(tokenId, true);
      await setUpLoanableLiquidity(tokenId, true);

      const loan0 = await strategyFee.getLoan(tokenId);
      expect(loan0.initLiquidity).to.equal(0);
      expect(loan0.liquidity).to.equal(0);
      expect(loan0.lpTokens).to.equal(0);
      expect(loan0.tokensHeld.length).to.equal(2);
      expect(loan0.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan0.tokensHeld[1]).to.equal(tokensHeld1);

      const lpTokensBorrowed = ONE;
      const res = await getBalanceChanges(lpTokensBorrowed, 0, 0);
      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      // about a month and a half
      await ethers.provider.send("hardhat_mine", ["0x53688"]);

      await (await strategyFee.updateLoanData(tokenId)).wait();

      const loan2 = await strategyFee.getLoan(tokenId);
      const collateral = sqrt(loan2.tokensHeld[0].mul(loan2.tokensHeld[1]));
      expect(loan2.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan2.liquidity).gt(res.liquidityBorrowed);
      expect(loan2.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(loan1.tokensHeld[0]);
      expect(loan2.tokensHeld[1]).to.equal(loan1.tokensHeld[1]);
      expect(
        await strategyFee.canLiquidate(loan2.liquidity, collateral)
      ).to.equal(true);

      const token0bal0 = await tokenAFee.balanceOf(owner.address);
      const token1bal0 = await tokenBFee.balanceOf(owner.address);

      const payLiquidity = loan2.liquidity;
      const tokenArepay = payLiquidity
        .mul(res.cfmmReserve0)
        .div(res.cfmmTotalInvariant);
      const tokenBrepay = payLiquidity
        .mul(res.cfmmReserve1)
        .div(res.cfmmTotalInvariant);

      const token0Change = tokenArepay.gt(loan2.tokensHeld[0])
        ? tokenArepay.sub(loan2.tokensHeld[0])
        : 0;
      const token1Change = tokenBrepay.gt(loan2.tokensHeld[1]) // We actually need less than this because there's a writeDown
        ? tokenBrepay.sub(loan2.tokensHeld[1])
        : 0;

      const cfmmBalance0 = await cfmm.balanceOf(owner.address);

      await (await strategyFee._liquidate(tokenId)).wait();

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(loan2.tokensHeld[0]);
      expect(loan3.tokensHeld[1]).lt(loan2.tokensHeld[1]);

      const cfmmBalance1 = await cfmm.balanceOf(owner.address);
      const token0bal1 = await tokenAFee.balanceOf(owner.address);
      const token1bal1 = await tokenBFee.balanceOf(owner.address);
      expect(token0bal1).eq(token0bal0);
      expect(token1bal1).eq(token1bal0);
      expect(cfmmBalance1).gt(cfmmBalance0);
    });

    it("Liquidate with LP Token, no write down", async function () {
      await createStrategyWithLP(false, false, null);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(1);
      const tokensHeld1 = ONE.mul(2);

      await setUpStrategyAndCFMM(tokenId, true);
      await setUpLoanableLiquidity(tokenId, true);

      const loan0 = await strategyFee.getLoan(tokenId);
      expect(loan0.initLiquidity).to.equal(0);
      expect(loan0.liquidity).to.equal(0);
      expect(loan0.lpTokens).to.equal(0);
      expect(loan0.tokensHeld.length).to.equal(2);
      expect(loan0.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan0.tokensHeld[1]).to.equal(tokensHeld1);

      const lpTokensBorrowed = ONE;
      const res = await getBalanceChanges(lpTokensBorrowed, 0, 0);
      const bal0 = await strategyFee.getPoolData();
      expect(bal0.lpTokenBalance).gt(0);
      expect(bal0.lpTokenBorrowed).to.equal(0);
      expect(bal0.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal0.borrowedInvariant).to.equal(0);
      expect(bal0.lpInvariant).gt(0);
      expect(bal0.lastCFMMInvariant).gt(0);
      expect(bal0.lastCFMMTotalSupply).gt(0);
      expect(bal0.tokenBalance.length).to.equal(2);
      expect(bal0.tokenBalance[0]).to.equal(ONE.mul(10));
      expect(bal0.tokenBalance[1]).to.equal(ONE.mul(20));

      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      // Pool balances changes after borrowing liquidity
      const bal1 = await strategyFee.getPoolData();

      expect(bal1.borrowedInvariant).gt(bal0.borrowedInvariant);
      expect(bal1.borrowedInvariant).to.equal(
        bal0.borrowedInvariant.add(loan1.liquidity)
      );
      expect(bal1.lpTokenBorrowedPlusInterest).to.equal(
        bal0.lpTokenBorrowedPlusInterest.add(lpTokensBorrowed)
      );
      expect(bal1.lpTokenBorrowed).to.equal(
        bal0.lpTokenBorrowed.add(lpTokensBorrowed)
      );
      expect(bal1.lpInvariant).to.equal(bal0.lpInvariant.sub(loan1.liquidity));
      expect(bal1.lpTokenBalance).to.equal(
        bal0.lpTokenBalance.sub(lpTokensBorrowed)
      );
      expect(bal1.tokenBalance[0]).to.equal(
        bal0.tokenBalance[0].add(res.tokenAChange)
      );
      expect(bal1.tokenBalance[1]).to.equal(
        bal0.tokenBalance[1].add(res.tokenBChange)
      );
      // expect(bal1.lastCFMMTotalSupply).to.equal(
      //   bal0.lastCFMMTotalSupply.sub(lpTokensBorrowed)
      // );
      // expect(bal1.lastCFMMInvariant).to.equal(
      //   bal0.lastCFMMInvariant.sub(loan1.liquidity)
      // );

      // about a month and a half 0x4CFE0, 0x4BAF0
      await ethers.provider.send("hardhat_mine", ["0x493E0"]);

      await (await strategyFee.updateLoanData(tokenId)).wait();

      // Pool balances changes after rate upate
      const bal2 = await strategyFee.getPoolData();
      const loan2 = await strategyFee.getLoan(tokenId);
      expect(bal2.borrowedInvariant).gt(bal1.borrowedInvariant);
      expect(bal2.lpTokenBorrowedPlusInterest).gt(
        bal1.lpTokenBorrowedPlusInterest
      );
      expect(bal2.lpTokenBorrowed).to.equal(bal1.lpTokenBorrowed);
      expect(bal2.lpInvariant).to.equal(bal1.lpInvariant);
      expect(bal2.lpTokenBalance).to.equal(bal1.lpTokenBalance);
      expect(bal2.tokenBalance[0]).to.equal(bal1.tokenBalance[0]);
      expect(bal2.tokenBalance[1]).to.equal(bal1.tokenBalance[1]);
      // expect(bal2.lastCFMMTotalSupply).to.equal(bal1.lastCFMMTotalSupply);
      // expect(bal2.lastCFMMInvariant).to.equal(bal1.lastCFMMInvariant.add(1)); // add 1 because loss of precision

      const collateral = sqrt(loan2.tokensHeld[0].mul(loan2.tokensHeld[1]));
      expect(loan2.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan2.liquidity).gt(res.liquidityBorrowed);
      expect(loan2.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));
      expect(
        await strategyFee.canLiquidate(loan2.liquidity, collateral)
      ).to.equal(true);

      await (await tokenA.transfer(cfmm.address, ONE.mul(50))).wait();
      await (await tokenB.transfer(cfmm.address, ONE.mul(100))).wait();
      await (await cfmm.mint(strategyFee.address)).wait();

      const addedLiquidityToCFMM = sqrt(ONE.mul(50).mul(ONE.mul(100)));
      const token0bal0 = await tokenAFee.balanceOf(owner.address);
      const token1bal0 = await tokenBFee.balanceOf(owner.address);

      const resp = await (await strategyFee._liquidateWithLP(tokenId)).wait();

      const len = resp.events.length;
      const liquidationEvent = resp.events[len - 3];
      expect(liquidationEvent.event).to.equal("Liquidation");
      expect(liquidationEvent.args.writeDownAmt).to.equal(0);
      expect(liquidationEvent.args.tokenId).to.equal(tokenId);
      expect(liquidationEvent.args.liquidity.div(ONE.div(10000))).to.equal(
        loan2.liquidity.div(ONE.div(10000))
      );
      expect(liquidationEvent.args.collateral).to.equal(collateral);
      expect(liquidationEvent.args.txType).to.equal(12);

      const loanUpdateEvent = resp.events[len - 2];
      expect(loanUpdateEvent.event).to.equal("LoanUpdated");
      expect(loanUpdateEvent.args.tokenId).to.equal(tokenId);
      expect(loanUpdateEvent.args.tokensHeld.length).to.equal(2);
      expect(loanUpdateEvent.args.tokensHeld[0]).lt(loan2.tokensHeld[0]);
      expect(loanUpdateEvent.args.tokensHeld[1]).lt(loan2.tokensHeld[1]);
      expect(loanUpdateEvent.args.liquidity).to.equal(0);
      expect(loanUpdateEvent.args.initLiquidity).to.equal(0);
      expect(loanUpdateEvent.args.lpTokens).to.equal(0);
      expect(loanUpdateEvent.args.rateIndex).to.equal(0);
      expect(loanUpdateEvent.args.txType).to.equal(12);

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.rateIndex).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(loan2.tokensHeld[0]);
      expect(loan3.tokensHeld[1]).lt(loan2.tokensHeld[1]);

      const token0bal1 = await tokenAFee.balanceOf(owner.address);
      const token1bal1 = await tokenBFee.balanceOf(owner.address);
      expect(token0bal1).gt(token0bal0);
      expect(token1bal1).gt(token1bal0);

      // Pool balances changes after rate upate
      const bal3 = await strategyFee.getPoolData();
      expect(bal3.borrowedInvariant).to.equal(0);
      expect(bal3.borrowedInvariant).lt(bal2.borrowedInvariant);
      expect(bal3.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal3.lpTokenBorrowedPlusInterest).lt(
        bal2.lpTokenBorrowedPlusInterest
      );
      expect(bal3.lpTokenBorrowed).to.equal(0);
      expect(bal3.lpTokenBorrowed).to.equal(bal0.lpTokenBorrowed);
      expect(bal3.lpTokenBorrowed).lt(bal2.lpTokenBorrowed);
      expect(bal3.lpInvariant).gt(bal0.lpInvariant);
      expect(bal3.lpInvariant).gt(bal1.lpInvariant);
      expect(bal3.lpInvariant).gt(bal2.lpInvariant);
      expect(bal3.lpTokenBalance).gt(bal0.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal1.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal2.lpTokenBalance);
      expect(bal3.tokenBalance[0]).lt(bal2.tokenBalance[0]);
      expect(bal3.tokenBalance[1]).lt(bal2.tokenBalance[1]);
      expect(bal3.tokenBalance[0]).to.equal(
        bal2.tokenBalance[0].sub(loan2.tokensHeld[0].sub(loan3.tokensHeld[0]))
      );
      expect(bal3.tokenBalance[1]).to.equal(
        bal2.tokenBalance[1].sub(loan2.tokensHeld[1].sub(loan3.tokensHeld[1]))
      );
      expect(bal3.lastCFMMTotalSupply).gt(bal0.lastCFMMTotalSupply);
      expect(bal3.lastCFMMTotalSupply).gt(bal1.lastCFMMTotalSupply);
      expect(bal3.lastCFMMTotalSupply).gt(bal2.lastCFMMTotalSupply);
      expect(bal3.lastCFMMInvariant).gt(bal0.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).gt(bal1.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).gt(bal2.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).to.equal(
        bal2.lastCFMMInvariant.add(addedLiquidityToCFMM)
      );

      const poolUpdateEvent = resp.events[len - 1];
      expect(poolUpdateEvent.event).to.equal("PoolUpdated");
      expect(poolUpdateEvent.args.lpTokenBalance).to.equal(bal3.lpTokenBalance);
      expect(poolUpdateEvent.args.lpTokenBorrowed).to.equal(
        bal3.lpTokenBorrowed
      );
      expect(poolUpdateEvent.args.lastBlockNumber).to.equal(
        bal3.lastBlockNumber
      );
      expect(poolUpdateEvent.args.accFeeIndex).to.equal(bal3.accFeeIndex);
      expect(poolUpdateEvent.args.lpTokenBorrowedPlusInterest).to.equal(
        bal3.lpTokenBorrowedPlusInterest
      );
      expect(poolUpdateEvent.args.lpInvariant).to.equal(bal3.lpInvariant);
      expect(poolUpdateEvent.args.borrowedInvariant).to.equal(
        bal3.borrowedInvariant
      );
      expect(poolUpdateEvent.args.txType).to.equal(12);
    });

    it("Liquidate with LP Token, write down", async function () {
      await createStrategyWithLP(false, false, null);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(1);
      const tokensHeld1 = ONE.mul(2);

      await setUpStrategyAndCFMM(tokenId, true);
      await setUpLoanableLiquidity(tokenId, true);

      const loan0 = await strategyFee.getLoan(tokenId);
      expect(loan0.initLiquidity).to.equal(0);
      expect(loan0.liquidity).to.equal(0);
      expect(loan0.lpTokens).to.equal(0);
      expect(loan0.tokensHeld.length).to.equal(2);
      expect(loan0.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan0.tokensHeld[1]).to.equal(tokensHeld1);

      const lpTokensBorrowed = ONE;
      const res = await getBalanceChanges(lpTokensBorrowed, 0, 0);
      const bal0 = await strategyFee.getPoolData();
      expect(bal0.lpTokenBalance).gt(0);
      expect(bal0.lpTokenBorrowed).to.equal(0);
      expect(bal0.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal0.borrowedInvariant).to.equal(0);
      expect(bal0.lpInvariant).gt(0);
      expect(bal0.lastCFMMInvariant).gt(0);
      expect(bal0.lastCFMMTotalSupply).gt(0);
      expect(bal0.tokenBalance.length).to.equal(2);
      expect(bal0.tokenBalance[0]).to.equal(ONE.mul(10));
      expect(bal0.tokenBalance[1]).to.equal(ONE.mul(20));

      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      // Pool balances changes after borrowing liquidity
      const bal1 = await strategyFee.getPoolData();

      expect(bal1.borrowedInvariant).gt(bal0.borrowedInvariant);
      expect(bal1.borrowedInvariant).to.equal(
        bal0.borrowedInvariant.add(loan1.liquidity)
      );
      expect(bal1.lpTokenBorrowedPlusInterest).to.equal(
        bal0.lpTokenBorrowedPlusInterest.add(lpTokensBorrowed)
      );
      expect(bal1.lpTokenBorrowed).to.equal(
        bal0.lpTokenBorrowed.add(lpTokensBorrowed)
      );
      expect(bal1.lpInvariant).to.equal(bal0.lpInvariant.sub(loan1.liquidity));
      expect(bal1.lpTokenBalance).to.equal(
        bal0.lpTokenBalance.sub(lpTokensBorrowed)
      );
      expect(bal1.tokenBalance[0]).to.equal(
        bal0.tokenBalance[0].add(res.tokenAChange)
      );
      expect(bal1.tokenBalance[1]).to.equal(
        bal0.tokenBalance[1].add(res.tokenBChange)
      );
      // expect(bal1.lastCFMMTotalSupply).to.equal(
      //   bal0.lastCFMMTotalSupply.sub(lpTokensBorrowed)
      // );
      // expect(bal1.lastCFMMInvariant).to.equal(
      //   bal0.lastCFMMInvariant.sub(loan1.liquidity)
      // );

      // about a month and a half
      await ethers.provider.send("hardhat_mine", ["0x4CFE0"]);

      await (await strategyFee.updateLoanData(tokenId)).wait();

      // Pool balances changes after rate upate
      const bal2 = await strategyFee.getPoolData();
      const loan2 = await strategyFee.getLoan(tokenId);
      expect(bal2.borrowedInvariant).gt(bal1.borrowedInvariant);
      expect(bal2.lpTokenBorrowedPlusInterest).gt(
        bal1.lpTokenBorrowedPlusInterest
      );
      expect(bal2.lpTokenBorrowed).to.equal(bal1.lpTokenBorrowed);
      expect(bal2.lpInvariant).to.equal(bal1.lpInvariant);
      expect(bal2.lpTokenBalance).to.equal(bal1.lpTokenBalance);
      expect(bal2.tokenBalance[0]).to.equal(bal1.tokenBalance[0]);
      expect(bal2.tokenBalance[1]).to.equal(bal1.tokenBalance[1]);
      // expect(bal2.lastCFMMTotalSupply).to.equal(bal1.lastCFMMTotalSupply);
      // expect(bal2.lastCFMMInvariant).to.equal(bal1.lastCFMMInvariant.add(1)); // add 1 because loss of precision

      const collateral = sqrt(loan2.tokensHeld[0].mul(loan2.tokensHeld[1]));
      expect(loan2.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan2.liquidity).gt(res.liquidityBorrowed);
      expect(loan2.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));
      expect(
        await strategyFee.canLiquidate(loan2.liquidity, collateral)
      ).to.equal(true);

      await (await tokenA.transfer(cfmm.address, ONE.mul(50))).wait();
      await (await tokenB.transfer(cfmm.address, ONE.mul(100))).wait();
      await (await cfmm.mint(strategyFee.address)).wait();

      const addedLiquidityToCFMM = sqrt(ONE.mul(50).mul(ONE.mul(100)));
      const token0bal0 = await tokenAFee.balanceOf(owner.address);
      const token1bal0 = await tokenBFee.balanceOf(owner.address);

      const resp = await (await strategyFee._liquidateWithLP(tokenId)).wait();

      const writeDownAmt = BigNumber.from("46189100472354650");
      const len = resp.events.length;
      const liquidationEvent = resp.events[len - 3]; // 46157136933282181
      expect(liquidationEvent.event).to.equal("Liquidation");
      expect(liquidationEvent.args.writeDownAmt).to.equal(writeDownAmt);
      expect(liquidationEvent.args.tokenId).to.equal(tokenId);
      expect(liquidationEvent.args.liquidity.div(ONE.div(10000))).to.equal(
        loan2.liquidity.sub(writeDownAmt).div(ONE.div(10000))
      );
      expect(liquidationEvent.args.collateral).to.equal(collateral);
      expect(liquidationEvent.args.txType).to.equal(12);

      const loanUpdateEvent = resp.events[len - 2];
      expect(loanUpdateEvent.event).to.equal("LoanUpdated");
      expect(loanUpdateEvent.args.tokenId).to.equal(tokenId);
      expect(loanUpdateEvent.args.tokensHeld.length).to.equal(2);
      expect(loanUpdateEvent.args.tokensHeld[0]).to.equal(0);
      expect(loanUpdateEvent.args.tokensHeld[1]).to.equal(0);
      expect(loanUpdateEvent.args.liquidity).to.equal(0);
      expect(loanUpdateEvent.args.initLiquidity).to.equal(0);
      expect(loanUpdateEvent.args.lpTokens).to.equal(0);
      expect(loanUpdateEvent.args.rateIndex).to.equal(0);
      expect(loanUpdateEvent.args.txType).to.equal(12);

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.rateIndex).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).to.equal(0);
      expect(loan3.tokensHeld[1]).to.equal(0);

      const token0bal1 = await tokenAFee.balanceOf(owner.address);
      const token1bal1 = await tokenBFee.balanceOf(owner.address);
      expect(token0bal1).gt(token0bal0);
      expect(token1bal1).gt(token1bal0);

      // Pool balances changes after rate upate
      const bal3 = await strategyFee.getPoolData();
      expect(bal3.borrowedInvariant).to.equal(0);
      expect(bal3.borrowedInvariant).lt(bal2.borrowedInvariant);
      expect(
        bal2.borrowedInvariant.sub(writeDownAmt).div(ONE.div(10000))
      ).to.equal(liquidationEvent.args.liquidity.div(ONE.div(10000)));
      expect(bal3.lpTokenBorrowedPlusInterest).to.equal(0);
      expect(bal3.lpTokenBorrowedPlusInterest).lt(
        bal2.lpTokenBorrowedPlusInterest
      );
      expect(bal3.lpTokenBorrowed).to.equal(0);
      expect(bal3.lpTokenBorrowed).to.equal(bal0.lpTokenBorrowed);
      expect(bal3.lpTokenBorrowed).lt(bal2.lpTokenBorrowed);
      expect(bal3.lpInvariant).gt(bal0.lpInvariant);
      expect(bal3.lpInvariant).gt(bal1.lpInvariant);
      expect(bal3.lpInvariant).gt(bal2.lpInvariant);
      expect(bal3.lpTokenBalance).gt(bal0.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal1.lpTokenBalance);
      expect(bal3.lpTokenBalance).gt(bal2.lpTokenBalance);
      expect(bal3.tokenBalance[0]).lt(bal2.tokenBalance[0]);
      expect(bal3.tokenBalance[1]).lt(bal2.tokenBalance[1]);
      expect(bal3.tokenBalance[0]).to.equal(
        bal2.tokenBalance[0].sub(loan2.tokensHeld[0])
      );
      expect(bal3.tokenBalance[1]).to.equal(
        bal2.tokenBalance[1].sub(loan2.tokensHeld[1])
      );
      expect(bal3.lastCFMMTotalSupply).gt(bal0.lastCFMMTotalSupply);
      expect(bal3.lastCFMMTotalSupply).gt(bal1.lastCFMMTotalSupply);
      expect(bal3.lastCFMMTotalSupply).gt(bal2.lastCFMMTotalSupply);
      expect(bal3.lastCFMMInvariant).gt(bal0.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).gt(bal1.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).gt(bal2.lastCFMMInvariant);
      expect(bal3.lastCFMMInvariant).to.equal(
        bal2.lastCFMMInvariant.add(addedLiquidityToCFMM)
      );

      const poolUpdateEvent = resp.events[len - 1];
      expect(poolUpdateEvent.event).to.equal("PoolUpdated");
      expect(poolUpdateEvent.args.lpTokenBalance).to.equal(bal3.lpTokenBalance);
      expect(poolUpdateEvent.args.lpTokenBorrowed).to.equal(
        bal3.lpTokenBorrowed
      );
      expect(poolUpdateEvent.args.lastBlockNumber).to.equal(
        bal3.lastBlockNumber
      );
      expect(poolUpdateEvent.args.accFeeIndex).to.equal(bal3.accFeeIndex);
      expect(poolUpdateEvent.args.lpTokenBorrowedPlusInterest).to.equal(
        bal3.lpTokenBorrowedPlusInterest
      );
      expect(poolUpdateEvent.args.lpInvariant).to.equal(bal3.lpInvariant);
      expect(poolUpdateEvent.args.borrowedInvariant).to.equal(
        bal3.borrowedInvariant
      );
      expect(poolUpdateEvent.args.txType).to.equal(12);
    });
  });
});
