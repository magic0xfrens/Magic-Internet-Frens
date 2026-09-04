import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const ElderCircleEvents = [];

export const ElderCircleAbi = [
    {
        name: 'checkin',
        inputs: [],
        outputs: [{ name: 'streak', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'claimRewards',
        inputs: [],
        outputs: [{ name: 'amount', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'depositFees',
        inputs: [{ name: 'amount', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'notifyTransfer',
        inputs: [{ name: 'from', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setTokenAddress',
        inputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setRegistryAddress',
        inputs: [{ name: 'registry', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'authorizeToken',
        inputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'deauthorizeToken',
        inputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'authorizeDepositor',
        inputs: [{ name: 'depositor', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'deauthorizeDepositor',
        inputs: [{ name: 'depositor', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getStreak',
        inputs: [{ name: 'holder', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'streak', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getPending',
        inputs: [{ name: 'holder', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'pending', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getWeight',
        inputs: [{ name: 'holder', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'weight', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getTotalWeight',
        inputs: [],
        outputs: [{ name: 'totalWeight', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    ...ElderCircleEvents,
    ...OP_NET_ABI,
];

export default ElderCircleAbi;
