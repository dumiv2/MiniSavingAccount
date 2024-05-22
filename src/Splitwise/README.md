# Our new proposal function as well as new features

1. Background

Alice, Bob and Carol are all friends who like to go out to eat together, Bob paid for lunch last time he and Alice went out to eat, so Alice owes Bob $10, Carol paid when she and Bob went out to eat, and so Bob owes Carol $10. 

Now imagine Carol run short on cash, and borrows $10 from Alice. Notice that at this point, instead of each person paying back their 'loan' at some point, they could just all agree that nobody owes anyone. In other words, whenever there is a cycle of debt, we can just remove it from our bookkeeping, making everything simpler and reducing the number of times cash needs to change hands. 

We will build a decentrialized way to track who owes what to do, so that no trusted third party has to be relied upon. It will be efficient: it won't cost an exorbitant amount of gas to store this data. No value will get transfered on the blockchain using app; the only ether involved will be for gas 

Because it's on the blockchain, when Carol picks up the check for her and Bob's meal, she can ask Bob to submit an IOU (which he can do using our DApp), and she can verify that he indeed has. The public on-chain storage will server as a single source of truth for who owes who. Later, when the cycle illustrate above get resolved, Carol will see that Bob no longer owes her money 

![Test](testing.png)


![alt text](nothiscase.png)


![alt text](notcomplex.png)


```solidity
struct IOU {
    address creditor;
    int32 amount;
    uint creditor_id;
    bool _valid;
}
struct Debtor {
    IOU [] IOUs; // list of IOU
    address debtor;
    uint id;
    bool _valid;
}
```

Debtor contains a list of IOU associated with a debtor. There might be several debtors, and they have their own IOU list 


Searching with mapping but return with array to save gas, because mapping can'be return in solidity. Link: https://ethereum.stackexchange.com/questions/65589/return-a-mapping-in-a-getall-function

```
mapping (address => mapping(address => IOU)) ledger
```

Mapping for searching 

```
Debtor[] ledgerArr
```

Array for returning 

**Append New Object to Array in Function**

Every newly initialized debtor is added into `Debtor[] ledgerArr` by `add_IOU` method. However, initializing onject inside of function automatically assigns them a memory pointer. To persistently push the object, one has to declare it outside and assign value inside the function. As follows: 

```
Debtor storage debtor = debtorMap[msg.send]; 
```

References: https://ethereum.stackexchange.com/questions/4467/initialising-structs-to-storage-variables


**Resolving Loop**
`add_IOU` is allowed to send negative value in order to cancel edges in IOU graph. For example, current IOU state is 


![alt text](currentIOstate.png)


With one more IOU added, B owes A 3 in this case. BFS will applied to find least weighted edge and cancel each edge accordingly. Note blue dash arrow means cancellation

![alt text](withBowesA3added.png)


![alt text](aftercancel.png)


**Call & Send**
There're `call` and `send` in web3js

`Call` is for A method with `view` modifier in contract. While `send` is for method incuring state change. 

**Send Address to Contract**: 

For example, `for("0x0d0f055551233");` is correct when sending to contract instead of `foo(0x0d0f05555)`

**What is 500000 Gas Limit Magic Number in Calling Method** 

When a new debtor be initialized, approx 310 000 gas will be used, which exceeds default gas limit set by remix. Therefore, I set it 500 000. To estimate the gas usage, utilize ![estimateGas](https://web3js.readthedocs.io/en/v1.2.11/web3-eth-contract.html#methods-mymethod-estimategas)