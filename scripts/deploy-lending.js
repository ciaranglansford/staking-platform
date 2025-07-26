const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying Lending contract with account:", deployer.address);

  const Lending = await hre.ethers.getContractFactory("Lending");
  const lending = await Lending.deploy();
  await lending.waitForDeployment();

  console.log("Lending deployed to:", await lending.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
