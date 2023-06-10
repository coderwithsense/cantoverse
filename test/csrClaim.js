const expect = require('chai').expect;

describe('csrClaim.sol', async function () {
  let signers;
  let turnstile, csrCanto, csrClaim;

  before(async function () {
    const s = await ethers.getSigners();
    signers = { god: s[0], owner: s[1], alice: s[2] };

    const Turnstile = await ethers.getContractFactory('contracts/mock/Turnstile.sol:Turnstile');
    const CsrCanto = await ethers.getContractFactory('CsrCanto');
    const CsrClaim = await ethers.getContractFactory('wallet');

    console.log('Deploying mock/Turnstile.sol ...');
    turnstile = await Turnstile.connect(signers.god).deploy();
    await turnstile.deployed();
    console.log('Done.');

    console.log('Deploying mock/CsrCanto.sol ...');
    csrCanto = await CsrCanto.connect(signers.god).deploy(turnstile.address);
    await csrCanto.deployed();
    console.log('Done.');

    console.log('Deploying CsrClaim.sol ...');
    csrClaim = await CsrClaim.connect(signers.owner).deploy(csrCanto.address);
    await csrClaim.deployed();
    console.log('Done.');
  });

  describe('contract ownership', async function () {
    it('set default ownership to the deployer address', async () => {
      expect(await csrClaim.owner.call()).to.equal(signers.owner.address);
    });
    
    it('revert when changing ownership to zero address', async () => {
      expect(csrClaim.connect(signers.owner).changeOwner(ethers.constants.AddressZero)).to.be.revertedWith('Invalid new owner address');
    });
    
    it('change ownership to Alice', async () => {
      await csrClaim.connect(signers.owner).changeOwner(signers.alice.address);
      expect(await csrClaim.owner.call()).to.equal(signers.alice.address);
    });
    
    it('revert change ownership by non-owner', async () => {
      expect(csrClaim.connect(signers.owner).changeOwner(signers.god.address)).to.be.reverted;
    });
    
    it('change ownership back from Alice to Owner', async () => {
      await csrClaim.connect(signers.alice).changeOwner(signers.owner.address);
      expect(await csrClaim.owner.call()).to.equal(signers.owner.address);
    });
  });
});
