const expect = require('chai').expect;

describe('csrClaim.sol', async function () {
  let signers;
  let turnstile, csrCanto, csrClaim;

  before(async function () {
    console.log('\n[ Mockup environment initialization ... ]\n');

    const s = await ethers.getSigners();
    signers = { 
      god: s[0],
      abraxas: s[1],
      cantoverse: s[2], 
      alice: s[3]
    };

    const Turnstile = await ethers.getContractFactory('contracts/mock/Turnstile.sol:Turnstile');
    const CsrCanto = await ethers.getContractFactory('CsrCanto');
    const CsrClaim = await ethers.getContractFactory('wallet');

    console.log('1. contracts deployment...');
    turnstile = await Turnstile.connect(signers.god).deploy();
    await turnstile.deployed();
    console.log('1.1. 0xGod deployed mock/Turnstile.sol');

    csrCanto = await CsrCanto.connect(signers.abraxas).deploy(turnstile.address);
    await csrCanto.deployed();
    console.log('1.2. 0xAbraxas deployed mock/CsrCanto.sol');

    csrClaim = await CsrClaim.connect(signers.cantoverse).deploy(csrCanto.address);
    await csrClaim.deployed();
    console.log('1.3. 0xCantoverse deployed CsrClaim.sol');
    console.log('Done.\n')

    console.log('2. contracts initialization...');
    await csrCanto.connect(signers.abraxas).m_addClaimer(csrClaim.address);
    console.log('2.1. 0xAbraxas added CsrClaim contract to the $csrCANTO holders eligible for CSR claiming');

    console.log('Done.\n'); // empty new line
  });

  describe('contract ownership', async function () {
    it('set default ownership to the deployer address', async () => {
      expect(await csrClaim.owner.call()).to.equal(signers.cantoverse.address);
    });
    
    it('revert when changing ownership to zero address', async () => {
      expect(csrClaim.connect(signers.cantoverse).changeOwner(ethers.constants.AddressZero)).to.be.revertedWith('Invalid new owner address');
    });
    
    it('change ownership to Alice', async () => {
      await csrClaim.connect(signers.cantoverse).changeOwner(signers.alice.address);
      expect(await csrClaim.owner.call()).to.equal(signers.alice.address);
    });
    
    it('revert change ownership by non-owner', async () => {
      expect(csrClaim.connect(signers.cantoverse).changeOwner(signers.god.address)).to.be.reverted;
    });
    
    it('change ownership back from Alice to Cantoverse', async () => {
      await csrClaim.connect(signers.alice).changeOwner(signers.cantoverse.address);
      expect(await csrClaim.owner.call()).to.equal(signers.cantoverse.address);
    });
  });
});
