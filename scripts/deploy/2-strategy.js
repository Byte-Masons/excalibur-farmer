const hre = require('hardhat');

async function main() {
  const vaultAddress = '0x32Cf4C6070a97cf26137e69dcD42527E1AbCA1eC';

  const Strategy = await ethers.getContractFactory('ReaperAutoCompoundExcaliburFarmer');
  const treasuryAddress = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
  const strategist1 = '0x1E71AEE6081f62053123140aacC7a06021D77348';
  const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  const wantAddress = '0x66402fdF9CF83Cdd54bfBB231162eEdA1B611925';
  const poolId = 2;

  const strategy = await hre.upgrades.deployProxy(
    Strategy,
    [
      vaultAddress,
      [treasuryAddress, paymentSplitterAddress],
      [strategist1, strategist2, strategist3],
      wantAddress,
      poolId,
    ],
    { kind: 'uups', timeout: 0, gasPrice: 300000000000, gasLimit: 9000000 },
  );
  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
