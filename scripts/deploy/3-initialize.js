async function main() {
  const vaultAddress = '0x583F3BD4675ED44D6727539A384EBa50d0d072d7';
  const strategyAddress = '0x1111709C13c97AAf5fd4cCB8A11B78682c064b46';

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
