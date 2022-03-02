// eslint-disable-next-line no-unused-vars
const { accounts, defaultSender } = require('@openzeppelin/test-environment');
const { BN, ether, time, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { default: BigNumber } = require('bignumber.js');
const { assert } = require('chai');

const GravisFactory = artifacts.require('GravisFactory');
const GravisPair = artifacts.require('GravisPair');
const GravisRouter = artifacts.require('GravisRouter');
const UniswapV2Factory = artifacts.require('UniswapV2Factory');
const UniswapV2Pair = artifacts.require('UniswapV2Pair');
const MockUSDX = artifacts.require('MockUSDX');
const MockUSDY = artifacts.require('MockUSDY');
const MockUSDZ = artifacts.require('MockUSDZ');
const MockWBTC = artifacts.require('MockWBTC');
const GravisVamp = artifacts.require('GravisVamp');
const Token = artifacts.require('TokenMock');
const TokenWETH = artifacts.require('MockWETH');

MockUSDX.numberFormat = 'String';

let uniswapFactory;
let uniswapFactory2;
let uniswapPair;
let uniswapPairUSDX_WETH;
let uPair;
let usdx;
let usdy;
let usdz;
let weth;
let wbtc;
let vamp;
let mooniPair;
let gravisPair;

const money = {
  ether,
  eth: ether,
  zero: ether('0'),
  weth: ether,
  dai: ether,
  usdx: ether,
  usdy: (value) => ether(value).div(new BN(1e10)),
  usdc: (value) => ether(value).div(new BN(1e12)),
  wbtc: (value) => ether(value).div(new BN(1e10)),
};

/**
 *Token  Decimals
V ETH    (18)
  USDT   (6)
  USDB   (18)
V USDC   (6)
V DAI    (18)
V EMRX   (8)
V WETH   (18)
v WBTC   (8)
  renBTC (8)
*/

let exec_id = 1;
const exec = async function (method, params) {
  return new Promise((resolve) =>
    web3.currentProvider.send({ method, params, jsonrpc: '2.0', id: ++exec_id }, (err, res) => resolve(res))
  );
};

contract('GravisVamp test', function (accounts) {
  const [TestOwner, alice, bob, clarc, dave, eve, george, henry, ivan] = accounts;

  before(async function () {
    uniswapFactory = await UniswapV2Factory.new(TestOwner);
    uniswapFactory2 = await UniswapV2Factory.new(TestOwner);

    usdx = await MockUSDX.new();
    usdy = await MockUSDY.new();
    usdz = await MockUSDZ.new();
    weth = await TokenWETH.new();
    wbtc = await MockWBTC.new();

    /* USDX - USDZ pair (DAI - USDC) */
    await uniswapFactory.createPair(weth.address, usdz.address);
    await uniswapFactory2.createPair(weth.address, usdz.address);

    const pairAddress = await uniswapFactory.getPair(weth.address, usdz.address);
    const pairAddress2 = await uniswapFactory2.getPair(weth.address, usdz.address);

    uniswapPair = await UniswapV2Pair.at(pairAddress);
    uPair2 = await UniswapV2Pair.at(pairAddress2);

    /* USDX - WETH pair (DAI - ETH) */
    await uniswapFactory.createPair(usdx.address, weth.address);
    await uniswapFactory2.createPair(usdx.address, weth.address);

    const pairAddressUSDX_WETH = await uniswapFactory.getPair(usdx.address, weth.address);
    uniswapPairUSDX_WETH = await UniswapV2Pair.at(pairAddressUSDX_WETH);

    const wethToPair = new BN(1).mul(new BN(10).pow(new BN(await weth.decimals()))).toString();
    const usdzToPair = new BN(40).mul(new BN(10).pow(new BN(await usdz.decimals()))).toString();

    const usdxToPair_USDXWETH = new BN(400).mul(new BN(10).pow(new BN(await usdx.decimals()))).toString();
    const wethToPair_USDXWETH = new BN(1).mul(new BN(10).pow(new BN(await weth.decimals()))).toString();

    await weth.deposit({ value: wethToPair });
    await weth.transfer(uPair2.address, wethToPair);
    await usdz.transfer(uPair2.address, usdzToPair);
    await uPair2.mint(bob);

    await weth.deposit({ value: wethToPair });
    await weth.deposit({ value: '10000000000000000' });
    await weth.transfer(uniswapPair.address, wethToPair);
    await usdz.transfer(uniswapPair.address, usdzToPair);
    await uniswapPair.mint(alice);
    let ttt = new BN(wethToPair);
    let ttt2 = new BN(usdzToPair);
    await weth.deposit({ value: ttt.mul(new BN(10)).toString() });
    await weth.transfer(uniswapPair.address, ttt.mul(new BN(10)).toString());
    await usdz.transfer(uniswapPair.address, ttt2.mul(new BN(10)).toString());
    await uniswapPair.mint(bob);

    await weth.deposit({ value: ttt.mul(new BN(30)).toString() });
    await weth.transfer(uniswapPair.address, ttt.mul(new BN(30)).toString());
    await usdz.transfer(uniswapPair.address, ttt2.mul(new BN(30)).toString());
    await uniswapPair.mint(dave);

    await usdx.transfer(bob, usdxToPair_USDXWETH);
    await usdx.transfer(uniswapPairUSDX_WETH.address, usdxToPair_USDXWETH);
    await weth.deposit({ value: wethToPair_USDXWETH });
    await weth.transfer(uniswapPairUSDX_WETH.address, wethToPair_USDXWETH);
    await uniswapPairUSDX_WETH.mint(alice);
    await usdx.transfer(alice, '1000000000000');
    await weth.transfer(alice, '1000000000');

    this.factory = await GravisFactory.new(ivan);
    console.log('INIT_CODE_PAIR_HASH =', await this.factory.INIT_CODE_PAIR_HASH());

    this.router = await GravisRouter.new(this.factory.address, weth.address);
    await weth.approve(this.router.address, '1000000000000000000000000000', { from: alice });
    await usdx.approve(this.router.address, '1000000000000000000000000000', { from: alice });

    let deadlockTime = Math.floor(Date.now() / 1000) + 120;

    await this.router.addLiquidity(usdx.address, weth.address, '100000000', '10000000', 0, 0, alice, deadlockTime, {
      from: alice,
    });
    let p_a = await this.factory.getPair(usdx.address, weth.address);
    gravisPair = await GravisPair.at(p_a);

    vamp = await GravisVamp.new([p_a, pairAddress, pairAddressUSDX_WETH], [0, 0, 0], this.router.address, {
      from: henry,
    });

    await uniswapPair.approve(vamp.address, '1000000000000000000000000000', { from: alice });
    await gravisPair.approve(vamp.address, '1000000000000000000000000000', {
      from: alice,
    });

    await exec('evm_snapshot', []);  // creates snapshot #2
  });

  beforeEach(async function () {
    await exec('evm_revert', [2]);
    await exec('evm_snapshot', []);
    // console.log(await exec("eth_blockNumber", []));
  });
  describe('Base checks', () => {
    it('isPairAvailable', async function () {
      assert.isTrue(await vamp.isPairAvailable(usdx.address, weth.address));
      assert.isTrue(await vamp.isPairAvailable(weth.address, usdx.address));
      assert.isNotTrue(await vamp.isPairAvailable(usdx.address, usdx.address));
    });
  });
  describe('Process allowed tokens lists', () => {
    it('should successfully get tokens list length under admin', async function () {
      let b = await vamp.getAllowedTokensLength({ from: henry });
      console.log('We have %d allowed tokens', b);
      assert.equal(b, 0);
    });
    it('should successfully get tokens list length under non-admin wallet', async function () {
      let b = await vamp.getAllowedTokensLength();
      assert.equal(b, 0);
    });
    it('should successfully add tokens under admin', async function () {
      let tx = await vamp.addAllowedToken(weth.address, { from: henry });
      console.log('Adding allowed token gas used: %d', tx.receipt.gasUsed);
      await vamp.addAllowedToken(usdz.address, { from: henry });
      b = await vamp.getAllowedTokensLength({ from: henry });
      console.log('Now we have %d allowed tokens', b);
      assert.equal(b, 2);
    });
    it('should successfully list tokens under admin', async function () {
      await vamp.addAllowedToken(weth.address, { from: henry });
      await vamp.addAllowedToken(usdz.address, { from: henry });
      b = await vamp.getAllowedTokensLength({ from: henry });
      assert.equal(b, 2);
      b = await vamp.allowedTokens(0, { from: henry });
      assert.equal(b, weth.address);
      b = await vamp.allowedTokens(1, { from: henry });
      assert.equal(b, usdz.address);
    });
    it('should allow to list LP-tokens', async function () {
      let b = await vamp.lpTokensInfoLength();
      console.log(b);
      assert.equal(b, 3);
      b = await vamp.lpTokensInfo(1);
      assert.equal(b.lpToken, uniswapPair.address);
      b = await vamp.lpTokensInfo(0);
      assert.equal(b.lpToken, gravisPair.address);
    });
    it('should succeed to list tokens under non-admin wallet', async function () {
      await vamp.addAllowedToken(usdz.address, { from: henry });
      let b = await vamp.allowedTokens(0);
      assert.equal(b, usdz.address);
    });
  });
  describe('Deposit LP-tokens to our contract', () => {
    it('should be transferring Uniswap tokens successfully', async function () {
      let r = await uniswapPair.getReserves();
      console.log('Pair rsv: %d, %d', r[0].toString(), r[1].toString());
      let b = await uniswapPair.balanceOf(alice);
      console.log('Alice has %d LP-tokens', b);
      let tx = await vamp.deposit(1, 40000000, { from: alice });
      console.log('Gas used for LP-tokens transfer: ' + tx.receipt.gasUsed);
    });
    it('should be transferring Gravis tokens successfully', async function () {
      console.log('GravisPair address is %s', gravisPair);
      let b = await gravisPair.balanceOf(alice);
      console.log('Alice has %d LP-tokens', b);
      let tx = await vamp.deposit(0, 1000000, { from: alice });
      console.log('Gas used for LP-tokens transfer: ' + tx.receipt.gasUsed);
    });
  });
});
