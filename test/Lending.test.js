const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseUnits } = require("ethers");

describe("Lending.sol v0.1", function () {
  let owner, alice, bob;
  let Lending, lending;
  let Token, dai, usdc;
  let DAI_PRICE_FEED, USDC_PRICE_FEED;

  const initialPrice = parseUnits("1", 8); // $1 with 8 decimals

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy mock price feeds
    const MockAggregator = await ethers.getContractFactory("MockV3Aggregator");
    DAI_PRICE_FEED = await MockAggregator.deploy(initialPrice);
    await DAI_PRICE_FEED.waitForDeployment();
    USDC_PRICE_FEED = await MockAggregator.deploy(initialPrice);
    await USDC_PRICE_FEED.waitForDeployment();

    // Deploy mock tokens
    Token = await ethers.getContractFactory("ERC20Mock");
    dai = await Token.deploy("DAI", "DAI", alice.address, parseUnits("1000", 18));
    await dai.waitForDeployment();
    usdc = await Token.deploy("USDC", "USDC", owner.address, parseUnits("1000", 18));
    await usdc.waitForDeployment();

    // Deploy lending contract
    Lending = await ethers.getContractFactory("Lending");
    lending = await Lending.deploy();
    await lending.waitForDeployment();

    // List tokens using .target (Ethers v6)
    await lending.connect(owner).listToken(dai.target, DAI_PRICE_FEED.target, 8000);
    await lending.connect(owner).listToken(usdc.target, USDC_PRICE_FEED.target, 8000);

    // Fund lending contract with USDC liquidity
    await usdc.transfer(lending.target, parseUnits("500", 18));

    // Approve deposits
    await dai.connect(alice).approve(lending.target, parseUnits("1000", 18));
    await usdc.connect(owner).approve(lending.target, parseUnits("500", 18));
  });

  it("Allows deposit and borrow", async () => {
    await lending.connect(alice).deposit(dai.target, parseUnits("100", 18));
    const deposit = await lending.getDeposit(alice.address, dai.target);
    expect(deposit).to.equal(parseUnits("100", 18));

    await lending.connect(alice).borrow(usdc.target, parseUnits("50", 18));
    const borrow = await lending.getBorrow(alice.address, usdc.target);
    expect(borrow).to.be.closeTo(parseUnits("50", 18), parseUnits("0.001", 18));
  });

  it("Prevents undercollateralized borrow", async () => {
    await lending.connect(alice).deposit(dai.target, parseUnits("10", 18));
    await expect(
      lending.connect(alice).borrow(usdc.target, parseUnits("20", 18))
    ).to.be.revertedWithCustomError(lending, "HealthFactorTooLow");
  });

  it("Accrues interest over time", async () => {
    await lending.connect(alice).deposit(dai.target, parseUnits("100", 18));
    await lending.connect(alice).borrow(usdc.target, parseUnits("50", 18));

    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]); // 1 year
    await usdc.connect(alice).approve(lending.target, parseUnits("1", 18));
    await lending.connect(alice).repay(usdc.target, parseUnits("1", 18)); // triggers interest accrual

    const newDebt = await lending.getBorrow(alice.address, usdc.target);
    expect(newDebt).to.be.gt(parseUnits("50", 18));
  });

  it("Triggers liquidation correctly", async () => {
    await lending.connect(alice).deposit(dai.target, parseUnits("100", 18));
    await lending.connect(alice).borrow(usdc.target, parseUnits("60", 18));

    // Drop DAI price to $0.60 to trigger undercollateralization
    await DAI_PRICE_FEED.setPrice(parseUnits("0.60", 8));

    const preReward = await dai.balanceOf(bob.address);

    // Bob liquidates Alice's position
    // Bob needs to cover the borrowed amount plus interest
    await usdc.transfer(bob.address, parseUnits("31", 18));
    // Approve 31 USDC to cover liquidation to include accrued interest
    await usdc.connect(bob).approve(lending.target, parseUnits("31", 18));
    await lending.connect(bob).liquidate(alice.address, usdc.target, dai.target);

    const postReward = await dai.balanceOf(bob.address);
    expect(postReward).to.be.gt(preReward);
  });

  it("Restricts withdrawals that would break health factor", async () => {
    await lending.connect(alice).deposit(dai.target, parseUnits("100", 18));
    await lending.connect(alice).borrow(usdc.target, parseUnits("60", 18));

    await expect(
      lending.connect(alice).withdraw(dai.target, parseUnits("90", 18))
    ).to.be.revertedWithCustomError(lending, "HealthFactorTooLow");
  });

  it("Pauses and unpauses contract", async () => {
    await lending.connect(owner).pause();
    await expect(
    lending.connect(alice).deposit(dai.target, parseUnits("1", 18))
    ).to.be.reverted;

    await lending.connect(owner).unpause();
    await lending.connect(alice).deposit(dai.target, parseUnits("1", 18));
  });
});
