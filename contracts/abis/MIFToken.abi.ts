import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const MIFTokenEvents = [
    {
        name: 'Minted',
        values: [
            { name: 'to', type: ABIDataTypes.ADDRESS },
            { name: 'amount', type: ABIDataTypes.UINT256 },
        ],
        type: BitcoinAbiTypes.Event,
    },
];

export const MIFTokenAbi = [
    {
        name: '_mint_external',
        inputs: [
            { name: 'to', type: ABIDataTypes.ADDRESS },
            { name: 'amount', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_addMinter',
        inputs: [{ name: 'minter', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_removeMinter',
        inputs: [{ name: 'minter', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: '_isMinter',
        inputs: [{ name: 'account', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'result', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    ...MIFTokenEvents,
    ...OP_NET_ABI,
];

export default MIFTokenAbi;
