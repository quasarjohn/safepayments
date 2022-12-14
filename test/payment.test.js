const { assert, expect } = require("chai");
// const { addLiquidityETH } = require("./helpers");
const SafePayment = artifacts.require("./SafePayment.sol");
const SafePaymentFactory = artifacts.require(
  "./SafePaymentFactory.sol"
);

const Web3 = require("web3");
const web3 = new Web3("http://127.0.0.1:7545");

require("chai").use(require("chai-as-promised")).should();

function isNotEmpty(val) {
  assert.notEqual(val, "");
  assert.notEqual(val, "0x0");
  assert.notEqual(val, null);
  assert.notEqual(val, undefined);
}

contract("Locker", (accounts) => {
  let factory;
  let paymentContract;
  let totalConvenienceFee;
  let serviceAmount = 10000000;

  before(async () => {
    factory = await SafePaymentFactory.deployed();
  });

  describe("Safe payment contract", () => {
    it("deploys successfully", async () => {
      isNotEmpty(factory.address);
      console.log(factory.address);
      // console.log((await factory.masterContract()).toString())
    });

    it("creates new payment", async () => {
      await factory.createNewPayment("testid", 10000000);
    });

    it("fetches the payment and reads correct values", async () => {
      let paymentAddress = await factory.getPayment("testid");
      isNotEmpty(paymentAddress);

      paymentContract = await SafePayment.at(paymentAddress);

      assert.equal(await paymentContract.provider(), accounts[0]);

      assert.equal(
        (await paymentContract.serviceAmount()).toString(),
        "10000000"
      );
    });

    it("calculates correct required deposit", async () => {
      assert.equal(
        (await paymentContract.customerDepositPercentage()).toString(),
        "25"
      );

      assert.equal(
        (await paymentContract.providerDepositPercentage()).toString(),
        "25"
      );

      assert.equal(
        (await paymentContract.customerRequiredDeposit()).toString(),
        "2500000"
      );

      assert.equal(
        (await paymentContract.providerRequiredDeposit()).toString(),
        "2500000"
      );
    });

    it("calculates correct convenience fee", async () => {
      // let convenienceFee = (await paymentContract.convenienceFee()).toString();
      // let conveniencePercentage = (
      //   await paymentContract.convenienceFeePercentage()
      // ).toString();

      // let serviceAmount = (await paymentContract.serviceAmount()).toString();

      // convenienceFee = 10000
      // percentage = 5%
      // serviceAmount = 10000000

      // convenience fee should be 10000 + 500000 = 510000

      totalConvenienceFee = (
        await paymentContract.totalConvenienceFee()
      ).toString();

      assert.equal(totalConvenienceFee, "510000");
    });

    it("deposit starts at zero", async () => {
      assert.equal(
        (await paymentContract.providerDepositAmount()).toString(),
        "0"
      );
      assert.equal(
        (await paymentContract.customerDepositAmount()).toString(),
        "0"
      );
    });

    it("fails deposit if incorrect function called", async () => {
      try {
        await paymentContract.customerDeposit({
          value: "2500000",
        });
      } catch (error) {
        expect(error.reason).to.equal("You are not the customer.");
      }

      try {
        await paymentContract.providerDeposit({
          value: "2500000",
          from: accounts[1],
        });
      } catch (error) {
        expect(error.reason).to.equal("You are not the provider.");
      }
    });

    it("rejects deposit if value is incorrect", async () => {
      // provider
      try {
        await paymentContract.providerDeposit({
          value: "2400000",
        });
      } catch (error) {
        expect(error.reason).to.equal("Incorrect deposit amount.");
      }

      try {
        await paymentContract.providerDeposit({
          value: (2500001 + totalConvenienceFee).toString(),
        });
      } catch (error) {
        expect(error.reason).to.equal("Incorrect deposit amount.");
      }

      // customer
      try {
        await paymentContract.customerDeposit({
          value: "2400000",
          from: accounts[1],
        });
      } catch (error) {
        expect(error.reason).to.equal("Incorrect deposit amount.");
      }

      try {
        await paymentContract.customerDeposit({
          value: (2500001 + totalConvenienceFee).toString(),
          from: accounts[1],
        });
      } catch (error) {
        expect(error.reason).to.equal("Incorrect deposit amount.");
      }
    });

    it("allows both parties to deposit", async () => {
      let requiredDeposit = 2500000;

      assert.equal(
        requiredDeposit.toString(),
        parseFloat(await paymentContract.customerRequiredDeposit()).toString()
      );

      // contract has no balance
      assert.equal(await web3.eth.getBalance(paymentContract.address), "0");

      // provider
      await paymentContract.providerDeposit({
        value: (requiredDeposit + parseFloat(totalConvenienceFee)).toString(),
      });

      assert.equal(
        (await paymentContract.providerDepositAmount()).toString(),
        requiredDeposit.toString()
      );

      await paymentContract.customerDeposit({
        value: (
          requiredDeposit +
          parseFloat(totalConvenienceFee) +
          serviceAmount
        ).toString(),
        from: accounts[1],
      });

      assert.equal(
        (await paymentContract.customerDepositAmount()).toString(),
        (requiredDeposit + serviceAmount).toString()
      );

      // contract has correct balance
      assert.equal(
        await web3.eth.getBalance(paymentContract.address),
        (
          (requiredDeposit + parseFloat(totalConvenienceFee)) * 2 +
          serviceAmount
        ).toString()
      );

      let providerDepositAmount = (
        await paymentContract.providerDepositAmount()
      ).toString();

      let customerDepositAmount = (
        await paymentContract.customerDepositAmount()
      ).toString();

      let balance = (
        await web3.eth.getBalance(paymentContract.address)
      ).toString();

      assert.equal(
        parseFloat(balance),
        parseFloat(customerDepositAmount) +
          parseFloat(providerDepositAmount) +
          parseFloat(totalConvenienceFee) * 2
      );
    });

    it("correct default vote values", async () => {
      assert.equal((await paymentContract.customerVote()).toString(), "0");
      assert.equal((await paymentContract.providerVote()).toString(), "0");
    });

    it("rejects vote if value is incorrect", async () => {
      try {
        await paymentContract.castVote("4");
      } catch (error) {
        expect(error.reason).to.equal(
          "Only values 1 or 2 are allowed. False = 1, True = 2"
        );
      }
    });

    it("rejects vote if cast by wrong people", async () => {
      try {
        await paymentContract.castVote("2", { from: accounts[4] });
      } catch (error) {
        expect(error.reason).to.equal(
          "Only customer or provider are allowed to vote."
        );
      }
    });

    it("rejects releasing of funds if vote not yet cast", async () => {
      try {
        await paymentContract.releaseFunds();
      } catch (error) {
        expect(error.reason).to.equal(
          "Both parties need to cast the same vote to release funds."
        );
      }
    });

    it("allows casting vote", async () => {
      assert.equal(
        (await paymentContract.isVotingComplete()).toString(),
        "false"
      );

      assert.equal((await paymentContract.customerVote()).toString(), "0");
      assert.equal((await paymentContract.providerVote()).toString(), "0");

      await paymentContract.castVote("1");
      await paymentContract.castVote("2", { from: accounts[1] });

      await paymentContract.castVote("2");

      try {
        await paymentContract.castVote("1", { from: accounts[1] });
      } catch (error) {
        expect(error.reason).to.equal(
          "Voting is complete. Both parties have agreed to the same decision."
        );
      }

      assert.equal(
        (await paymentContract.isVotingComplete()).toString(),
        "true"
      );
    });

    // both yes
    it("allows returning of deposit and sending payment to provider", async () => {
      let providerDepositAmount = (
        await paymentContract.providerDepositAmount()
      ).toString();

      let customerDepositAmount = (
        await paymentContract.customerDepositAmount()
      ).toString();

      let oldBalance = (
        await web3.eth.getBalance(paymentContract.address)
      ).toString();

      let convenienceFee = (
        await paymentContract.totalConvenienceFee()
      ).toString();

      await paymentContract.releaseFunds();
      await paymentContract.releaseFunds({ from: accounts[1] });

      let expectedBalance =
        parseFloat(oldBalance) -
        (parseFloat(providerDepositAmount) + parseFloat(customerDepositAmount));

      assert.equal(
        expectedBalance.toString(),
        (await web3.eth.getBalance(paymentContract.address)).toString()
      );

      assert.equal(
        (await web3.eth.getBalance(paymentContract.address)).toString(),
        (parseFloat(convenienceFee) * 2).toString()
      );
    });

    // both cancel
    // it("allows returning of funds if deal was canceled", async () => {
    //   await paymentContract.releaseFunds();
    // });

    // both agreed
  });
});
