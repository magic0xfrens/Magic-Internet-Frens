import { ABIDataTypes, BitcoinAbiTypes, OP_NET_ABI } from 'opnet';

export const FrenMarketEvents = [];

export const FrenMarketAbi = [
    {
        name: 'setNFTContract',
        inputs: [{ name: 'nftContract', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeRecipient',
        inputs: [{ name: 'recipient', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeRecipientHash',
        inputs: [{ name: 'hash', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'setFeeBps',
        inputs: [{ name: 'bps', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'listNFT',
        inputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHash', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
        ],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'cancelListing',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'reserveBuy',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'claimReserved',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'cancelReservation',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [{ name: 'success', type: ABIDataTypes.BOOL }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getListing',
        inputs: [{ name: 'tokenId', type: ABIDataTypes.UINT256 }],
        outputs: [
            { name: 'seller', type: ABIDataTypes.ADDRESS },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'active', type: ABIDataTypes.BOOL },
            { name: 'reservedBy', type: ABIDataTypes.UINT256 },
            { name: 'reserveExpiry', type: ABIDataTypes.UINT256 },
        ],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getActiveListingCount',
        inputs: [],
        outputs: [{ name: 'count', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getListingByIndex',
        inputs: [{ name: 'index', type: ABIDataTypes.UINT256 }],
        outputs: [
            { name: 'tokenId', type: ABIDataTypes.UINT256 },
            { name: 'seller', type: ABIDataTypes.ADDRESS },
            { name: 'priceSats', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrHi', type: ABIDataTypes.UINT256 },
            { name: 'sellerAddrLo', type: ABIDataTypes.UINT256 },
            { name: 'reservedBy', type: ABIDataTypes.UINT256 },
            { name: 'reserveExpiry', type: ABIDataTypes.UINT256 },
        ],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getFeeBps',
        inputs: [],
        outputs: [{ name: 'bps', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    {
        name: 'getBuyerFeeBps',
        inputs: [{ name: 'buyer', type: ABIDataTypes.ADDRESS }],
        outputs: [{ name: 'feeBps', type: ABIDataTypes.UINT256 }],
        type: BitcoinAbiTypes.Function,
    },
    ...FrenMarketEvents,
    ...OP_NET_ABI,
];

export default FrenMarketAbi;
