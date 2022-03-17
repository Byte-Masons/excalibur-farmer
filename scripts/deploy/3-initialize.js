async function main() {
  const vaultAddress = '0x32Cf4C6070a97cf26137e69dcD42527E1AbCA1eC';
  const strategyAddress = '0xe336dCfaE19DdE1F4D3bCf5Da45662216d3f09fE';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);

  const options = { gasPrice: 300000000000, gasLimit: 9000000 };
  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
