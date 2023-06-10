// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

/*
   _                
  | |                ██████  █████  ███    ██ ████████  ██████  
 / __) ___ ___ _ __ ██      ██   ██ ████   ██    ██    ██    ██ 
 \__ \/ __/ __| '__|██      ███████ ██ ██  ██    ██    ██    ██ 
 (   / (__\__ \ |   ██      ██   ██ ██  ██ ██    ██    ██    ██ 
  |_| \___|___/_|    ██████ ██   ██ ██   ████    ██     ██████  
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface Turnstile {
    function register(address) external returns(uint256);
    function getTokenId(address _smartContract) external view returns (uint256);
    function withdraw(uint256 _tokenId, address _recipient, uint256 _amount) external returns (uint256);
    function balances(uint256 _tokenId) external view returns (uint256);
}

contract CsrCanto is ERC20, Pausable, ReentrancyGuard {
    uint256 constant maxProtocolFee = 5000; // Permyriad (x/10,000)
    Turnstile immutable turnstile;
    uint256 public immutable turnstileTokenId;

    /*=====================================
    =            CONFIGURABLES            =
    =====================================*/
    string private _name = "CSR (wrapped) Canto";
    string private _symbol = "csrCANTO";
    address public ADMIN_ROLE;
    address public MANAGER_ROLE;
    address public protocolFeePayee;
    bool public hasUnwrapFee = false;
    bool public hasClaimFee = false;
    uint256 public claimDelay = 0;
    uint256 public protocolFee = 0;

    /*================================
    =            DATASETS            =
    ================================*/
    struct holder {
        uint256 lastTimeClaimed;
        bool isClaimer;
        /* Token Holders CSR Payments */
        // claimed but not yet withdrawn funds for a user
        uint256 claimedFunds;
        // cumulative funds received which were already processed for distribution - by user
        uint256 processedFunds;
    }
    mapping(address => holder) public holders;
    uint256 public claimersTotalSupply = 0;
    uint256 public receivedFunds; // cumulative funds received by this contract

    /*==============================
    =            EVENTS            =
    ==============================*/
    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event Register(address account);
    event Claim(address indexed account, uint256 claimed, uint256 protocolFee);
    event ContractReceived(address from, uint256 amount);
    event PullFundsFromTurnstile(address from, uint256 amount);

    /*=======================================================
    =        TOKEN HOLDERS CSR PAYMENTS MECHANISM           =
    =======================================================*/

    receive() external payable {
        require(msg.sender == address(turnstile), "accept receiving plain $CANTO transfers only from turnstile contract");
        emit ContractReceived(msg.sender, msg.value);
    }

    function _claimFunds(address _forAddress) internal {
        uint256 unprocessedFunds = _calcUnprocessedFunds(_forAddress);

        holders[_forAddress].processedFunds = receivedFunds;
        holders[_forAddress].claimedFunds += unprocessedFunds;
    }

    function _prepareWithdraw() internal returns(uint256){
        uint256 withdrawableFunds = availableFunds(msg.sender);

        holders[msg.sender].processedFunds = receivedFunds;
        holders[msg.sender].claimedFunds = 0;

        return withdrawableFunds;
    }

    function _calcUnprocessedFunds(address _forAddress) internal view returns (uint256) {
        if(holders[_forAddress].isClaimer == false) return 0;
        uint256 newReceivedFunds = receivedFunds - holders[_forAddress].processedFunds;
        return balanceOf(_forAddress) * newReceivedFunds / claimersTotalSupply;
    }

    /*
     * ERC20 overrides 
     */

    function transfer(address _to, uint256 _value)
        public override
        returns (bool)
    {
        _claimFunds(msg.sender);
        _claimFunds(_to);

        return super.transfer(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value)
        public override
        returns (bool)
    {
        _claimFunds(_from);
        _claimFunds(_to);

        return super.transferFrom(_from, _to, _value);
    }

    function _afterTokenTransfer (
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if(holders[from].isClaimer) claimersTotalSupply -= amount;
        if(holders[to].isClaimer) claimersTotalSupply += amount;
    }

    /* 
     * public functions 
     */

    function pullFundsFromTurnstile() public {
        uint256 amount = turnstile.balances(turnstileTokenId);
        if(amount > 0){
            turnstile.withdraw(turnstileTokenId, payable(address(this)), amount);
            _mint(address(this), amount);
            receivedFunds += amount; // register funds
            emit PullFundsFromTurnstile(msg.sender, amount);
        }
    }

    function availableFunds(address _forAddress) public view returns(uint256) {
        return _calcUnprocessedFunds(_forAddress) + holders[_forAddress].claimedFunds;
    }

    function getAmountClaimable(address addr) public view returns(uint256) {
        if(holders[addr].isClaimer == true && claimersTotalSupply > 0){
            /* dry run pullFundsFromTurnstile */
            uint256 simulate_receivedFunds = receivedFunds;
            uint256 amount = turnstile.balances(turnstileTokenId);
            simulate_receivedFunds += amount;

            /* dry run _calcUnprocessedFunds() */
            uint256 newReceivedFunds = simulate_receivedFunds - holders[addr].processedFunds;
            uint256 simulate_calcUnprocessedFunds_returns = balanceOf(addr) * newReceivedFunds / claimersTotalSupply;

            /* dry run availableFunds() */
            uint256 withdrawnClaim = simulate_calcUnprocessedFunds_returns + holders[addr].claimedFunds;
            uint256 fee = 0;
            
            if(hasClaimFee){
                (withdrawnClaim, fee) = feeSplit(withdrawnClaim);
            }

            return withdrawnClaim;
        }
        else
            return 0;
    }

    /*=======================================
    =            PUBLIC FUNCTIONS           =
    =======================================*/

    constructor(address turnstileAddr) ERC20(_name, _symbol) {
        ADMIN_ROLE = msg.sender;
        MANAGER_ROLE = msg.sender;
        protocolFeePayee = msg.sender;

        turnstile = Turnstile(turnstileAddr);
        turnstile.register(address(this));
        turnstileTokenId = turnstile.getTokenId(address(this));
    }

    function name() public view override returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol; }
    
    /* wrap CANTO to $csrCANTO -.
                               \*/
    function deposit() public payable whenNotPaused {
        _mint(msg.sender, msg.value);
        holders[msg.sender].lastTimeClaimed = block.timestamp; // reset claim delay to prevent whale attack

        _claimFunds(msg.sender);
        emit Deposit(msg.sender, msg.value);
    }

    /* unwrap $csrCANTO to CANTO -.
                                 \*/
    function withdraw(uint256 amount) public nonReentrant whenNotPaused {
        require(this.balanceOf(msg.sender) >= amount, "insufficient balance");

        if(hasUnwrapFee) {
            (uint256 withdrawn, uint256 fee) = feeSplit(amount);
            _transfer(msg.sender, protocolFeePayee, fee);
            _burn(msg.sender, withdrawn);
            payable(msg.sender).transfer(withdrawn);
        }
        else {
            _burn(msg.sender, amount);
            payable(msg.sender).transfer(amount);
        }

        emit Withdraw(msg.sender, amount);
    }

    /* Register to be able to claim Turnstile revenue (EOA only) -.
                                                                 \*/
    function register() public {
        require(tx.origin == msg.sender, "Registrant must be an EOA");
        require(!holders[msg.sender].isClaimer, "Already registered as a claimer");

        holders[msg.sender].isClaimer = true;
        holders[msg.sender].lastTimeClaimed = block.timestamp;
        claimersTotalSupply += balanceOf(msg.sender);
        
        emit Register(msg.sender);
    }

    /* claim $CANTO from Turnstile, gets rewarded in $csrCANTO (claimer only) -.
                                                                              \*/
    function withdrawClaimed() public nonReentrant whenNotPaused {
        require(holders[msg.sender].isClaimer == true, "not in the claimers list");
        require(block.timestamp >= holders[msg.sender].lastTimeClaimed + claimDelay, "claim delay not met");

        pullFundsFromTurnstile();
        uint256 withdrawnClaim = _prepareWithdraw();
        uint256 fee = 0;
        if(hasClaimFee){
            (withdrawnClaim, fee) = feeSplit(withdrawnClaim);
            payable(msg.sender).transfer(withdrawnClaim);
            payable(protocolFeePayee).transfer(fee);
        }
        else{
            payable(msg.sender).transfer(withdrawnClaim);
        }

        _burn(address(this), withdrawnClaim + fee);
        holders[msg.sender].lastTimeClaimed = block.timestamp;

        emit Claim(msg.sender, withdrawnClaim, fee);
    }

    /*==============================
    =            GETTERS           =
    ==============================*/
    function getRemainingTimeBeforeCanClaim(address addr) public view returns(uint256) {
        require(holders[msg.sender].isClaimer == true);

        uint256 claimedSince = block.timestamp - holders[addr].lastTimeClaimed;
        return claimedSince < claimDelay ? claimDelay - claimedSince : 0;
    }

    function feeSplit(uint256 amount) private view returns(uint256, uint256){
        uint256 fee = amount * protocolFee / 10_000;
        uint256 user = amount - fee;
        require(amount == user + fee, "Calculation error");
        return(user, fee);
    }

    /*=======================================
    =            ADMIN FUNCTIONS            =
    =======================================*/
    function a_setAdminRole(address addr) public onlyAdmin { 
        require(addr != address(0), "0x00... cannot be Admin");
        ADMIN_ROLE = addr;
    }
    function a_setManagerRole(address addr) public onlyAdmin { 
        require(addr != address(0), "0x00... cannot be Manager");
        MANAGER_ROLE = addr;
    }
    function a_setPayee(address addr) public onlyAdmin {
        require(addr != address(0), "0x00... cannot be protocolFeePayee");
        protocolFeePayee = addr;
    }
    function a_toggleHasUnwrapFee() public onlyAdmin { hasUnwrapFee = hasUnwrapFee ? false : true; }
    function a_toggleHasClaimFee() public onlyAdmin { hasClaimFee = hasClaimFee ? false : true; }
    function a_setClaimDelay(uint256 blocksrange) public onlyAdmin { claimDelay = blocksrange; }
    function a_setProtocolFee(uint256 permyriad) public onlyAdmin {
        require(permyriad <= maxProtocolFee, "protocol fee too high");
        protocolFee = permyriad;
    }
    function a_setName(string calldata __name) public onlyAdmin { _name = __name; }
    function a_setSymbol(string calldata __symbol) public onlyAdmin { _name = __symbol; }
    
    function a_pause() public onlyAdmin { _pause(); }
    function a_unpause() public onlyAdmin { _unpause(); }

    /*=======================================
    =            MANAGER FUNCTIONS          =
    =======================================*/
    function m_addClaimer(address addr) public onlyManager {
        require(!holders[addr].isClaimer, "address already in the claimers list");
        holders[addr].isClaimer = true;
        claimersTotalSupply += balanceOf(addr);
    }
    function m_delClaimer(address addr) public onlyManager {
        require(holders[addr].isClaimer, "address already not claimer");
        delete holders[addr].isClaimer;
        claimersTotalSupply -= balanceOf(addr);
    }

    /*==============================
    =          MODIFIERS           =
    ==============================*/
    modifier onlyAdmin() {
        require(msg.sender == ADMIN_ROLE);
        _;
    }
    modifier onlyManager() {
        require(msg.sender == MANAGER_ROLE);
        _;
    }
}