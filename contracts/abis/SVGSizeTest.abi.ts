import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const SVGSizeTestEvents = [];

export const SVGSizeTestAbi = [
    {
        name: 'testReturn',
        inputs: [{ name: 'size', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'result', type: ABIDataTypes.STRING }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'testDataURI',
        inputs: [{ name: 'svgSize', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'result', type: ABIDataTypes.STRING }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'testBase64URI',
        inputs: [{ name: 'rawSize', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'result', type: ABIDataTypes.STRING }],
        type: BitcoinAbiTypes.Function,
    },
    ...SVGSizeTestEvents,
    ...OP_NET_ABI,
];

export default SVGSizeTestAbi;
