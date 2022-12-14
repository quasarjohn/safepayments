pragma solidity ^0.8.4;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address internal _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract CloneFactory {
    function createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            result := create(0, clone, 0x37)
        }
    }

    function isClone(address target, address query)
        internal
        view
        returns (bool result)
    {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000
            )
            mstore(add(clone, 0xa), targetBytes)
            mstore(
                add(clone, 0x1e),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            let other := add(clone, 0x40)
            extcodecopy(query, other, 0, 0x2d)
            result := and(
                eq(mload(clone), mload(other)),
                eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
            )
        }
    }
}

contract SafePayment is Ownable {
    address public provider;
    address public customer;

    string public paymentId;

    uint256 public convenienceFee;
    uint256 public convenienceFeePercentage;

    uint256 public creationDate;
    uint256 public endDate;
    uint256 public serviceAmount;
    uint256 public maxDepositAmount;
    uint256 public customerDepositPercentage;
    uint256 public providerDepositPercentage;
    uint256 public customerDepositAmount;
    uint256 public providerDepositAmount;

    uint256 public customerVote = 0;
    uint256 public providerVote = 0;

    uint256 public voteInterval;
    mapping(address => uint256) lastVoteTime;

    function init(
        string memory _paymentId,
        address _companyWallet,
        address _provider,
        uint256 _serviceAmount,
        uint256 _customerDepositPercentage,
        uint256 _providerDepositPercentage,
        uint256 _maxDepositAmount,
        uint256 _convenienceFee,
        uint256 _convenienceFeePercentage
    ) external {
        paymentId = _paymentId;
        _owner = _companyWallet;
        provider = _provider;
        serviceAmount = _serviceAmount;
        providerDepositPercentage = _providerDepositPercentage;
        customerDepositPercentage = _customerDepositPercentage;
        maxDepositAmount = _maxDepositAmount;
        convenienceFee = _convenienceFee;
        convenienceFeePercentage = _convenienceFeePercentage;

        creationDate = block.timestamp;
    }

    function calculateRequiredDeposit(uint256 depositPercentage)
        internal
        view
        returns (uint256)
    {
        // require(serviceAmount > 0, "Service amount should not be zero.");
        uint256 requiredDeposit = (serviceAmount * depositPercentage) / 100;

        // if (requiredDeposit > maxDepositAmount) {
        //     return maxDepositAmount;
        // } else if (maxDepositAmount == 0) {
        //     return requiredDeposit;
        // }

        return requiredDeposit;
    }

    function customerRequiredDeposit() public view returns (uint256) {
        return calculateRequiredDeposit(customerDepositPercentage);
    }

    function providerRequiredDeposit() public view returns (uint256) {
        return calculateRequiredDeposit(providerDepositPercentage);
    }

    function customerTotalRequiredDeposit() public view returns (uint256) {
        return
            customerRequiredDeposit() + totalConvenienceFee() + serviceAmount;
    }

    function providerTotalRequiredDeposit() public view returns (uint256) {
        return providerRequiredDeposit() + totalConvenienceFee();
    }

    function totalConvenienceFee() public view returns (uint256) {
        return
            convenienceFee + (serviceAmount * convenienceFeePercentage) / 100;
    }

    function customerDeposit() public payable {
        require(msg.sender != provider, "You are not the customer.");
        require(serviceAmount > 0, "Service amount should not be zero.");
        require(customerDepositAmount == 0, "Deposit already made.");
        require(
            msg.value == customerTotalRequiredDeposit(),
            "Incorrect deposit amount."
        );
        customer = msg.sender;
        customerDepositAmount = msg.value - totalConvenienceFee();
    }

    function providerDeposit() public payable {
        require(msg.sender == provider, "You are not the provider.");
        require(serviceAmount > 0, "Service amount should not be zero.");
        require(providerDepositAmount == 0, "Deposit already made.");
        require(
            msg.value == providerTotalRequiredDeposit(),
            "Incorrect deposit amount."
        );
        providerDepositAmount = msg.value - totalConvenienceFee();
    }

    function isVotingComplete() public view returns (bool) {
        return
            !(customerVote == 0 ||
                providerVote == 0 ||
                customerVote != providerVote);
    }

    function castVote(uint256 vote) public {
        // require(
        //     block.timestamp - lastVoteTime[msg.sender] > 21600,
        //     "You can only vote once every 6 hours."
        // );

        require(
            vote == 1 || vote == 2,
            "Only values 1 or 2 are allowed. False = 1, True = 2"
        );

        require(
            msg.sender == customer || msg.sender == provider,
            "Only customer or provider are allowed to vote."
        );

        require(
            !isVotingComplete(),
            "Voting is complete. Both parties have agreed to the same decision."
        );

        if (msg.sender == customer) {
            customerVote = vote;
        } else if (msg.sender == provider) {
            providerVote = vote;
        }

        lastVoteTime[msg.sender] = block.timestamp;
    }

    function releaseFunds() public returns (bool) {
        require(
            isVotingComplete(),
            "Both parties need to cast the same vote to release funds."
        );

        // both agreed to just return the funds
        if (customerVote == 1) {
            require(
                msg.sender == customer || msg.sender == provider,
                "You don't have rights to claim funds."
            );

            if (msg.sender == provider) {
                require(
                    providerDepositAmount > 0,
                    "You don't have any deposits."
                );
                uint256 tempAmount = providerDepositAmount;
                providerDepositAmount = 0;

                if (!payable(provider).send(tempAmount)) {
                    providerDepositAmount = tempAmount;
                    return false;
                }

                return true;
            } else if (msg.sender == customer) {
                require(
                    customerDepositAmount > 0,
                    "You don't have any deposits."
                );
                uint256 tempAmount = customerDepositAmount;
                customerDepositAmount = 0;

                if (!payable(customer).send(tempAmount)) {
                    customerDepositAmount = tempAmount;
                    return false;
                }

                return true;
            }
        }
        // both agreed that service is completed. send payment to provider and return deposits to both parties
        else if (customerVote == 2) {
            // if provider, send all funds to provider and return his deposit
            if (msg.sender == provider) {
                require(
                    providerDepositAmount > 0,
                    "You don't have any deposits."
                );
                uint256 tempAmount = providerDepositAmount;
                providerDepositAmount = 0;

                // send deposit + send service amount to provider
                if (!payable(provider).send(tempAmount + serviceAmount)) {
                    providerDepositAmount = tempAmount;
                    return false;
                }
            }
            // just return customer deposit
            else if (msg.sender == customer) {
                require(
                    customerDepositAmount > 0,
                    "You don't have any deposits."
                );
                uint256 tempAmount = customerDepositAmount - serviceAmount;
                customerDepositAmount = 0;

                // return deposit minus the service amount
                if (!payable(customer).send(tempAmount)) {
                    customerDepositAmount = tempAmount;
                    return false;
                }
            }
        }

        return true;
    }
}

contract SafePaymentFactory is Ownable, CloneFactory {
    address corelo = 0x85E5dA0ef856fB322F1f082292066da97e5Aa1d4;
    mapping(string => address) private payments;

    uint256 public customerDepositPercentage = 25;
    uint256 public providerDepositPercentage = 25;
    uint256 public maxDepositAmount = 2600000;
    uint256 public convenienceFee = 10000;
    uint256 public convenienceFeePercentage = 5;

    address public masterContract;

    constructor(address _masterContract) {
        masterContract = _masterContract;
    }

    function createNewPayment(string memory paymentId, uint256 serviceAmount)
        public
    {
        address cloneAddress = createClone(masterContract);
        SafePayment newPayment = SafePayment(cloneAddress);
        newPayment.init(
            paymentId,
            corelo,
            msg.sender,
            serviceAmount,
            customerDepositPercentage,
            providerDepositPercentage,
            maxDepositAmount,
            convenienceFee,
            convenienceFeePercentage
        );
        payments[paymentId] = cloneAddress;
    }

    function getPayment(string memory paymentId) public view returns (address) {
        return payments[paymentId];
    }

    function setCustomerDepositPercentage(uint256 _customerDepositPercentage)
        public
        onlyOwner
    {
        customerDepositPercentage = _customerDepositPercentage;
    }

    function setProviderDepositPercentage(uint256 _providerDepositPercentage)
        public
        onlyOwner
    {
        providerDepositPercentage = _providerDepositPercentage;
    }

    function setMaxDepositAmount(uint256 _maxDepositAmount) public onlyOwner {
        maxDepositAmount = _maxDepositAmount;
    }

    function setConvenienceFeePercentage(uint256 _convenienceFeePercentage)
        public
        onlyOwner
    {
        convenienceFeePercentage = _convenienceFeePercentage;
    }

    function setConvenienceFee(uint256 _convenienceFee) public onlyOwner {
        convenienceFee = _convenienceFee;
    }
}
