require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const ALCHEMY_API_KEY = 'JSASkuvN8nvcFpSeT1eu0E1FPNh7tvtT';
// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4"
      },
      {
        version: "0.8.3"
      }
    ]
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    ropsten: {
      url: `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      accounts: [`0xa2a5ea50cd7b6a6a3fd0939680c24bcf57015fc3a522478478d231b41850d529`]
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: '1CKR5GQJMP1R6K2HXSSQCYH1XZSZHTDC8F'
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 21
  }
};

