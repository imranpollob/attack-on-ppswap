// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";

// ERC Token Standard #20 Interface
abstract contract ERC20Interface { // five  functions and four implicit getters
    function totalSupply() public virtual view returns (uint);
    function balanceOf(address tokenOwner) public virtual view returns (uint balance);
    function allowance(address tokenOwner, address spender) public virtual view returns (uint remaining);
    function transfer(address to, uint rawAmt) public virtual returns (bool success);
    function approve(address spender, uint rawAmt) public virtual returns (bool success);
    function transferFrom(address from, address to, uint rawAmt) public virtual returns (bool success);

    event Transfer(address indexed from, address indexed to, uint rawAmt);
    event Approval(address indexed tokenOwner, address indexed spender, uint rawAmt);
}

// ----------------------------------------------------------------------------
// Safe Math Library
// ----------------------------------------------------------------------------
contract SafeMath {
    function safeAdd(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function safeSub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a); 
        c = a - b;
    } 
        
    function safeMul(uint a, uint b) internal pure returns (uint c) { 
        c = a * b; 
        require(a == 0 || c / a == b); 
    } 
        
    function safeDiv(uint a, uint b) internal pure returns (uint c) { 
        require(b > 0);
        c = a / b;
    }
}

contract PPSwap is ERC20Interface, SafeMath, VRFV2WrapperConsumerBase {
    string public constant name = "PPSwap";
    string public constant symbol = "PPS";
    uint8 public constant decimals = 18; // 18 decimals is the strongly suggested default, avoid changing it
    uint public constant _totalSupply = 1*10**9*10**18; // one billion 
    uint public lastOfferID = 0; // the genesis orderID
    uint public ppsPrice = 1;  // how many PPS can we buy with 1eth
    address payable trustAccount;
    address contractOwner;

    mapping(uint => mapping(string => address)) offers; // orderID, key, value
    mapping(uint => address payable) offerMakers;
    mapping(uint => mapping(string => uint)) offerAmts; // orderID, key, value
    mapping(uint => int8) offerStatus; // 1: created; 2= filled; 3=cancelled.

    mapping(address => uint) balances;       // two column table: owneraddress, balance
    mapping(address => mapping(address => uint)) allowed; // three column table: owneraddress, spenderaddress, allowance

    address constant linkAddress = 	0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant vrfWrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46;
    uint128 constant entryFees = 0.001 ether;
    uint32 constant callbackGasLimit = 1_000_000;
    uint32 constant numWords = 1;
    uint16 constant requestConfirmations = 3;

    uint guessNumber;
    uint randomNumber;
    
    event BuyPPS(uint ETHAmt, uint PPSAmt);
    event SellPPS(uint PPSAmt, uint ETHAmt);
    event RenounceOwnership(address oldOwner, address newOwner);

    event RandomNumber(uint number);
    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    constructor(address payable trustAcc) payable VRFV2WrapperConsumerBase(linkAddress, vrfWrapperAddress) { 
        contractOwner = msg.sender;
        trustAccount = trustAcc;
        balances[trustAccount] = _totalSupply; // The trustAccount has all PPS initially 
        emit Transfer(address(0), trustAccount, _totalSupply);
    }
    
    modifier onlyContractOwner(){
       require(msg.sender == contractOwner, "only the contract owner can call this function. ");
       _;
    }
    
    function renounceCwnership() onlyContractOwner() public {
        address oldOwner = contractOwner;
        contractOwner = address(this);
        emit RenounceOwnership(oldOwner, address(this));
    
    }

    function totalSupply() public override view returns (uint) {
        return _totalSupply;
    }

    // The contract does not accept ETH
    fallback() external payable  {
        revert();
    }  

    function balanceOf(address tokenOwner) public override view returns (uint balance) {
        return balances[tokenOwner];
    }
    
    function allowance(address tokenOwner, address spender) public override view returns (uint remaining) {
        return allowed[tokenOwner][spender];
    }

    // called by the owner
    function approve(address spender, uint rawAmt) public override returns (bool success) {
        allowed[msg.sender][spender] = rawAmt;
        emit Approval(msg.sender, spender, rawAmt);
        return true;
    }

    function transfer(address to, uint rawAmt) public override returns (bool success) {
        balances[msg.sender] = safeSub(balances[msg.sender], rawAmt);
        balances[to] = safeAdd(balances[to], rawAmt);
        emit Transfer(msg.sender, to, rawAmt);
        return true;
    }
    
    // ERC the allowence function should be more specic +-
    function transferFrom(address from, address to, uint rawAmt) public override returns (bool success) {
        allowed[from][msg.sender] = safeSub(allowed[from][msg.sender], rawAmt); // this will ensure the spender indeed has the authorization
        balances[from] = safeSub(balances[from], rawAmt);
        balances[to] = safeAdd(balances[to], rawAmt);
        emit Transfer(from, to, rawAmt);
        return true;
    }    
    
    function setPPSPrice(uint newPPSPrice) onlyContractOwner() public returns (bool success) {
        ppsPrice = newPPSPrice;
        return true;
    }
    
    function PPSPrice() public view returns (uint PPSAmt) {
        return ppsPrice;
    }
    
    function buyPPS() public payable returns (bool) {      
        // require(msg.value <= 5*10**17, "Maximum buy: 0.5 eth. ");
        uint rawPPSAmt = ppsPrice*msg.value; 
        balances[address(this)] = safeSub(balances[address(this)], rawPPSAmt);
        balances[msg.sender] = safeAdd(balances[msg.sender], rawPPSAmt);
        emit Transfer(address(this), msg.sender, rawPPSAmt);
        emit BuyPPS(msg.value, rawPPSAmt);
        return true;
    }
    
    function sellPPS(uint amtPPS) public payable returns (bool success) {
        uint256 amtETH = safeDiv(amtPPS, ppsPrice);
        balances[msg.sender] = safeSub(balances[msg.sender], amtPPS);
        balances[address(this)] = safeAdd(balances[address(this)], amtPPS);

        (bool sent, ) = msg.sender.call{value: amtETH}("");
        require(sent, "Failed to send Ether");

        emit Transfer(msg.sender, address(this), amtPPS);
        emit SellPPS(amtPPS, amtETH);
        return true;
    }

    function withdrawPPS(uint amtPPS) onlyContractOwner() public returns (bool success) {
        balances[address(this)] = safeSub(balances[address(this)], amtPPS);
        balances[trustAccount] = safeAdd(balances[trustAccount], amtPPS);
        emit Transfer(address(this), trustAccount, amtPPS);
        return true;
    }

    function withdrawETH(uint amtETH) onlyContractOwner() public returns (bool success) {
        trustAccount.transfer(amtETH);        
        return true;
    }

    function fulfillRandomWords(uint requestId, uint[] memory randomWords) internal override {
        randomNumber = randomWords[0];
        emit RandomNumber(randomNumber);
        randomNumber = (randomNumber % 10) + 1;
        
        if (randomNumber == guessNumber) {
            balances[address(this)] = safeSub(balances[address(this)], 10);
            balances[msg.sender] = safeAdd(balances[msg.sender], 10);
            emit Transfer(address(this), msg.sender, 10);
            return;
        }

        revert("You guess isn't right");
    }

    function lottery(uint _num) public payable returns (uint256) {
        guessNumber = _num;
        uint256 requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        return requestId;
    }
}