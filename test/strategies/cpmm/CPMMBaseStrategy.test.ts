import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

const UniswapV2FactoryJSON = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairJSON = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const TestCPMMBaseStrategyJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/strategies/cpmm/TestCPMMBaseStrategy.sol/TestCPMMBaseStrategy.json");

describe("CPMMBaseStrategy", function () {
  let TestERC20: any;
  let TestStrategy: any;
  let UniswapV2Factory: any;
  let UniswapV2Pair: any;
  let tokenA: any;
  let tokenB: any;
  let cfmm: any;
  let uniFactory: any;
  let strategy: any;
  let owner: any;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    TestERC20 = await ethers.getContractFactory("TestERC20");
    [owner] = await ethers.getSigners();
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
    TestStrategy = new ethers.ContractFactory(
        TestCPMMBaseStrategyJSON.abi,
        TestCPMMBaseStrategyJSON.bytecode,
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

    strategy = await TestStrategy.deploy(baseRate, factor, maxApy);
    await (
      await strategy.initialize(
        cfmm.address,
        [tokenA.address, tokenB.address],
        [18, 18]
      )
    ).wait();
  });

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

  async function sendToCFMM(amtA: BigNumber, amtB: BigNumber) {
    await tokenA.transfer(cfmm.address, amtA);
    await tokenB.transfer(cfmm.address, amtB);
  }

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    it("Check Init Params", async function () {
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

    it("Check Invariant Calculation", async function () {
      expect(
        await strategy.testCalcInvariant(cfmm.address, [
          BigNumber.from(10),
          BigNumber.from(10),
        ])
      ).to.equal(10);
      expect(
        await strategy.testCalcInvariant(cfmm.address, [
          BigNumber.from(20),
          BigNumber.from(20),
        ])
      ).to.equal(20);
      expect(
        await strategy.testCalcInvariant(cfmm.address, [
          BigNumber.from(30),
          BigNumber.from(30),
        ])
      ).to.equal(30);
      expect(
        await strategy.testCalcInvariant(cfmm.address, [
          BigNumber.from(20),
          BigNumber.from(500),
        ])
      ).to.equal(100);
      expect(
        await strategy.testCalcInvariant(cfmm.address, [
          BigNumber.from(2),
          BigNumber.from(450),
        ])
      ).to.equal(30);
    });
  });

  describe("Check Write Functions", function () {
    it("Deposit to CFMM", async function () {
      const ONE = BigNumber.from(10).pow(18);
      const amtA = ONE.mul(20);
      const amtB = ONE.mul(500);
      await sendToCFMM(amtA, amtB);
      const expectedSupply = ONE.mul(100);
      const expectedLiquidity = expectedSupply.sub(1000); // subtract 1000 because 1st deposit
      expect(await cfmm.balanceOf(owner.address)).to.equal(0);
      expect(await cfmm.balanceOf(strategy.address)).to.equal(0);
      expect(await cfmm.totalSupply()).to.equal(0);
      const res = await (
        await strategy.testDepositToCFMM(
          cfmm.address,
          [amtA, amtB],
          strategy.address
        )
      ).wait();
      const depositToCFMMEvent = res.events[res.events.length - 1];
      expect(depositToCFMMEvent.args.cfmm).to.equal(cfmm.address);
      expect(depositToCFMMEvent.args.to).to.equal(strategy.address);
      expect(depositToCFMMEvent.args.liquidity).to.equal(expectedLiquidity);
      expect(await cfmm.balanceOf(strategy.address)).to.equal(
        expectedLiquidity
      );
      expect(await cfmm.balanceOf(owner.address)).to.equal(0);
      expect(await cfmm.totalSupply()).to.equal(expectedSupply);
    });

    it("Withdraw from CFMM", async function () {
      const ONE = BigNumber.from(10).pow(18);
      const amtA = ONE.mul(20);
      const amtB = ONE.mul(500);
      await sendToCFMM(amtA, amtB);
      await (
        await strategy.testDepositToCFMM(
          cfmm.address,
          [amtA, amtB],
          strategy.address
        )
      ).wait();

      const withdrawAmt = ONE.mul(50);
      const expectedAmtA = ONE.mul(10);
      const expectedAmtB = ONE.mul(250);
      expect(await tokenA.balanceOf(strategy.address)).to.equal(0);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(0);
      const res = await (
        await strategy.testWithdrawFromCFMM(
          cfmm.address,
          withdrawAmt,
          strategy.address
        )
      ).wait();

      const withdrawFromCFMMEvent = res.events[res.events.length - 1];
      expect(withdrawFromCFMMEvent.args.cfmm).to.equal(cfmm.address);
      expect(withdrawFromCFMMEvent.args.to).to.equal(strategy.address);
      expect(withdrawFromCFMMEvent.args.amounts.length).to.equal(2);
      expect(withdrawFromCFMMEvent.args.amounts[0]).to.equal(expectedAmtA);
      expect(withdrawFromCFMMEvent.args.amounts[1]).to.equal(expectedAmtB);
      expect(await tokenA.balanceOf(strategy.address)).to.equal(expectedAmtA);
      expect(await tokenB.balanceOf(strategy.address)).to.equal(expectedAmtB);
    });

    it("Update Reserves", async function () {
      const res = await strategy.getCFMMReserves();
      expect(res.length).to.equal(2);
      expect(res[0]).to.equal(0);
      expect(res[1]).to.equal(0);

      const ONE = BigNumber.from(10).pow(18);
      const amtA = ONE.mul(20);
      const amtB = ONE.mul(500);
      await sendToCFMM(amtA, amtB);
      await (
        await strategy.testDepositToCFMM(
          cfmm.address,
          [amtA, amtB],
          strategy.address
        )
      ).wait();

      const res1 = await strategy.getCFMMReserves();
      expect(res1.length).to.equal(2);
      expect(res1[0]).to.equal(0);
      expect(res1[1]).to.equal(0);

      await (await strategy.testUpdateReserves()).wait();

      const res2 = await strategy.getCFMMReserves();
      expect(res2.length).to.equal(2);
      expect(res2[0]).to.equal(amtA);
      expect(res2[1]).to.equal(amtB);

      const withdrawAmt = ONE.mul(50);
      const expectedAmtA = ONE.mul(10);
      const expectedAmtB = ONE.mul(250);

      await (
        await strategy.testWithdrawFromCFMM(
          cfmm.address,
          withdrawAmt,
          strategy.address
        )
      ).wait();

      const res3 = await strategy.getCFMMReserves();
      expect(res3.length).to.equal(2);
      expect(res3[0]).to.equal(amtA);
      expect(res3[1]).to.equal(amtB);

      await (await strategy.testUpdateReserves()).wait();

      const res4 = await strategy.getCFMMReserves();
      expect(res4.length).to.equal(2);
      expect(res4[0]).to.equal(expectedAmtA);
      expect(res4[1]).to.equal(expectedAmtB);
    });
  });
});
