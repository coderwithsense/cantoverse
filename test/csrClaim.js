const expect = require('chai').expect;

describe('csrClaim.sol', async function () {
  before(async function () {
    const s = await ethers.getSigners();
    const signers = {
      god: s[0]
    };

    console.log('Deploying mock/Turnstile.sol ...');
    const Turnstile = await ethers.getContractFactory('contracts/mock/Turnstile.sol:Turnstile');
    const turnstile = await Turnstile.connect(signers.god).deploy();
    await turnstile.deployed();
    console.log('Done.');

    console.log('Deploying mock/CsrCanto.sol ...');
    const CsrCanto = await ethers.getContractFactory('CsrCanto');
    const csrCanto = await CsrCanto.connect(signers.god).deploy(turnstile.address);
    await csrCanto.deployed();
    console.log('Done.');
  });

  it('should be true', () => {
    expect(true).to.equal(true);
  });
});
