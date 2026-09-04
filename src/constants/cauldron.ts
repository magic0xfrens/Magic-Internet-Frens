export const CAULDRON_CONTRACTS = {
    regtest: {
        CAULDRON_REGISTRY: '0x...',
        CAULDRON_VAULT: '0x...',
        VOLUME_ORACLE: '0x...',
        NFT: '0x...',
    },
    testnet: {
        CAULDRON_REGISTRY: '0x...',
        CAULDRON_VAULT: '0x...',
        VOLUME_ORACLE: '0x...',
        NFT: '0x...',
    },
    mainnet: {
        CAULDRON_REGISTRY: '0x...',
        CAULDRON_VAULT: '0x...',
        VOLUME_ORACLE: '0x...',
        NFT: '0x...',
    },
};

// The eternal creatures summoned from the Cauldron
export const CAULDRON_CREATURES = [
    { gen: 1, name: 'Magic Internet Token', symbol: 'MIT', emoji: '🔥', color: '#FF4500', spell: 'Ignis Aeternus' },
    { gen: 2, name: 'Ethereal Spirit', symbol: 'SPIRIT', emoji: '✨', color: '#FFA500', spell: 'Anima Perpetua' },
    { gen: 3, name: 'Shadow Wraith', symbol: 'WRAITH', emoji: '🌪️', color: '#808080', spell: 'Umbra Infinitus' },
    { gen: 4, name: 'Infernal Beast', symbol: 'BEAST', emoji: '🌋', color: '#DC143C', spell: 'Bestia Aeterna' },
    { gen: 5, name: 'Astral Entity', symbol: 'ASTRAL', emoji: '💫', color: '#9370DB', spell: 'Astra Immortalis' },
    { gen: 6, name: 'Storm Elemental', symbol: 'STORM', emoji: '⚡', color: '#FFD700', spell: 'Tempestas Perpetua' },
];

export const CAULDRON_CONFIG = {
    MAX_SPELL_CASTERS: 777, // 777 Magic Internet Wizard Frens
    DEATH_THRESHOLD_BTC: 0.01,
    INITIAL_LIQUIDITY_TOKENS: 777,
    INITIAL_LIQUIDITY_BTC: 1,
    BLOCKS_PER_24H: 144,
    SPELL_CASTER_TAX: 0, // 0% for NFT holders
    NON_CASTER_TAX: 3, // 3% for non-holders
};

export const SPELL_INCANTATION = `
    By the power of 777 Magic Internet Wizard Frens,
    We gather at the Cauldron's edge,
    And cast the eternal spell:

    "From the void we summon thee,
     Creature of infinity,
     Born to live and die and rise,
     Eternal through the endless skies!"
`;
