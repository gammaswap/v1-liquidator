import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

const UniswapV2FactoryJSON = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairJSON = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const DeltaSwapFactoryJSON = require("@gammaswap/v1-deltaswap/artifacts/contracts/DeltaSwapFactory.sol/DeltaSwapFactory.json");
const DeltaSwapPairJSON = require("@gammaswap/v1-deltaswap/artifacts/contracts/DeltaSwapPair.sol/DeltaSwapPair.json");

const IS_DELTASWAP = true;

describe("CPMMShortStrategy", function () {
  let TestERC20: any;
  let TestStrategy: any;
  let TestGammaPoolFactory: any;
  let UniswapV2Factory: any;
  let UniswapV2Pair: any;
  let tokenA: any;
  let tokenB: any;
  let cfmm: any;
  let gsFactory: any;
  let uniFactory: any;
  let strategy: any;
  let owner: any;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    TestERC20 = await ethers.getContractFactory("TestERC20");
    TestGammaPoolFactory = await ethers.getContractFactory("TestGammaPoolFactory");
    TestStrategy = await ethers.getContractFactory("TestCPMMShortStrategy");
    [owner] = await ethers.getSigners();
    UniswapV2Factory = new ethers.ContractFactory(
        IS_DELTASWAP ? DeltaSwapFactoryJSON.abi : UniswapV2FactoryJSON.abi,
        IS_DELTASWAP ? DeltaSwapFactoryJSON.bytecode : UniswapV2FactoryJSON.bytecode,
        owner
    );
    UniswapV2Pair = new ethers.ContractFactory(
        IS_DELTASWAP ? DeltaSwapPairJSON.abi : UniswapV2PairJSON.abi,
        IS_DELTASWAP ? DeltaSwapPairJSON.bytecode : UniswapV2PairJSON.bytecode,
        owner
    );

    tokenA = await TestERC20.deploy("Test Token A", "TOKA");
    tokenB = await TestERC20.deploy("Test Token B", "TOKB");

    const ONE = BigNumber.from(10).pow(18);
    tokenA.mint(owner.address, ONE.mul(100000));
    tokenB.mint(owner.address, ONE.mul(100000));

    // address _feeToSetter, uint16 _fee
    gsFactory = await TestGammaPoolFactory.deploy(owner.address, 10000);

    uniFactory = IS_DELTASWAP ? await UniswapV2Factory.deploy(owner.address, owner.address, gsFactory.address) : await UniswapV2Factory.deploy(owner.address);

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

    const baseRate = ONE.div(100);
    const optimalUtilRate = ONE.mul(8).div(10);
    const slope1 = ONE.mul(5).div(100);
    const slope2 = ONE.mul(75).div(100);

    strategy = await TestStrategy.deploy(baseRate, optimalUtilRate, slope1, slope2);

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
      const optimalUtilRate = ONE.mul(8).div(10);
      const slope1 = ONE.mul(5).div(100);
      const slope2 = ONE.mul(75).div(100);
      expect(await strategy.baseRate()).to.equal(baseRate);
      expect(await strategy.optimalUtilRate()).to.equal(optimalUtilRate);
      expect(await strategy.slope1()).to.equal(slope1);
      expect(await strategy.slope2()).to.equal(slope2);
      expect(await strategy.BLOCKS_PER_YEAR()).to.equal(2252571);
      expect(await strategy.MAX_TOTAL_APY()).to.equal(ONE.mul(10));
    });
  });

  describe("Calc Deposit Amounts Functions", function () {
    it("Check Optimal Amt", async function () {
      const ONE = BigNumber.from(10).pow(18);
      const amountOptimal = ONE.mul(100);
      const amountMin = amountOptimal.add(1);

      await expect(
        strategy.testCheckOptimalAmt(amountOptimal, amountMin)
      ).to.be.revertedWithCustomError(strategy, "NotOptimalDeposit");

      expect(
        await strategy.testCheckOptimalAmt(amountOptimal, amountMin.sub(1))
      ).to.equal(3);
      expect(
        await strategy.testCheckOptimalAmt(amountOptimal.add(1), amountMin)
      ).to.equal(3);
      expect(
        await strategy.testCheckOptimalAmt(amountOptimal.add(2), amountMin)
      ).to.equal(3);
    });

    it("Get Reserves", async function () {
      const ONE = BigNumber.from(10).pow(18);
      const amtA = ONE.mul(20);
      const amtB = ONE.mul(500);
      await sendToCFMM(amtA, amtB);

      const res0 = await strategy.testGetReserves(cfmm.address);
      expect(res0.length).to.equal(2);
      expect(res0[0]).to.equal(0);
      expect(res0[1]).to.equal(0);

      await (await cfmm.mint(owner.address)).wait();

      const res1 = await strategy.testGetReserves(cfmm.address);
      expect(res1.length).to.equal(2);
      expect(res1[0]).to.equal(amtA);
      expect(res1[1]).to.equal(amtB);

      await sendToCFMM(amtA, amtB);

      await (await cfmm.mint(owner.address)).wait();

      const res2 = await strategy.testGetReserves(cfmm.address);
      expect(res2.length).to.equal(2);
      expect(res2[0]).to.equal(amtA.mul(2));
      expect(res2[1]).to.equal(amtB.mul(2));

      await (await cfmm.transfer(cfmm.address, ONE.mul(50))).wait();
      await (await cfmm.burn(owner.address)).wait();

      const res3 = await strategy.testGetReserves(cfmm.address);
      expect(res3.length).to.equal(2);
      expect(res3[0]).to.equal(amtA.mul(2).sub(amtA.div(2)));
      expect(res3[1]).to.equal(amtB.mul(2).sub(amtB.div(2)));
    });

    it("Error Calc Deposit Amounts, 0 amt", async function () {
      await expect(
        strategy.testCalcDeposits([0, 0], [0, 0])
      ).to.be.revertedWithCustomError(strategy, "ZeroDeposits");
      await expect(
        strategy.testCalcDeposits([1, 0], [0, 0])
      ).to.be.revertedWithCustomError(strategy, "ZeroDeposits");
      await expect(
        strategy.testCalcDeposits([0, 1], [0, 0])
      ).to.be.revertedWithCustomError(strategy, "ZeroDeposits");
    });

    it("Error Calc Deposit Amounts, 0 reserve tokenA", async function () {
      await (await tokenB.transfer(cfmm.address, 1)).wait();
      await (await cfmm.sync()).wait();
      await expect(
        strategy.testCalcDeposits([1, 1], [0, 0])
      ).to.be.revertedWithCustomError(strategy, "ZeroReserves");
    });

    it("Error Calc Deposit Amounts, 0 reserve tokenB", async function () {
      await (await tokenA.transfer(cfmm.address, 1)).wait();
      await (await cfmm.sync()).wait();
      await expect(
        strategy.testCalcDeposits([1, 1], [0, 0])
      ).to.be.revertedWithCustomError(strategy, "ZeroReserves");
    });

    it("Error Calc Deposit Amounts, < minAmt", async function () {
      await (await tokenA.transfer(cfmm.address, 1)).wait();
      await (await tokenB.transfer(cfmm.address, 1)).wait();
      await (await cfmm.sync()).wait();
      await expect(
        strategy.testCalcDeposits([1, 1], [0, 2])
      ).to.be.revertedWithCustomError(strategy, "NotOptimalDeposit");

      await (await tokenB.transfer(cfmm.address, 1)).wait();
      await (await cfmm.sync()).wait();
      await expect(
        strategy.testCalcDeposits([1, 1], [2, 0])
      ).to.be.revertedWithCustomError(strategy, "NotOptimalDeposit");
    });

    it("Empty reserves", async function () {
      const res = await strategy.testCalcDeposits([1, 1], [0, 0]);
      expect(res.amounts.length).to.equal(2);
      expect(res.amounts[0]).to.equal(1);
      expect(res.amounts[1]).to.equal(1);
      expect(res.payee).to.equal(cfmm.address);
    });

    it("Success Calculation", async function () {
      const ONE = BigNumber.from(10).pow(18);
      await (await tokenA.transfer(cfmm.address, ONE.mul(100))).wait();
      await (await tokenB.transfer(cfmm.address, ONE.mul(100))).wait();
      await (await cfmm.sync()).wait();
      const res = await strategy.testCalcDeposits(
        [ONE.mul(100), ONE.mul(100)],
        [0, 0]
      );
      expect(res.amounts.length).to.equal(2);
      expect(res.amounts[0]).to.equal(ONE.mul(100));
      expect(res.amounts[1]).to.equal(ONE.mul(100));
      expect(res.payee).to.equal(cfmm.address);

      await (await tokenB.transfer(cfmm.address, ONE.mul(100))).wait();
      await (await cfmm.sync()).wait();

      const res1 = await strategy.testCalcDeposits(
        [ONE.mul(100), ONE.mul(100)],
        [0, 0]
      );
      expect(res1.amounts.length).to.equal(2);
      expect(res1.amounts[0]).to.equal(ONE.mul(50));
      expect(res1.amounts[1]).to.equal(ONE.mul(100));
      expect(res1.payee).to.equal(cfmm.address);

      await (await tokenA.transfer(cfmm.address, ONE.mul(300))).wait();
      await (await cfmm.sync()).wait();

      const res2 = await strategy.testCalcDeposits(
        [ONE.mul(100), ONE.mul(100)],
        [0, 0]
      );
      expect(res2.amounts.length).to.equal(2);
      expect(res2.amounts[0]).to.equal(ONE.mul(100));
      expect(res2.amounts[1]).to.equal(ONE.mul(50));
      expect(res2.payee).to.equal(cfmm.address);
    });
  });
});
