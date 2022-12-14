const SafePayment = artifacts.require("SafePayment");
const SafePaymentFactory = artifacts.require("SafePaymentFactory");

module.exports = async function (deployer) {
  await deployer.deploy(SafePayment);
  await deployer.deploy(SafePaymentFactory, SafePayment.address);

};
