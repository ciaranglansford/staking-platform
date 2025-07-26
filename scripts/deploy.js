const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contracts with account: ${deployer.address}`);

  // 1. Deploy Reward Token (1,000,000 RWT)
  const RewardToken = await ethers.getContractFactory("RewardToken");
  const rewardToken = await RewardToken.deploy(ethers.parseUnits("1000000", 18));
  await rewardToken.waitForDeployment();
  console.log(`✅ RewardToken deployed at: ${await rewardToken.getAddress()}`);

  // 2. Deploy Staking Token (1,000,000 STK)
  const StakingToken = await ethers.getContractFactory("StakingToken");
  const stakingToken = await StakingToken.deploy(ethers.parseUnits("1000000", 18));
  await stakingToken.waitForDeployment();
  console.log(`✅ StakingToken deployed at: ${await stakingToken.getAddress()}`);

  // 3. Deploy MasterChef
  const rewardPerSec = ethers.parseUnits("1", 18); // 1 RWT per second
  const currentTime = Math.floor(Date.now() / 1000); // current Unix timestamp

  const MasterChef = await ethers.getContractFactory("MasterChef");
  const masterChef = await MasterChef.deploy(
    await rewardToken.getAddress(),
    rewardPerSec,
    currentTime
  );
  await masterChef.waitForDeployment();
  console.log(`✅ MasterChef deployed at: ${await masterChef.getAddress()}`);

  // 4. Transfer 500,000 RWT to MasterChef contract
  const fundingAmount = ethers.parseUnits("500000", 18);
  const transferTx = await rewardToken.transfer(await masterChef.getAddress(), fundingAmount);
  await transferTx.wait();
  console.log(`✅ Transferred ${ethers.formatUnits(fundingAmount, 18)} RWT to MasterChef`);

  // 5. Approve staking token for the deployer (optional: for testing)
  const approvalTx = await stakingToken.approve(await masterChef.getAddress(), ethers.MaxUint256);
  await approvalTx.wait();

  // 6. Add staking pool to MasterChef (allocPoint = 100)
  const addTx = await masterChef.addPool(
    100,                                 // allocPoint
    await stakingToken.getAddress(),     // staking token
    true                                 // withUpdate
  );
  await addTx.wait();
  console.log(`✅ Pool added for staking token: ${await stakingToken.getAddress()}`);

  console.log("\n🚀 Deployment complete. Ready for local testing.");
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exit(1);
});