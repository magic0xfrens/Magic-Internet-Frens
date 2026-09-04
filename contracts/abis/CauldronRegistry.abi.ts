import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const CauldronRegistryEvents = [];

export const CauldronRegistryAbi = [
    {
        name: 'summonGenesis',
        inputs: [
            { name: 'tokenAddress', type: ABIDataTypes.ADDRESS },
            { name: 'poolAddress', type: ABIDataTypes.ADDRESS },
            { name: 'name', type: ABIDataTypes.STRING },
            { name: 'symbol', type: ABIDataTypes.STRING },
        ],
        outputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'triggerRebirth',
        inputs: [
            { name: 'newTokenAddress', type: ABIDataTypes.ADDRESS },
            { name: 'newPoolAddress', type: ABIDataTypes.ADDRESS },
            { name: 'name', type: ABIDataTypes.STRING },
            { name: 'symbol', type: ABIDataTypes.STRING },
        ],
        outputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'claimTokens',
        inputs: [{ name: 'generation', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'balance', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getCurrentToken',
        inputs: [],
        outputs: [{ name: 'token', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getCurrentGeneration',
        inputs: [],
        outputs: [{ name: 'generation', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    ...CauldronRegistryEvents,
    ...OP_NET_ABI,
];

export default CauldronRegistryAbi;
