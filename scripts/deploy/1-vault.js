async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_3');

  const wantAddress = '0xfA54BD05a1Aeaf66031a97a212981e8B35f88cD2';
  const tokenName = 'USDC-UST Excalibur Crypt';
  const tokenSymbol = 'rf-EXC-V1-USDC-UST';
  const depositFee = 200;
  const tvlCap = ethers.utils.parseEther('2000');
  const options = { gasPrice: 300000000000, gasLimit: 9000000 };

  const vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, depositFee, tvlCap, options);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
