import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const FrenForgeEvents = [];

export const FrenForgeAbi = [
    {
        name: 'setNFTContract',
        inputs: [{ name: 'nftContract', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setMerkleRoot',
        inputs: [{ name: 'root', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setArtAuthority',
        inputs: [{ name: 'authority', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setTreasury',
        inputs: [{ name: 'treasury', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setTreasuryScriptHash',
        inputs: [{ name: 'scriptHash', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'batchInscribeAll',
        inputs: [{ name: 'data', type: ABIDataTypes.BYTES }],
        outputs: [{ name: 'count', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'updateTraitImage',
        inputs: [
            { name: 'traitKey', type: ABIDataTypes.UINT256 },
            { name: 'data', type: ABIDataTypes.BYTES },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'deleteTraitImage',
        inputs: [{ name: 'traitKey', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'inscribeTrait',
        inputs: [
            { name: 'traitKey', type: ABIDataTypes.UINT256 },
            { name: 'data', type: ABIDataTypes.BYTES },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'mint',
        inputs: [
            { name: 'traitKey', type: ABIDataTypes.UINT256 },
            { name: 'data', type: ABIDataTypes.BYTES },
        ],
        outputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getArtAuthority',
        inputs: [],
        outputs: [{ name: 'authority', type: ABIDataTypes.ADDRESS }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'isTraitInscribed',
        inputs: [{ name: 'traitKey', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'inscribed', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getTraitImage',
        inputs: [{ name: 'traitKey', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'data', type: ABIDataTypes.BYTES }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getGlobalPalette',
        inputs: [],
        outputs: [{ name: 'data', type: ABIDataTypes.BYTES }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getInscriptionStats',
        inputs: [],
        outputs: [{ name: 'totalInscribed', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'tokenURI',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'uri', type: ABIDataTypes.STRING }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'renderTokenURI',
        inputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'classIdx', type: ABIDataTypes.UINT256 },
            { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
            { name: 'faceIdx', type: ABIDataTypes.UINT256 },
            { name: 'itemIdx', type: ABIDataTypes.UINT256 },
            { name: 'subitemIdx', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'uri', type: ABIDataTypes.STRING }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'tokenSvgURI',
        inputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'part', type: ABIDataTypes.UINT256 },
            { name: 'classIdx', type: ABIDataTypes.UINT256 },
            { name: 'bodyIdx', type: ABIDataTypes.UINT256 },
            { name: 'faceIdx', type: ABIDataTypes.UINT256 },
            { name: 'itemIdx', type: ABIDataTypes.UINT256 },
            { name: 'subitemIdx', type: ABIDataTypes.UINT256 },
        ],
        outputs: [
            { name: 'totalParts', type: ABIDataTypes.UINT256 },
            { name: 'svgChunk', type: ABIDataTypes.STRING },
        ],
        type: BitcoinAbiTypes.Function,
    },
    ...FrenForgeEvents,
    ...OP_NET_ABI,
];

export default FrenForgeAbi;
