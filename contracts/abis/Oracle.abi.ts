import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const OracleEvents = [];

export const OracleAbi = [
    {
        name: '_getPrice',
        inputs: [],
        outputs: [{ name: 'price', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_isFresh',
        inputs: [],
        outputs: [{ name: 'fresh', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_lastUpdateView',
        inputs: [],
        outputs: [{ name: 'timestamp', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_adminView',
        inputs: [],
        outputs: [{ name: 'admin', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_updateCountView',
        inputs: [],
        outputs: [{ name: 'count', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_setPrice',
        inputs: [{ name: 'price', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_transferAdmin',
        inputs: [{ name: 'newAdmin', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    ...OracleEvents,
    ...OP_NET_ABI,
];

export default OracleAbi;
