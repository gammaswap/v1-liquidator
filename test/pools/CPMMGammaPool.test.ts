import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

const UniswapV2FactoryJSON = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const UniswapV2PairJSON = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const CPMMGammaPoolJSON = require("@gammaswap/v1-implementations/artifacts/contracts/pools/CPMMGammaPool.sol/CPMMGammaPool.json");
const TestPoolViewerJSON = require("@gammaswap/v1-implementations/artifacts/contracts/test/pools/TestPoolViewer.sol/TestPoolViewer.json");

const PROTOCOL_ID = 1;

describe("CPMMGammaPool", function () {
  let TestERC20: any;
  let CPMMGammaPool: any;
  let TestPoolViewer: any;
  let UniswapV2Factory: any;
  let UniswapV2Pair: any;
  let tokenA: any;
  let tokenB: any;
  let tokenC: any;
  let owner: any;
  let addr1: any;
  let addr2: any;
  let addr3: any;
  let addr4: any;
  let addr5: any;
  let addr6: any;
  let pool: any;
  let viewer: any;
  let gsFactoryAddress: any;
  let cfmmHash: any;
  let longStrategyAddr: any;
  let repayStrategyAddr: any;
  let shortStrategyAddr: any;
  let liquidationStrategyAddr: any;
  let externalRebalanceStrategyAddr: any;
  let externalLiquidationStrategyAddr: any;
  let cfmm: any;
  let uniFactory: any;
  let badPool: any;
  let badPool2: any;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    [owner, addr1, addr2, addr3, addr4, addr5, addr6] = await ethers.getSigners();
    TestERC20 = await ethers.getContractFactory("TestERC20");
    CPMMGammaPool = new ethers.ContractFactory(
        CPMMGammaPoolJSON.abi,
        CPMMGammaPoolJSON.bytecode,
        owner
    );
    TestPoolViewer = new ethers.ContractFactory(
        TestPoolViewerJSON.abi,
        TestPoolViewerJSON.bytecode,
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

    tokenA = await TestERC20.deploy("Test Token A", "TOKA");
    tokenB = await TestERC20.deploy("Test Token B", "TOKB");
    tokenC = await TestERC20.deploy("Test Token C", "TOKC");
    viewer = await TestPoolViewer.deploy();

    uniFactory = await UniswapV2Factory.deploy(owner.address);

    cfmm = await createPair(tokenA, tokenB);

    // 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f UniswapV2
    // 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303 SushiSwap
    gsFactoryAddress = owner.address;
    cfmmHash =
      "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";
    longStrategyAddr = addr1.address;
    repayStrategyAddr = addr4.address;
    shortStrategyAddr = addr2.address;
    liquidationStrategyAddr = addr3.address;
    externalRebalanceStrategyAddr = addr5.address;
    externalLiquidationStrategyAddr = addr6.address;

    pool = await CPMMGammaPool.deploy(
      PROTOCOL_ID,
      owner.address,
      longStrategyAddr,
      repayStrategyAddr,
      shortStrategyAddr,
      liquidationStrategyAddr,
      liquidationStrategyAddr,
      viewer.address,
      externalRebalanceStrategyAddr,
      externalLiquidationStrategyAddr,
      uniFactory.address,
      cfmmHash
    );

    const badCfmmHash =
      "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845e";

    badPool = await CPMMGammaPool.deploy(
      PROTOCOL_ID,
      owner.address,
      longStrategyAddr,
      repayStrategyAddr,
      shortStrategyAddr,
      liquidationStrategyAddr,
      liquidationStrategyAddr,
      viewer.address,
      externalRebalanceStrategyAddr,
      externalLiquidationStrategyAddr,
      uniFactory.address,
      badCfmmHash
    );

    badPool2 = await CPMMGammaPool.deploy(
      PROTOCOL_ID,
      owner.address,
      longStrategyAddr,
      repayStrategyAddr,
      shortStrategyAddr,
      liquidationStrategyAddr,
      liquidationStrategyAddr,
      viewer.address,
      externalRebalanceStrategyAddr,
      externalLiquidationStrategyAddr,
      gsFactoryAddress,
      cfmmHash
    );
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

  async function validateCFMM(token0: any, token1: any, cfmm: any) {
    const data = ethers.utils.defaultAbiCoder.encode([], []);
    const tokensOrdered = await pool.validateCFMM(
      [token0.address, token1.address],
      cfmm.address,
      data
    );
    const bigNum0 = BigNumber.from(token0.address);
    const bigNum1 = BigNumber.from(token1.address);
    const token0Addr = bigNum0.lt(bigNum1) ? token0.address : token1.address;
    const token1Addr = bigNum0.lt(bigNum1) ? token1.address : token0.address;
    expect(tokensOrdered[0]).to.equal(token0Addr);
    expect(tokensOrdered[1]).to.equal(token1Addr);
  }

  describe("Deployment", function () {
    it("Should set right init params", async function () {
      expect(await pool.protocolId()).to.equal(1);
      expect(await pool.borrowStrategy()).to.equal(addr1.address);
      expect(await pool.repayStrategy()).to.equal(addr4.address);
      expect(await pool.rebalanceStrategy()).to.equal(addr1.address);
      expect(await pool.shortStrategy()).to.equal(addr2.address);
      expect(await pool.singleLiquidationStrategy()).to.equal(addr3.address);
      expect(await pool.batchLiquidationStrategy()).to.equal(addr3.address);
      expect(await pool.factory()).to.equal(owner.address);
      expect(await pool.cfmmFactory()).to.equal(uniFactory.address);
      expect(await pool.cfmmInitCodeHash()).to.equal(cfmmHash);
    });
  });

  describe("Validate CFMM", function () {
    it("Error is Not Contract", async function () {
      const data = ethers.utils.defaultAbiCoder.encode([], []);
      await expect(
        pool.validateCFMM([tokenA.address, tokenB.address], owner.address, data)
      ).to.be.revertedWithCustomError(pool, "NotContract");
    });

    it("Error Not Right Contract", async function () {
      const data = ethers.utils.defaultAbiCoder.encode([], []);
      await expect(
        pool.validateCFMM(
          [tokenA.address, tokenB.address],
          uniFactory.address,
          data
        )
      ).to.be.revertedWithCustomError(pool, "BadProtocol");
    });

    it("Error Not Right Tokens", async function () {
      const data = ethers.utils.defaultAbiCoder.encode([], []);
      await expect(
        pool.validateCFMM([tokenA.address, tokenC.address], cfmm.address, data)
      ).to.be.revertedWithCustomError(pool, "BadProtocol");
    });

    it("Error Bad Hash", async function () {
      expect(await badPool.cfmmFactory()).to.equal(uniFactory.address);
      expect(await badPool.cfmmInitCodeHash()).to.not.equal(cfmmHash);
      const data = ethers.utils.defaultAbiCoder.encode([], []);
      await expect(
        badPool.validateCFMM(
          [tokenA.address, tokenB.address],
          cfmm.address,
          data
        )
      ).to.be.revertedWithCustomError(pool, "BadProtocol");
    });

    it("Error Bad Factory", async function () {
      expect(await badPool2.cfmmFactory()).to.not.equal(uniFactory.address);
      expect(await badPool2.cfmmInitCodeHash()).to.equal(cfmmHash);
      const data = ethers.utils.defaultAbiCoder.encode([], []);
      await expect(
        badPool2.validateCFMM(
          [tokenA.address, tokenB.address],
          cfmm.address,
          data
        )
      ).to.be.revertedWithCustomError(badPool2, "BadProtocol");
    });

    it("Correct Validation", async function () {
      expect(await pool.cfmmFactory()).to.equal(uniFactory.address);
      expect(await pool.cfmmInitCodeHash()).to.equal(cfmmHash);

      await validateCFMM(tokenA, tokenB, cfmm);

      const cfmm1 = await createPair(tokenA, tokenC);
      await validateCFMM(tokenA, tokenC, cfmm1);

      const cfmm2 = await createPair(tokenB, tokenC);
      await validateCFMM(tokenB, tokenC, cfmm2);
    });
  });
});
