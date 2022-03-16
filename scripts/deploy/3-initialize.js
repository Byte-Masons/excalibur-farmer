async function main() {
  const vaultAddress = '0x69e4F9d39e03959F6bf5a8EF7f481a1cb2B09893';
  const strategyAddress = '0x4d37e3901C656adC24c89c2C08e078d9f188201F';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');
  const vault = Vault.attach(vaultAddress);

  const options = { gasPrice: 200000000000, gasLimit: 9000000 };
  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
