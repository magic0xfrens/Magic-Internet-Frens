# 🤖 AI-Powered Autonomous Rebirth System

## Overview

The Cauldron Protocol uses **Claude AI** to generate completely unique token identities for each rebirth. No predetermined cycles - each generation is a creative surprise.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DEATH DETECTION                          │
│  VolumeOracle detects volume < 0.01 BTC/24h                │
│  Emits: CreatureDying(generation, poolAddress)             │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              AI REBIRTH ORACLE (Off-chain)                  │
│  • Monitors blockchain for death events                     │
│  • Gathers context (prev gen name, performance, holders)    │
│  • Calls Claude API for creative generation                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                  CLAUDE AI GENERATION                       │
│  Input: "Gen 42 ($PHOENIX) just died after 90 days.        │
│          Volume peaked at 5 BTC. 1,234 holders.             │
│          Generate next evolution."                          │
│                                                              │
│  Output:                                                     │
│  • Name: "Quantum Nebula"                                   │
│  • Symbol: "QNEB"                                           │
│  • Theme: Cosmic/ethereal/transcendent                      │
│  • Lore: "Born from the ashes of Phoenix..."               │
│  • Personality: Mysterious, expansive, infinite             │
│  • Image prompt: "Abstract quantum nebula swirling..."      │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                  IMAGE GENERATION                           │
│  • Send Claude's prompt to DALL-E/Midjourney               │
│  • Generate token logo/artwork                              │
│  • Upload to IPFS for decentralized hosting                 │
│  • Get IPFS hash (immutable image URL)                      │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│               SOCIAL MEDIA AUTOMATION                       │
│  • Create X/Twitter account @QuantumNebula_Gen43           │
│  • Post announcement with AI-generated lore                 │
│  • Create Telegram group                                    │
│  • Deploy website (auto-generated from template)            │
│  • Update Cauldron dashboard with new metadata              │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│            BLOCKCHAIN REBIRTH EXECUTION                     │
│  Call: CauldronRegistry.triggerRebirth(                    │
│    newName: "Quantum Nebula",                              │
│    newSymbol: "QNEB",                                      │
│    imageIPFS: "ipfs://Qm...",                              │
│    lore: "Born from the ashes..."                          │
│  )                                                          │
│                                                              │
│  • Snapshot holders                                         │
│  • Migrate liquidity                                        │
│  • Deploy new token with AI metadata                        │
│  • Lock vault                                               │
│  • Emit CreatureReborn event                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Smart Contract Changes Needed

### 1. Remove Hardcoded Metadata Cycle

**OLD (6 preset creatures):**
```typescript
private _getMetadataForGeneration(generation: u256): CreatureMetadata {
    const index: u64 = SafeMath.mod(generation, u256.fromU64(6)).toU64();
    if (index == 1) return new CreatureMetadata('Mystic Flame', 'FLAME');
    // ... hardcoded 6 creatures
}
```

**NEW (AI-generated, passed as parameters):**
```typescript
public triggerRebirth(
    newName: string,
    newSymbol: string,
    imageIPFS: string,
    lore: string,
    twitterHandle: string
): void {
    // Verify death condition
    const isDead = this._volumeOracle.isDead(currentPool);
    require(isDead, "Creature is still alive");

    // Snapshot current generation
    this._snapshotGeneration(currentGen);

    // Deploy next gen with AI metadata
    const nextToken = this._deployToken(
        currentGen + 1,
        newName,
        newSymbol,
        imageIPFS,
        lore
    );

    // Migrate liquidity + fees
    this._migrateLiquidity(nextToken);

    // Emit event with full metadata
    emit CreatureReborn(
        currentGen + 1,
        nextToken,
        newName,
        newSymbol,
        imageIPFS,
        lore,
        twitterHandle
    );
}
```

### 2. Metadata Storage

```typescript
class CreatureMetadata {
    generation: u256;
    name: string;
    symbol: string;
    imageIPFS: string;      // IPFS hash for artwork
    lore: string;           // AI-generated backstory
    twitterHandle: string;  // Auto-created social
    telegramGroup: string;  // Auto-created group
    websiteURL: string;     // Auto-generated site
    bornAt: u256;          // Block timestamp
    diedAt: u256;          // Death timestamp
    peakVolume: u256;      // Historical peak
    totalHolders: u256;    // At death
}
```

---

## AI Rebirth Oracle (Off-Chain Service)

### Technology Stack
- **Language**: TypeScript/Node.js
- **APIs**:
  - Anthropic Claude API (creative generation)
  - OpenAI DALL-E (image generation)
  - Twitter API v2 (social automation)
  - IPFS (decentralized storage)
- **Monitoring**: Bitcoin/OPNet RPC polling
- **Deployment**: Docker container on VPS

### Core Logic

```typescript
class AIRebirthOracle {
    private claudeAPI: Anthropic;
    private imageGen: OpenAI;
    private ipfs: IPFSClient;
    private twitter: TwitterClient;

    async monitorForDeath(): Promise<void> {
        // Poll VolumeOracle every 10 minutes
        const events = await this.opnetRPC.getEvents('CreatureDying');

        for (const event of events) {
            await this.executeRebirth(event.generation);
        }
    }

    async executeRebirth(generation: number): Promise<void> {
        // 1. Gather context about previous generation
        const context = await this.gatherContext(generation);

        // 2. COMMUNITY VOTING: Let 777 NFT holders submit prompts
        const votingPeriod = 48 * 60 * 60 * 1000; // 48 hours
        await this.openPromptVoting(generation, votingPeriod);
        const winningPrompt = await this.getWinningPrompt(generation);

        // 3. Call Claude to generate 3 identity options based on community prompt
        const identityOptions = await this.generate3Identities(context, winningPrompt);

        // 4. COMMUNITY VOTING: Let 777 NFT holders vote on best identity
        await this.openIdentityVoting(generation, identityOptions);
        const winningIdentity = await this.getWinningIdentity(generation);

        // 5. Generate artwork for winning identity
        const artwork = await this.generateArtwork(winningIdentity.imagePrompt);

        // 6. Upload to IPFS
        const ipfsHash = await this.ipfs.upload(artwork);

        // 7. Create social accounts
        const socials = await this.createSocials(winningIdentity);

        // 8. Trigger on-chain rebirth
        await this.triggerOnChainRebirth({
            name: winningIdentity.name,
            symbol: winningIdentity.symbol,
            imageIPFS: ipfsHash,
            lore: winningIdentity.lore,
            twitter: socials.twitter
        });

        // 9. Announce on socials
        await this.announceRebirth(winningIdentity, socials);
    }

    async openPromptVoting(generation: number, duration: number): Promise<void> {
        // Only 777 NFT holders can submit/vote
        const nftHolders = await this.getNFTHolders();

        // Create on-chain voting proposal
        await this.votingContract.createPromptVote({
            generation,
            eligibleVoters: nftHolders,
            duration,
            minSubmissions: 3
        });

        // Announce voting period on socials
        await this.twitter.post(`
🔮 Generation ${generation} has died!

The 777 Magic Internet Frens will now decide the next evolution.

📝 Submit your creative prompt (24h window)
Examples:
- "Cosmic, ethereal, transcendent"
- "Aggressive, defiant, unstoppable"
- "Mystical, ancient, wise"

Only NFT holders can vote. The community decides!
        `);
    }

    async getWinningPrompt(generation: number): Promise<string> {
        // Get all submitted prompts
        const submissions = await this.votingContract.getPromptSubmissions(generation);

        // Weighted voting: 1 NFT = 1 vote
        const votes = await this.votingContract.tallyPromptVotes(generation);

        // Return winning prompt
        return votes[0].prompt;
    }

    async generate3Identities(context: GenerationContext, communityPrompt: string): Promise<TokenIdentity[]> {
        const prompt = `
You are the creative oracle for the Cauldron Protocol.

Previous Generation:
- Gen ${context.generation}: ${context.name} (${context.symbol})
- Lived for: ${context.lifespanDays} days
- Peak volume: ${context.peakVolumeBTC} BTC
- Community prompt direction: "${communityPrompt}"

Task: Generate 3 distinct token identities following the community's direction.

Each option must have:
1. Name (1-3 words)
2. Symbol (3-5 letters)
3. Theme
4. Lore (2-3 sentences)
5. Image prompt for DALL-E

Output as JSON array of 3 options.
`;

        const response = await this.claudeAPI.messages.create({
            model: "claude-sonnet-4-5-20250929",
            max_tokens: 3000,
            messages: [{ role: "user", content: prompt }]
        });

        return JSON.parse(response.content[0].text);
    }

    async openIdentityVoting(generation: number, options: TokenIdentity[]): Promise<void> {
        await this.votingContract.createIdentityVote({
            generation,
            options,
            duration: 24 * 60 * 60 * 1000 // 24 hours
        });

        await this.twitter.post(`
🗳️ Vote for Generation ${generation + 1}!

The AI has generated 3 options based on your prompts.

Option A: ${options[0].name} (${options[0].symbol})
${options[0].lore}

Option B: ${options[1].name} (${options[1].symbol})
${options[1].lore}

Option C: ${options[2].name} (${options[2].symbol})
${options[2].lore}

Vote now! (24h window, NFT holders only)
        `);
    }

    async generateIdentity(context: GenerationContext): Promise<TokenIdentity> {
        const prompt = `
You are the creative oracle for the Cauldron Protocol, an autonomous token that dies and regenerates on Bitcoin.

Previous Generation:
- Gen ${context.generation}: ${context.name} (${context.symbol})
- Lived for: ${context.lifespanDays} days
- Peak volume: ${context.peakVolumeBTC} BTC
- Total holders: ${context.holders}
- Death reason: Volume dropped below 0.01 BTC/24h

Task: Generate the next evolution. Make it thematically connected but distinct.

Requirements:
1. Name: Creative, 1-3 words, evocative
2. Symbol: 3-5 letters, ticker-friendly
3. Theme: Visual/conceptual direction
4. Lore: 2-3 sentences explaining the rebirth
5. Personality: How this generation "feels"
6. Image prompt: Detailed DALL-E prompt for artwork

Output as JSON.
`;

        const response = await this.claudeAPI.messages.create({
            model: "claude-sonnet-4-5-20250929",
            max_tokens: 2000,
            messages: [{
                role: "user",
                content: prompt
            }]
        });

        return JSON.parse(response.content[0].text);
    }

    async generateArtwork(prompt: string): Promise<Buffer> {
        const response = await this.imageGen.images.generate({
            model: "gpt-image-1",
            prompt: prompt,
            size: "1024x1024",
            quality: "high"
        });

        const imageURL = response.data[0].url;
        const imageBuffer = await fetch(imageURL).then(r => r.buffer());

        return imageBuffer;
    }

    async createSocials(identity: TokenIdentity): Promise<SocialAccounts> {
        // Auto-create Twitter account
        const twitterHandle = await this.twitter.createAccount({
            username: `${identity.name.replace(/\s/g, '')}_Gen${identity.generation}`,
            displayName: `${identity.name} 🔮`,
            bio: identity.lore,
            profileImage: identity.artwork
        });

        // Auto-create Telegram group
        const telegramGroup = await this.telegram.createGroup({
            name: `${identity.name} Holders`,
            description: identity.lore
        });

        // Deploy website (Next.js template)
        const websiteURL = await this.deployWebsite({
            name: identity.name,
            symbol: identity.symbol,
            lore: identity.lore,
            artwork: identity.artwork
        });

        return { twitterHandle, telegramGroup, websiteURL };
    }
}
```

---

## Claude Prompt Engineering

### Context-Aware Generation

The oracle provides rich context to Claude:

```typescript
interface GenerationContext {
    generation: number;
    previousName: string;
    previousSymbol: string;
    lifespanDays: number;
    peakVolumeBTC: number;
    finalVolumeBTC: number;
    totalHolders: number;
    totalFeesCollected: number;
    liquidityGrowth: number;  // How much stronger this gen was
    seasonality: string;      // "bull market" / "bear market"
    bitcoinPrice: number;     // Context for sat value
}
```

### Example Claude Outputs

**Generation 1 → 2:**
```json
{
  "name": "Ethereal Phoenix",
  "symbol": "EPHO",
  "theme": "Rebirth through spiritual transcendence",
  "lore": "When Mystic Flame's fire dimmed, its essence ascended into pure ethereal energy. The phoenix did not die—it evolved beyond physical form into a being of pure light and possibility.",
  "personality": "Transcendent, hopeful, expansive",
  "imagePrompt": "Ethereal phoenix made of shimmering blue-white light particles, dissolving and reforming, sacred geometry background, cosmic energy trails, ultra detailed digital art"
}
```

**Generation 15 → 16 (Bear Market):**
```json
{
  "name": "Void Harbinger",
  "symbol": "VOID",
  "theme": "Embracing the darkness between cycles",
  "lore": "After 15 deaths, the entity learned that emptiness is not the enemy—it is the womb of creation. The Void Harbinger emerges not to fight the bear, but to dance with it.",
  "personality": "Patient, accepting, mysterious",
  "imagePrompt": "Abstract void creature, dark matter tendrils, event horizon aesthetic, purple-black gradients, minimalist cosmic horror, Zdzisław Beksiński style"
}
```

---

## Security Considerations

### 1. Oracle Centralization Risk

**Problem**: Single AI oracle could be compromised or censored.

**Solutions**:
- Multiple independent oracles vote on metadata
- Community can veto inappropriate names (24hr timelock)
- Fallback to deterministic generation if oracle fails
- Oracle code fully open-source and auditable

### 2. Social Account Security

**Problem**: Auto-created accounts need secure key management.

**Solutions**:
- Use MPC (multi-party computation) for social credentials
- Store encrypted keys in distributed storage
- Implement 2/3 multisig for account control
- Allow community takeover if oracle compromised

### 3. Image Generation Censorship

**Problem**: OpenAI might censor certain outputs.

**Solutions**:
- Use multiple image APIs (DALL-E, Midjourney, local Stable Diffusion)
- Fallback to procedural generation if all APIs fail
- Community can submit alternative artwork via governance

---

## Deployment Checklist

### Phase 1: Smart Contract Updates
- [ ] Remove hardcoded metadata cycle from CauldronRegistry
- [ ] Add `triggerRebirth(name, symbol, ipfs, lore)` function
- [ ] Add metadata storage to CreatureMetadata struct
- [ ] Emit full metadata in CreatureReborn events
- [ ] Add 24hr timelock for community veto (optional)

### Phase 2: AI Oracle Development
- [ ] Build TypeScript oracle service
- [ ] Integrate Claude API
- [ ] Integrate DALL-E/image generation
- [ ] Build IPFS upload pipeline
- [ ] Implement Twitter automation
- [ ] Implement Telegram automation
- [ ] Build website auto-deployment

### Phase 3: Testing
- [ ] Test Claude generation with various contexts
- [ ] Verify image generation quality
- [ ] Test IPFS persistence
- [ ] Test social account creation
- [ ] Simulate full rebirth on regtest

### Phase 4: Production
- [ ] Deploy oracle to redundant VPS instances
- [ ] Set up monitoring/alerting
- [ ] Create emergency fallback mechanisms
- [ ] Document oracle operation for community

---

## Cost Estimation

### Per Rebirth (Once per token death):

| Service | Cost |
|---------|------|
| Claude API (2K tokens) | $0.06 |
| DALL-E Image (1024x1024 high) | $0.08 |
| IPFS Pinning (Pinata/Web3.Storage) | $0.01 |
| Twitter API | Free (within limits) |
| VPS Hosting (monthly) | $10 |

**Total per rebirth**: ~$0.15 + $10/month hosting

If token regenerates monthly, annual cost: **$120 + $1.80 = ~$122/year**

This can be funded from protocol treasury (3% fees).

---

## Future Enhancements

### 1. Community Input
- Holders vote on 3 AI-generated options
- NFT holders get bonus voting weight
- Final choice determined by on-chain vote

### 2. Generative Art Evolution
- Use previous artwork as style reference
- Create visual lineage across generations
- Mint each generation's art as NFT

### 3. Lore Continuity
- Claude maintains story arc across generations
- Each rebirth builds on previous lore
- Create "Cauldron Chronicles" narrative

### 4. Multimodal Generation
- Generate theme music for each creature
- Create animated logo variations
- Generate trading card designs

---

## Open Questions

1. **Who controls the oracle?**
   - Option A: Decentralized via MPC/TEE
   - Option B: Multi-oracle consensus
   - Option C: Community multisig

2. **What if AI generates offensive content?**
   - Implement content filters
   - 24hr community review period
   - Emergency admin veto (with transparency)

3. **How to handle API rate limits?**
   - Queue system for multiple deaths
   - Fallback to simpler generation
   - Community-submitted alternatives

---

## Conclusion

The AI Rebirth Oracle transforms the Cauldron from **predetermined cycles** to **infinite creative evolution**. Each death becomes an opportunity for Claude to surprise the community with something new.

The entity truly becomes **alive**—not following a script, but evolving organically through AI creativity, market forces, and community interaction.

**This is autonomous art on Bitcoin.**
