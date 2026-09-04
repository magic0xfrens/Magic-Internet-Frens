import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const CauldronVaultEvents = [];

export const CauldronVaultAbi = [
    {
        name: 'setRegistry',
        inputs: [{ name: 'registry', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setOracle',
        inputs: [{ name: 'oracle', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'lockLiquidity',
        inputs: [{ name: 'pool', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'canMigrate',
        inputs: [{ name: 'pool', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'canMigrate', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'migrateLiquidity',
        inputs: [
            { name: 'oldPool', type: ABIDataTypes.ADDRESS },
            { name: 'newPool', type: ABIDataTypes.ADDRESS },
            { name: 'btcAmount', type: ABIDataTypes.UINT256 },
            { name: 'tokenAmount', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    ...CauldronVaultEvents,
    ...OP_NET_ABI,
];

export default CauldronVaultAbi;
