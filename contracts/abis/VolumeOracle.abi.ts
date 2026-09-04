import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const VolumeOracleEvents = [];

export const VolumeOracleAbi = [
    {
        name: 'setDeathThreshold',
        inputs: [{ name: 'threshold', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'updateVolume',
        inputs: [
            { name: 'pool', type: ABIDataTypes.ADDRESS },
            { name: 'volumeSats', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'isDead',
        inputs: [{ name: 'pool', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'isDead', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getVolume',
        inputs: [{ name: 'pool', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'volume', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'addKeeper',
        inputs: [{ name: 'keeper', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'removeKeeper',
        inputs: [{ name: 'keeper', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'isKeeper',
        inputs: [{ name: 'account', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'result', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    ...VolumeOracleEvents,
    ...OP_NET_ABI,
];

export default VolumeOracleAbi;
