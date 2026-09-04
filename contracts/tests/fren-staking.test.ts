/**
 * FREN Staking Contract Tests
 *
 * Tests for the staking module where users stake FREN tokens and receive sFREN
 * (staked FREN) shares. The sFREN/FREN ratio increases as rewards are distributed,
 * meaning sFREN becomes worth more FREN over time. Unstaking imposes a 24-hour
 * timelock before the user can claim their underlying FREN.
 *
 * TODO: Replace mock utilities with OP_NET SDK testing framework
 *       once the runtime is integrated (opnet, Blockchain, Address, etc.)
 */

// TODO: Import OP_NET SDK test utilities
// import { Blockchain, Address, CallResponse } from '@opnet/unit-test-framework';

// ---------------------------------------------------------------------------
// Minimal describe/it test runner
// ---------------------------------------------------------------------------
type TestFn = () => void | Promise<void>;
interface TestCase { name: string; fn: TestFn }
interface Suite { name: string; tests: TestCase[]; beforeEach?: TestFn }

const suites: Suite[] = [];
let currentSuite: Suite | null = null;

function describe(name: string, fn: () => void): void {
    const suite: Suite = { name, tests: [] };
    suites.push(suite);
    currentSuite = suite;
    fn();
    currentSuite = null;
}

function beforeEach(fn: TestFn): void {
    if (currentSuite) currentSuite.beforeEach = fn;
}

function it(name: string, fn: TestFn): void {
    if (currentSuite) currentSuite.tests.push({ name, fn });
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function assertEqual<T>(actual: T, expected: T, msg?: string): void {
    if (actual !== expected) {
        throw new Error(
            `Assertion failed: expected ${expected}, got ${actual}${msg ? ' — ' + msg : ''}`
        );
    }
}

function assertReverts(fn: () => void, expectedMsg?: string): void {
    try {
        fn();
        throw new Error('Expected revert but call succeeded');
    } catch (e: any) {
        if (expectedMsg && !e.message.includes(expectedMsg)) {
            throw new Error(
                `Expected revert with "${expectedMsg}" but got "${e.message}"`
            );
        }
    }
}

function assertApproxEqual(actual: bigint, expected: bigint, tolerance: bigint, msg?: string): void {
    const diff = actual > expected ? actual - expected : expected - actual;
    if (diff > tolerance) {
        throw new Error(
            `Assertion failed: ${actual} not within ${tolerance} of ${expected}${msg ? ' — ' + msg : ''}`
        );
    }
}

// ---------------------------------------------------------------------------
// Mock addresses
// ---------------------------------------------------------------------------
const DEPLOYER  = '0xDeployerAddress000000000000000000000001';
const ALICE     = '0xAliceAddress00000000000000000000000003';
const BOB       = '0xBobAddress000000000000000000000000000004';
const CAROL     = '0xCarolAddress00000000000000000000000005';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const TIMELOCK_DURATION = 24 * 60 * 60; // 24 hours in seconds
const PRECISION = 10n ** 18n;

// ---------------------------------------------------------------------------
// Mock Staking Contract
// ---------------------------------------------------------------------------
class MockFrenStaking {
    /** Total FREN held by the staking contract */
    private totalFren: bigint = 0n;
    /** Total sFREN shares outstanding */
    private totalShares: bigint = 0n;
    /** sFREN shares per user */
    private shares: Map<string, bigint> = new Map();
    /** Pending unstake requests: user -> { amount (FREN), unlockTime } */
    private unstakeRequests: Map<string, { frenAmount: bigint; unlockTime: number }> = new Map();
    /** Simulated current block timestamp */
    public currentTime: number = 1_700_000_000;

    // --- Core staking ----------------------------------------------------

    /**
     * Stake FREN and receive sFREN shares.
     * shares = (frenAmount * totalShares) / totalFren   (or 1:1 if pool empty)
     */
    stake(caller: string, frenAmount: bigint): bigint {
        if (frenAmount <= 0n) throw new Error('Revert: amount must be > 0');

        let newShares: bigint;
        if (this.totalShares === 0n || this.totalFren === 0n) {
            newShares = frenAmount; // 1:1 initial ratio
        } else {
            newShares = (frenAmount * this.totalShares) / this.totalFren;
        }
        if (newShares === 0n) throw new Error('Revert: zero shares');

        this.totalFren += frenAmount;
        this.totalShares += newShares;
        const prev = this.shares.get(caller) ?? 0n;
        this.shares.set(caller, prev + newShares);

        return newShares;
    }

    /**
     * Initiate unstake — locks FREN for TIMELOCK_DURATION.
     * Burns the sFREN shares immediately and records the FREN owed.
     */
    unstake(caller: string, sharesToBurn: bigint): void {
        const userShares = this.shares.get(caller) ?? 0n;
        if (userShares < sharesToBurn) throw new Error('Revert: insufficient shares');

        const frenOwed = (sharesToBurn * this.totalFren) / this.totalShares;

        this.shares.set(caller, userShares - sharesToBurn);
        this.totalShares -= sharesToBurn;
        this.totalFren -= frenOwed;

        const existing = this.unstakeRequests.get(caller);
        const prevAmount = existing ? existing.frenAmount : 0n;

        this.unstakeRequests.set(caller, {
            frenAmount: prevAmount + frenOwed,
            unlockTime: this.currentTime + TIMELOCK_DURATION,
        });
    }

    /**
     * Claim unstaked FREN after timelock has elapsed.
     */
    claim(caller: string): bigint {
        const req = this.unstakeRequests.get(caller);
        if (!req || req.frenAmount === 0n) throw new Error('Revert: nothing to claim');
        if (this.currentTime < req.unlockTime) throw new Error('Revert: timelock not elapsed');

        const amount = req.frenAmount;
        this.unstakeRequests.delete(caller);
        return amount;
    }

    /**
     * Distribute reward FREN into the pool (increases sFREN/FREN ratio).
     */
    distributeReward(amount: bigint): void {
        if (this.totalShares === 0n) throw new Error('Revert: no stakers');
        this.totalFren += amount;
    }

    // --- View helpers ----------------------------------------------------

    /** How much FREN one sFREN share is worth */
    sharePrice(): bigint {
        if (this.totalShares === 0n) return PRECISION;
        return (this.totalFren * PRECISION) / this.totalShares;
    }

    sharesOf(addr: string): bigint {
        return this.shares.get(addr) ?? 0n;
    }

    frenValueOf(addr: string): bigint {
        const s = this.shares.get(addr) ?? 0n;
        if (this.totalShares === 0n) return 0n;
        return (s * this.totalFren) / this.totalShares;
    }

    getUnstakeRequest(addr: string) {
        return this.unstakeRequests.get(addr) ?? null;
    }

    getTotalFren(): bigint { return this.totalFren; }
    getTotalShares(): bigint { return this.totalShares; }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
let staking: MockFrenStaking;

describe('FREN Staking', () => {
    beforeEach(() => {
        staking = new MockFrenStaking();
    });

    // --- Stake FREN -> receive sFREN ------------------------------------
    it('should mint sFREN 1:1 on first stake', () => {
        // TODO: Replace with OP_NET SDK calls
        //   await frenToken.approve(stakingAddress, 1000n);
        //   const result = await staking.stake(1000n);
        const shares = staking.stake(ALICE, 1000n * PRECISION);
        assertEqual(shares, 1000n * PRECISION, 'First staker should get 1:1 shares');
        assertEqual(staking.sharesOf(ALICE), 1000n * PRECISION);
    });

    // --- sFREN/FREN ratio -----------------------------------------------
    it('should calculate correct sFREN/FREN ratio after rewards', () => {
        staking.stake(ALICE, 1000n * PRECISION);

        // Before rewards: 1 sFREN = 1 FREN
        assertEqual(staking.sharePrice(), PRECISION, 'Ratio should be 1:1 initially');

        // Distribute 500 FREN reward
        staking.distributeReward(500n * PRECISION);

        // Now 1000 shares back 1500 FREN => 1 share = 1.5 FREN
        const expectedPrice = (1500n * PRECISION * PRECISION) / (1000n * PRECISION);
        assertEqual(staking.sharePrice(), expectedPrice, 'Ratio should be 1.5 after reward');
    });

    // --- distributeReward increases ratio --------------------------------
    it('should increase sFREN/FREN ratio when rewards are distributed', () => {
        staking.stake(ALICE, 2000n * PRECISION);
        const priceBefore = staking.sharePrice();

        staking.distributeReward(1000n * PRECISION);
        const priceAfter = staking.sharePrice();

        assert(priceAfter > priceBefore, 'Share price should increase after reward distribution');
    });

    // --- Unstake with 24h timelock --------------------------------------
    it('should initiate unstake and set 24h timelock', () => {
        staking.stake(ALICE, 1000n * PRECISION);
        staking.unstake(ALICE, 500n * PRECISION);

        const req = staking.getUnstakeRequest(ALICE);
        assert(req !== null, 'Unstake request should exist');
        assertEqual(
            req!.unlockTime,
            staking.currentTime + TIMELOCK_DURATION,
            'Unlock time should be current + 24h'
        );
        assertEqual(req!.frenAmount, 500n * PRECISION, 'FREN amount should match');
        assertEqual(staking.sharesOf(ALICE), 500n * PRECISION, 'Shares should be reduced');
    });

    // --- Claim after timelock -------------------------------------------
    it('should allow claim after timelock has elapsed', () => {
        staking.stake(ALICE, 1000n * PRECISION);
        staking.unstake(ALICE, 1000n * PRECISION);

        // Advance time past the timelock
        staking.currentTime += TIMELOCK_DURATION + 1;

        const claimed = staking.claim(ALICE);
        assertEqual(claimed, 1000n * PRECISION, 'Should claim full amount');
    });

    // --- Claim before timelock reverts ----------------------------------
    it('should revert claim before timelock has elapsed', () => {
        staking.stake(ALICE, 1000n * PRECISION);
        staking.unstake(ALICE, 500n * PRECISION);

        // Do NOT advance time
        assertReverts(
            () => staking.claim(ALICE),
            'timelock not elapsed'
        );
    });

    // --- Multiple stakers share rewards proportionally ------------------
    it('should distribute rewards proportionally among multiple stakers', () => {
        // Alice stakes 3000, Bob stakes 1000 => Alice has 75%, Bob has 25%
        staking.stake(ALICE, 3000n * PRECISION);
        staking.stake(BOB, 1000n * PRECISION);

        // Distribute 400 FREN reward
        staking.distributeReward(400n * PRECISION);

        // Total FREN in pool = 4400
        // Alice value = (3000 / 4000) * 4400 = 3300
        // Bob value   = (1000 / 4000) * 4400 = 1100
        const aliceValue = staking.frenValueOf(ALICE);
        const bobValue = staking.frenValueOf(BOB);

        assertApproxEqual(aliceValue, 3300n * PRECISION, 1n, 'Alice should have ~3300 FREN value');
        assertApproxEqual(bobValue, 1100n * PRECISION, 1n, 'Bob should have ~1100 FREN value');
    });

    // --- Second staker gets fewer shares when ratio > 1 -----------------
    it('should give fewer shares to later stakers when ratio has increased', () => {
        staking.stake(ALICE, 1000n * PRECISION);
        staking.distributeReward(1000n * PRECISION);
        // Ratio is now 2:1 (1000 shares, 2000 FREN)

        const bobShares = staking.stake(BOB, 1000n * PRECISION);
        // Bob should get 1000 * 1000 / 2000 = 500 shares
        assertEqual(bobShares, 500n * PRECISION, 'Bob should get 500 shares at 2:1 ratio');
    });

    // --- Unstake reflects increased ratio --------------------------------
    it('should return more FREN than staked when ratio has increased', () => {
        staking.stake(ALICE, 1000n * PRECISION);
        staking.distributeReward(500n * PRECISION);
        // 1000 shares, 1500 FREN

        staking.unstake(ALICE, 1000n * PRECISION);
        const req = staking.getUnstakeRequest(ALICE);
        assertEqual(
            req!.frenAmount,
            1500n * PRECISION,
            'Should receive 1500 FREN (1000 staked + 500 reward)'
        );
    });
});

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------
(async () => {
    let passed = 0;
    let failed = 0;
    for (const suite of suites) {
        console.log(`\n  ${suite.name}`);
        for (const t of suite.tests) {
            try {
                if (suite.beforeEach) await suite.beforeEach();
                await t.fn();
                console.log(`    [PASS] ${t.name}`);
                passed++;
            } catch (e: any) {
                console.log(`    [FAIL] ${t.name} — ${e.message}`);
                failed++;
            }
        }
    }
    console.log(`\n  Results: ${passed} passed, ${failed} failed\n`);
    if (failed > 0) process.exit(1);
})();
