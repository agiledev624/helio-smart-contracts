const {ethers, upgrades} = require('hardhat')
const hre = require('hardhat')
const contractAddresses = require("./contract_address.json");
const {transferProxyAdminOwner} = require("../upgrades/utils/upgrade_utils");
const path = require("path");
const fs = require("fs");
const {addCollateral} = require('../utils/add_collateral')

// Global Variables
let rad = '000000000000000000000000000000000000000000000' // 45 Decimals

async function main() {

    const [deployer] = await ethers.getSigners()
    let NEW_OWNER = '0xAca0ed4651ddA1F43f00363643CFa5EBF8774b37'
    let PROXY_ADMIN_OWNER = '0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253'
    let oracleName = 'PumpBtcOracle';
    let oracleInitializeArgs = [];
    let oracleInitializer = 'initialize';

    const symbol = 'cePumpBTC'
    let tokenAddress = '0xc6F28a668b7c18F921ccBA4adc3D8db72BFF0FE2' // cePumpBTC token address on BSC Mainnet

    if (hre.network.name === 'bsc_testnet') {
        NEW_OWNER = process.env.OWNER || deployer.address
        PROXY_ADMIN_OWNER = process.env.PROXY_ADMIN_OWNER || deployer.address
        // testnet token address
        tokenAddress = '0xF95144b8aeFeeD7cBea231D24Be53766223Ad5f0'
    }

    // add collateral
    await addCollateral({
        symbol,
        tokenAddress,
        oracleName,
        oracleInitializeArgs,
        oracleInitializer,
        owner: NEW_OWNER,
        proxyAdminOwner: PROXY_ADMIN_OWNER,
        clipperBuf: '1100000000000000000000000000',
        clipperTail: '10800',
        clipperCusp: '600000000000000000000000000',
        clipperChip: '0',
        clipperTip: '5' + rad,
        clipperStopped: '0'
    })
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })