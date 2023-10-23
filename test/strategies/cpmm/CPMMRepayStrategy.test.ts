import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

const UniswapV2FactoryJSON = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairJSON = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const TestERC20WithFeeJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/TestERC20WithFee.sol/TestERC20WithFee.json");
const TestGammaPoolFactoryJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/TestGammaPoolFactory.sol/TestGammaPoolFactory.json");
const TestCPMMRepayStrategyJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/strategies/cpmm/TestCPMMRepayStrategy.sol/TestCPMMRepayStrategy.json");

describe("CPMMRepayStrategy", function () {
  let TestERC20: any;
  let TestERC20WithFee: any;
  let TestStrategy: any;
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
  let strategyFee: any;
  let owner: any;
  let addr1: any;
  let addr2: any;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    [owner, addr1, addr2] = await ethers.getSigners();
    TestERC20 = await ethers.getContractFactory("TestERC20");
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
        TestCPMMRepayStrategyJSON.abi,
        TestCPMMRepayStrategyJSON.bytecode,
        owner
    );
    tokenA = await TestERC20.deploy("Test Token A", "TOKA");
    tokenB = await TestERC20.deploy("Test Token B", "TOKB");

    uniFactory = await UniswapV2Factory.deploy(owner.address);

    cfmm = await createPair(tokenA, tokenB);

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
    const baseRate = ONE.div(100);
    const factor = ONE.mul(4).div(100);
    const maxApy = ONE.mul(75).div(100);

    strategy = await TestStrategy.deploy(
      addr2.address,
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
  });

  async function createStrategy(tok0Fee: any, tok1Fee: any) {
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

    const fee = BigNumber.from(10).pow(16);

    if (tok0Fee) {
      await (await tokenAFee.setFee(fee)).wait();
    }

    if (tok1Fee) {
      await (await tokenBFee.setFee(fee)).wait();
    }

    const ONE = BigNumber.from(10).pow(18);
    const baseRate = ONE.div(100);
    const factor = ONE.mul(4).div(100);
    const maxApy = ONE.mul(75).div(100);

    strategyFee = await TestStrategy.deploy(
      addr2.address,
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

  async function setUpStrategyAndCFMM(tokenId: any, hasFee: any) {
    const ONE = BigNumber.from(10).pow(18);

    if (hasFee) {
      strategy = strategyFee;
      tokenA = tokenAFee;
      tokenB = tokenBFee;
      cfmm = cfmmFee;
    }

    const collateral0 = ONE.mul(100);
    const collateral1 = ONE.mul(200);
    const balance0 = ONE.mul(1000);
    const balance1 = ONE.mul(2000);

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
    };
  }

  function getTokensHeld(amt0: any, amt1: any, fee0: any, fee1: any) {
    const ONE = BigNumber.from(10).pow(18);
    const feeAmt0 = amt0.mul(fee0).div(ONE);
    const feeAmt1 = amt1.mul(fee1).div(ONE);
    return { tokensHeld0: amt0.sub(feeAmt0), tokensHeld1: amt1.sub(feeAmt1) };
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
      expect(await strategy.baseRate()).to.equal(baseRate);
      expect(await strategy.factor()).to.equal(factor);
      expect(await strategy.maxApy()).to.equal(maxApy);
      expect(await strategy.BLOCKS_PER_YEAR()).to.equal(2252571);
      expect(await strategy.MAX_TOTAL_APY()).to.equal(ONE.mul(10));
    });
  });

  describe("Repay Functions", function () {
    it("Calc Tokens to Repay", async function () {
      const ONE = BigNumber.from(10).pow(18);
      const reserves0 = ONE.mul(500);
      const reserves1 = ONE.mul(1000);
      const lastCFMMInvariant = await strategy.testCalcInvariant([
        reserves0,
        reserves1,
      ]);
      const liquidity = ONE.mul(100);
      await (
        await strategy.setCFMMReserves(reserves0, reserves1, lastCFMMInvariant)
      ).wait();
      const expToken0 = liquidity.mul(reserves0).div(lastCFMMInvariant);
      const expToken1 = liquidity.mul(reserves1).div(lastCFMMInvariant);
      const res0 = await strategy.testCalcTokensToRepay(liquidity);
      expect(res0[0]).to.equal(expToken0);
      expect(res0[1]).to.equal(expToken1);

      const reserves0a = reserves0;
      const reserves1a = reserves1.mul(2);
      const lastCFMMInvariant1 = await strategy.testCalcInvariant([
        reserves0a,
        reserves1a,
      ]);
      await (
        await strategy.setCFMMReserves(
          reserves0a,
          reserves1a,
          lastCFMMInvariant1
        )
      ).wait();
      const expToken0a = liquidity.mul(reserves0a).div(lastCFMMInvariant1);
      const expToken1a = liquidity.mul(reserves1a).div(lastCFMMInvariant1);
      const res1 = await strategy.testCalcTokensToRepay(liquidity);
      expect(res1[0]).to.equal(expToken0a);
      expect(res1[1]).to.equal(expToken1a);

      const reserves0b = reserves0.mul(2);
      const reserves1b = reserves1;
      const lastCFMMInvariant2 = await strategy.testCalcInvariant([
        reserves0b,
        reserves1b,
      ]);
      await (
        await strategy.setCFMMReserves(
          reserves0b,
          reserves1b,
          lastCFMMInvariant2
        )
      ).wait();
      const expToken0b = liquidity.mul(reserves0b).div(lastCFMMInvariant2);
      const expToken1b = liquidity.mul(reserves1b).div(lastCFMMInvariant2);
      const res2 = await strategy.testCalcTokensToRepay(liquidity);
      expect(res2[0]).to.equal(expToken0b);
      expect(res2[1]).to.equal(expToken1b);
    });

    it("Error Before Repay", async function () {
      const ONE = BigNumber.from(10).pow(18);

      const res1 = await (await strategy.createLoan()).wait();
      const tokenId = res1.events[0].args.tokenId;

      await expect(
        strategy.testBeforeRepay(tokenId, [1, 1])
      ).to.be.revertedWithCustomError(strategy, "NotEnoughCollateral");

      expect(await tokenA.balanceOf(cfmm.address)).to.equal(0);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(0);

      await (await strategy.setTokenBalances(tokenId, 10, 10, 100, 10)).wait();

      await expect(
        strategy.testBeforeRepay(tokenId, [11, 1])
      ).to.be.revertedWithCustomError(strategy, "NotEnoughCollateral");

      expect(await tokenA.balanceOf(cfmm.address)).to.equal(0);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(0);

      const amtA = ONE.mul(100);
      const amtB = ONE.mul(200);

      await (await tokenA.transfer(strategy.address, amtA)).wait();
      await (await tokenB.transfer(strategy.address, amtB)).wait();

      await expect(
        strategy.testBeforeRepay(tokenId, [1, 11])
      ).to.be.revertedWithCustomError(strategy, "NotEnoughCollateral");

      expect(await tokenA.balanceOf(cfmm.address)).to.equal(0);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(0);

      await (await strategy.setTokenBalances(tokenId, 10, 10, 100, 11)).wait();

      await expect(
        strategy.testBeforeRepay(tokenId, [1, 11])
      ).to.be.revertedWithCustomError(strategy, "NotEnoughCollateral");

      expect(await tokenA.balanceOf(cfmm.address)).to.equal(0);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(0);
    });

    it("Before Repay", async function () {
      const res1 = await (await strategy.createLoan()).wait();
      const tokenId = res1.events[0].args.tokenId;

      await (await tokenA.transfer(strategy.address, 100)).wait();
      await (await tokenB.transfer(strategy.address, 200)).wait();

      expect(await tokenA.balanceOf(strategy.address)).to.equal(100);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(200);
      expect(await tokenA.balanceOf(cfmm.address)).to.equal(0);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(0);

      await (
        await strategy.setTokenBalances(tokenId, 100, 200, 100, 200)
      ).wait();

      await (await strategy.testBeforeRepay(tokenId, [100, 200])).wait();

      expect(await tokenA.balanceOf(cfmm.address)).to.equal(100);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(200);
      expect(await tokenA.balanceOf(strategy.address)).to.equal(0);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(0);

      await (await tokenA.transfer(strategy.address, 300)).wait();
      await (await tokenB.transfer(strategy.address, 140)).wait();

      expect(await tokenA.balanceOf(strategy.address)).to.equal(300);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(140);
      expect(await tokenA.balanceOf(cfmm.address)).to.equal(100);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(200);

      await (await strategy.setTokenBalances(tokenId, 150, 70, 150, 70)).wait();

      await (await strategy.testBeforeRepay(tokenId, [150, 70])).wait();

      expect(await tokenA.balanceOf(strategy.address)).to.equal(150);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(70);
      expect(await tokenA.balanceOf(cfmm.address)).to.equal(250);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(270);

      await (await strategy.testBeforeRepay(tokenId, [150, 70])).wait();

      expect(await tokenA.balanceOf(strategy.address)).to.equal(0);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(0);
      expect(await tokenA.balanceOf(cfmm.address)).to.equal(400);
      expect(await tokenB.balanceOf(cfmm.address)).to.equal(340);
    });
  });

  describe("Repay Loans", function () {
    it("Repay Tokens without Fees", async function () {
      await createStrategy(false, false);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const tokensHeld0 = ONE.mul(100);
      const tokensHeld1 = ONE.mul(200);

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

      const payLiquidity = res.liquidityBorrowed;

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan2 = await strategyFee.getLoan(tokenId);
      expect(loan2.initLiquidity).gt(0);
      expect(loan2.liquidity).gt(0);
      expect(loan2.lpTokens).gt(0);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).to.equal(0);
      expect(loan3.liquidity).to.equal(0);
      expect(loan3.lpTokens).to.equal(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(tokensHeld0);
      expect(loan3.tokensHeld[1]).lt(tokensHeld1);
    });

    it("Repay Tokens with Fees", async function () {
      await createStrategy(true, true);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const fee = ONE.div(10);
      const _held = getTokensHeld(ONE.mul(100), ONE.mul(200), fee, fee);
      const tokensHeld0 = _held.tokensHeld0;
      const tokensHeld1 = _held.tokensHeld1;

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
      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).lt(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).lt(tokensHeld1.add(res.tokenBChange));

      const payLiquidity = res.liquidityBorrowed;

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan2 = await strategyFee.getLoan(tokenId);
      expect(loan2.initLiquidity).gt(0);
      expect(loan2.liquidity).gt(0);
      expect(loan2.lpTokens).gt(0);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).lt(tokensHeld0);
      expect(loan2.tokensHeld[1]).lt(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).gt(0);
      expect(loan3.liquidity).gt(0);
      expect(loan3.lpTokens).gt(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(tokensHeld0);
      expect(loan3.tokensHeld[1]).lt(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan4 = await strategyFee.getLoan(tokenId);
      expect(loan4.initLiquidity).lt(loan3.initLiquidity.div(100));
      expect(loan4.initLiquidity).gt(0);
      expect(loan4.liquidity).lt(loan3.liquidity.div(99));
      expect(loan4.liquidity).gt(0);
      expect(loan4.lpTokens).lt(loan3.lpTokens.div(100));
      expect(loan4.lpTokens).gt(0);
      expect(loan4.tokensHeld.length).to.equal(2);
      expect(loan4.tokensHeld[0]).lt(tokensHeld0);
      expect(loan4.tokensHeld[1]).lt(tokensHeld1);
    });

    it("Repay Tokens with only TokenA Fees", async function () {
      await createStrategy(true, false);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const fee = ONE.div(10);
      const _held = getTokensHeld(ONE.mul(100), ONE.mul(200), fee, 0);
      const tokensHeld0 = _held.tokensHeld0;
      const tokensHeld1 = _held.tokensHeld1;

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
      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).lt(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).to.equal(tokensHeld1.add(res.tokenBChange));

      const payLiquidity = res.liquidityBorrowed;

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan2 = await strategyFee.getLoan(tokenId);
      expect(loan2.initLiquidity).gt(0);
      expect(loan2.liquidity).gt(0);
      expect(loan2.lpTokens).gt(0);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).lt(tokensHeld0);
      expect(loan2.tokensHeld[1]).to.equal(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).gt(0);
      expect(loan3.liquidity).gt(0);
      expect(loan3.lpTokens).gt(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(tokensHeld0);
      expect(loan3.tokensHeld[1]).lt(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan4 = await strategyFee.getLoan(tokenId);
      expect(loan4.initLiquidity).lt(loan3.initLiquidity.mul(10).div(1000));
      expect(loan4.initLiquidity).gt(0);
      expect(loan4.liquidity).lt(loan3.liquidity.mul(10).div(999));
      expect(loan4.liquidity).gt(0);
      expect(loan4.lpTokens).lt(loan3.lpTokens.mul(10).div(1000));
      expect(loan4.lpTokens).gt(0);
      expect(loan4.tokensHeld.length).to.equal(2);
      expect(loan4.tokensHeld[0]).lt(tokensHeld0);
      expect(loan4.tokensHeld[1]).lt(tokensHeld1);
    });

    it("Repay Tokens with only TokenB Fees", async function () {
      await createStrategy(false, true);

      const tokenId = (await (await strategyFee.createLoan()).wait()).events[0]
        .args.tokenId;

      const ONE = BigNumber.from(10).pow(18);
      const fee = ONE.div(10);
      const _held = getTokensHeld(ONE.mul(100), ONE.mul(200), 0, fee);
      const tokensHeld0 = _held.tokensHeld0;
      const tokensHeld1 = _held.tokensHeld1;

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
      await (
        await strategyFee._borrowLiquidity(tokenId, lpTokensBorrowed, [])
      ).wait();
      const loan1 = await strategyFee.getLoan(tokenId);
      expect(loan1.initLiquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.liquidity).to.equal(res.liquidityBorrowed);
      expect(loan1.lpTokens).to.equal(lpTokensBorrowed);
      expect(loan1.tokensHeld.length).to.equal(2);
      expect(loan1.tokensHeld[0]).to.equal(tokensHeld0.add(res.tokenAChange));
      expect(loan1.tokensHeld[1]).lt(tokensHeld1.add(res.tokenBChange));

      const payLiquidity = res.liquidityBorrowed;

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan2 = await strategyFee.getLoan(tokenId);
      expect(loan2.initLiquidity).gt(0);
      expect(loan2.liquidity).gt(0);
      expect(loan2.lpTokens).gt(0);
      expect(loan2.tokensHeld.length).to.equal(2);
      expect(loan2.tokensHeld[0]).to.equal(tokensHeld0);
      expect(loan2.tokensHeld[1]).lt(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan3 = await strategyFee.getLoan(tokenId);
      expect(loan3.initLiquidity).gt(0);
      expect(loan3.liquidity).gt(0);
      expect(loan3.lpTokens).gt(0);
      expect(loan3.tokensHeld.length).to.equal(2);
      expect(loan3.tokensHeld[0]).lt(tokensHeld0);
      expect(loan3.tokensHeld[1]).lt(tokensHeld1);

      await (
        await strategyFee._repayLiquidity(
          tokenId,
          payLiquidity,
          0,
          ethers.constants.AddressZero
        )
      ).wait();

      const loan4 = await strategyFee.getLoan(tokenId);
      expect(loan4.initLiquidity).lt(loan3.initLiquidity.mul(10).div(1000));
      expect(loan4.initLiquidity).gt(0);
      expect(loan4.liquidity).lt(loan3.liquidity.mul(10).div(999));
      expect(loan4.liquidity).gt(0);
      expect(loan4.lpTokens).lt(loan3.lpTokens.mul(10).div(1000));
      expect(loan4.lpTokens).gt(0);
      expect(loan4.tokensHeld.length).to.equal(2);
      expect(loan4.tokensHeld[0]).lt(tokensHeld0);
      expect(loan4.tokensHeld[1]).lt(tokensHeld1);
    });
  });
});
