import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const CauldronTokenEvents = [];

export const CauldronTokenAbi = [
    {
        name: 'getGeneration',
        inputs: [],
        outputs: [{ name: 'generation', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'mint',
        inputs: [
            { name: 'to', type: ABIDataTypes.ADDRESS },
            { name: 'amount', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'isAlive',
        inputs: [],
        outputs: [{ name: 'alive', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setElderCircle',
        inputs: [{ name: 'elderCircle', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'markDead',
        inputs: [],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setRouter',
        inputs: [{ name: 'router', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setWbtc',
        inputs: [{ name: 'wbtc', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setSwapThreshold',
        inputs: [{ name: 'threshold', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getAccumulatedTax',
        inputs: [],
        outputs: [{ name: 'accumulated', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    ...CauldronTokenEvents,
    ...OP_NET_ABI,
];

export default CauldronTokenAbi;
