const hre = require("hardhat");
const {ethers, upgrades} = require("hardhat");
const {ether} = require("@openzeppelin/test-helpers");

///////////////////////////////////////////////////////////////////////////////////
// Note: This script is meant to be used before full release. Not for production.//
///////////////////////////////////////////////////////////////////////////////////

// Global Variables
let wad = "000000000000000000", // 18 Decimals
    ray = "000000000000000000000000000", // 27 Decimals
    rad = "000000000000000000000000000000000000000000000"; // 45 Decimals

async function main() {

  // Declare and load network variables from networkVars.json
  let ilkCE = "";

  // Contracts Fetching
  this.Vat = await hre.ethers.getContractFactory("Vat");
  this.Dog = await hre.ethers.getContractFactory("Dog");
  this.Clip = await hre.ethers.getContractFactory("Clipper");
  this.Abaci = await hre.ethers.getContractFactory("LinearDecrease");
  // this.Vow = await hre.ethers.getContractFactory("Vow");

  let vat = await this.Vat.attach("");
  let dog = await this.Dog.attach("");
  let clipCE = await this.Clip.attach("");
  let abaci = await this.Abaci.attach("");
  // let vow = await this.Vow.attach("");

  // Variables Update
  console.log("Vat Update...");
  await vat["file(bytes32,uint256)"](ethers.utils.formatBytes32String("Line"), "5000000" + rad);
  await vat["file(bytes32,bytes32,uint256)"](ilkCE, ethers.utils.formatBytes32String("line"), "5000000" + rad);
  await vat["file(bytes32,bytes32,uint256)"](ilkCE, ethers.utils.formatBytes32String("dust"), "100" + ray);

  console.log("Dog Update...");
  await dog["file(bytes32,uint256)"](ethers.utils.formatBytes32String("Hole"), "50000000" + rad);
  await dog["file(bytes32,bytes32,uint256)"](ilkCE, ethers.utils.formatBytes32String("hole"), "50000000" + rad);
  await dog["file(bytes32,bytes32,uint256)"](ilkCE, ethers.utils.formatBytes32String("chop"), "1100000000000000000"); // 10%

  console.log("Clip Update...");
  await clipCE["file(bytes32,uint256)"](ethers.utils.formatBytes32String("buf"), "1100000000000000000000000000"); // 10%
  await clipCE["file(bytes32,uint256)"](ethers.utils.formatBytes32String("tail"), "10800"); // 3h reset time
  await clipCE["file(bytes32,uint256)"](ethers.utils.formatBytes32String("cusp"), "600000000000000000000000000"); // 60% reset ratio
  await clipCE["file(bytes32,uint256)"](ethers.utils.formatBytes32String("chip"), "100000000000000"); // 0.01% from vow incentive
  await clipCE["file(bytes32,uint256)"](ethers.utils.formatBytes32String("tip"), "10" + rad); // 10$ flat fee incentive

  console.log("Abaci Update...");
  await abaci.file(ethers.utils.formatBytes32String("tau"), "36000");

  // console.log("Vow Update...");
  // await vow["file(bytes32,uint256)"](ethers.utils.formatBytes32String("hump"), "0" + rad);
  
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });