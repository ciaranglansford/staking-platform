const { ethers, network } = require("hardhat");

async function main() {
  const [owner, user1, user2] = await ethers.getSigners();

  // ========== Deploy MTKN ==========
  const FeedMTKN = await ethers.getContractFactory("MockV3Aggregator");
  const feedMTKN = await FeedMTKN.deploy(ethers.parseUnits("1000", 8), 8);
  await feedMTKN.waitForDeployment();
  console.log("✅ MTKN price feed deployed at:", feedMTKN.target);

  const Token = await ethers.getContractFactory("ERC20Mock");
  const tokenMKTN = await Token.deploy("Mock Token", "MTKN", owner.address, ethers.parseUnits("100000", 18));
  await tokenMKTN.waitForDeployment();
  console.log("✅ MTKN deployed at:", tokenMKTN.target);

  // ========== Deploy USDC ==========
  const FeedUSDC = await ethers.getContractFactory("MockV3Aggregator");
  const feedUSDC = await FeedUSDC.deploy(ethers.parseUnits("1", 8), 8); // USDC = $1
  await feedUSDC.waitForDeployment();
  console.log("✅ USDC price feed deployed at:", feedUSDC.target);

  const tokenUSDC = await Token.deploy("USD Coin", "USDC", owner.address, ethers.parseUnits("1000000", 18));
  await tokenUSDC.waitForDeployment();
  console.log("✅ USDC deployed at:", tokenUSDC.target);

  // ========== Deploy Lending Contract ==========
  const Lending = await ethers.getContractFactory("Lending");
  const lending = await Lending.deploy();
  await lending.waitForDeployment();
  console.log("✅ Lending contract deployed at:", lending.target);

  // ========== List Tokens ==========
  await lending.listToken(tokenMKTN.target, feedMTKN.target, 8000); // 80% collateral
  await lending.listToken(tokenUSDC.target, feedUSDC.target, 8000);
  console.log("✅ Both tokens listed");

  // ========== Fund Lending Pool with USDC ==========
  await tokenUSDC.transfer(lending.target, ethers.parseUnits("80000", 18));
  console.log("🏦 Lending pool funded with 80K USDC");

  // ========== Distribute MTKN to users ==========
  const userAmount = ethers.parseUnits("1000", 18);
  await tokenMKTN.transfer(user1.address, userAmount);
  await tokenMKTN.transfer(user2.address, userAmount);
  console.log("✅ Distributed 1000 MTKN to user1 and user2");

  // ========== User1 deposits MTKN ==========
  const depositAmount = ethers.parseUnits("100", 18);
  await tokenMKTN.connect(user1).approve(lending.target, depositAmount);
  await lending.connect(user1).deposit(tokenMKTN.target, depositAmount);
  console.log("✅ User1 deposited 100 MTKN");

  // ========== User1 borrows USDC ==========
  const borrowAmount = ethers.parseUnits("75000", 18);
  await lending.connect(user1).borrow(tokenUSDC.target, borrowAmount);
  console.log("✅ User1 borrowed 75000 USDC");

  // ========== Simulate 30 Days Passing ==========
  console.log("⏳ Advancing time by 30 days...");
  await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 30]);
  await network.provider.send("evm_mine");

  // ========== Trigger interest accrual ==========
  await tokenUSDC.connect(user1).approve(lending.target, ethers.parseUnits("0.0001", 18));
  await lending.connect(user1).repay(tokenUSDC.target, ethers.parseUnits("0.00001", 18));
  console.log("✅ Interest accrued");

  const hfAfterInterest = await lending.healthFactor(user1.address);
  console.log("🧮 Health Factor after interest:", ethers.formatUnits(hfAfterInterest, 18));

  // ========== Drop MTKN Price to Simulate Devaluation ==========
  await feedMTKN.setPrice(ethers.parseUnits("500", 8)); // Drop from $1000 → $400
  console.log("🔻 MTKN price dropped to $500");

  const hfAfterPriceDrop = await lending.healthFactor(user1.address);
  console.log("🧮 Health Factor after price drop:", ethers.formatUnits(hfAfterPriceDrop, 18));

  // ========== Liquidation Attempt ==========
  if (hfAfterPriceDrop < ethers.parseUnits("1", 18)) {
    console.log("⚠️  User1 is insolvent — proceeding with liquidation");

    const victimDebt = await lending.getBorrow(user1.address, tokenUSDC.target);
    const halfDebt = victimDebt / 2n;
    const buffer = halfDebt / 100n; // Add 1% buffer
    const approvalAmount = halfDebt + buffer;

    console.log("🔍 HalfDebt to repay:", ethers.formatUnits(halfDebt, 18));
    console.log("🔍 Approving:", ethers.formatUnits(approvalAmount, 18));

    await tokenUSDC.transfer(user2.address, approvalAmount);
    await tokenUSDC.connect(user2).approve(lending.target, approvalAmount);

    await lending.connect(user2).liquidate(user1.address, tokenUSDC.target, tokenMKTN.target);
    console.log("⚡ User2 successfully liquidated user1");
    } else {
    console.log("✅ User1 is still solvent — no liquidation performed");
    }


    // ========== Final Balances ==========

    const deposit1 = await lending.getDeposit(user1.address, tokenMKTN.target);
    const borrow1 = await lending.getBorrow(user1.address, tokenUSDC.target);
    const deposit2 = await lending.getDeposit(user2.address, tokenMKTN.target);
    const borrow2 = await lending.getBorrow(user2.address, tokenUSDC.target);

    const balanceMTKN1 = await tokenMKTN.balanceOf(user1.address);
    const balanceMTKN2 = await tokenMKTN.balanceOf(user2.address);
    const balanceUSDC1 = await tokenUSDC.balanceOf(user1.address);
    const balanceUSDC2 = await tokenUSDC.balanceOf(user2.address);

    const contractMTKN = await tokenMKTN.balanceOf(lending.target);
    const contractUSDC = await tokenUSDC.balanceOf(lending.target);

    const hfUser1 = await lending.healthFactor(user1.address);
    const hfUser2 = await lending.healthFactor(user2.address);

    // ========== Logging ==========

    console.log("\n📊 Final Balances:");

    console.log("👤 User1:");
    console.log("   📥 Deposit (MTKN):", ethers.formatUnits(deposit1, 18));
    console.log("   📤 Borrow  (USDC):", ethers.formatUnits(borrow1, 18));
    console.log("   💰 Wallet  (MTKN):", ethers.formatUnits(balanceMTKN1, 18));
    console.log("   💰 Wallet  (USDC):", ethers.formatUnits(balanceUSDC1, 18));
    console.log("   🧮 Health Factor:", ethers.formatUnits(hfUser1, 18));

    console.log("👤 User2:");
    console.log("   📥 Deposit (MTKN):", ethers.formatUnits(deposit2, 18));
    console.log("   📤 Borrow  (USDC):", ethers.formatUnits(borrow2, 18));
    console.log("   💰 Wallet  (MTKN):", ethers.formatUnits(balanceMTKN2, 18));
    console.log("   💰 Wallet  (USDC):", ethers.formatUnits(balanceUSDC2, 18));
    console.log("   🧮 Health Factor:", ethers.formatUnits(hfUser2, 18));

    console.log("🏦 Lending Contract Reserves:");
    console.log("   💼 MTKN:", ethers.formatUnits(contractMTKN, 18));
    console.log("   💼 USDC:", ethers.formatUnits(contractUSDC, 18));

    // ========== Optional Protocol Logs ==========
    if (lending.totalDeposits) {
    const totalDeposits = await lending.totalDeposits(tokenMKTN.target);
    console.log("📈 Protocol Total Deposits (MTKN):", ethers.formatUnits(totalDeposits, 18));
    }
    if (lending.totalBorrows) {
    const totalBorrows = await lending.totalBorrows(tokenUSDC.target);
    console.log("📉 Protocol Total Borrows (USDC):", ethers.formatUnits(totalBorrows, 18));
    }

    // ========== Invariant Checks ==========

    if (hfUser1 < ethers.parseUnits("1", 18)) {
    console.warn("🚨 User1 remains insolvent after liquidation!");
    } else {
    console.log("✅ User1 health factor is above 1 after liquidation.");
    }

    if (borrow1 < ethers.parseUnits("75000", 18)) {
    const repaid = ethers.parseUnits("75000", 18) - borrow1;
    console.log("💥 Liquidation reduced debt by:", ethers.formatUnits(repaid, 18), "USDC");
    } else {
    console.warn("❌ No debt reduction detected — liquidation may not have executed properly.");
    }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
