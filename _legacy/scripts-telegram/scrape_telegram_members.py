"""
Scrape members from two Telegram groups and export a deduplicated list.

Prerequisites:
  1. pip install telethon python-dotenv
  2. Get API credentials from https://my.telegram.org
  3. Fill in scripts/.env with your group usernames

Usage:
  python scrape_telegram_members.py
"""

import asyncio
import csv
import os
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient
from telethon.tl.functions.channels import GetParticipantsRequest
from telethon.tl.types import ChannelParticipantsSearch, PeerChannel

# Load .env from the same directory as this script
load_dotenv(Path(__file__).parent / ".env")

# ── Config ────────────────────────────────────────────────────────────
API_ID = os.getenv("TELEGRAM_API_ID", "")
API_HASH = os.getenv("TELEGRAM_API_HASH", "")

# Group usernames (without @) or invite links or numeric IDs
GROUP_1 = os.getenv("TELEGRAM_GROUP_1", "")  # e.g. "mygroup1"
GROUP_2 = os.getenv("TELEGRAM_GROUP_2", "")  # e.g. "mygroup2"

OUTPUT_FILE = "telegram_members_deduped.csv"
SESSION_NAME = "tg_scraper_session"
# ─────────────────────────────────────────────────────────────────────


def parse_group_id(group_str):
    """Convert a group ID string to a PeerChannel if it looks like a numeric ID."""
    try:
        gid = int(group_str)
        # Telegram supergroup IDs start with -100; strip it to get the channel ID
        if gid < 0:
            channel_id = int(str(gid).replace("-100", "", 1))
        else:
            channel_id = gid
        return PeerChannel(channel_id)
    except ValueError:
        # Not numeric — return as-is (username or invite link)
        return group_str


async def get_all_participants(client, group):
    """Fetch all members from a group/channel."""
    peer = parse_group_id(group)
    entity = await client.get_entity(peer)
    print(f"  Fetching members from: {getattr(entity, 'title', group)}")

    members = []
    offset = 0
    batch_size = 200

    while True:
        participants = await client(GetParticipantsRequest(
            channel=entity,
            filter=ChannelParticipantsSearch(""),
            offset=offset,
            limit=batch_size,
            hash=0,
        ))

        if not participants.users:
            break

        for user in participants.users:
            members.append({
                "user_id": user.id,
                "username": user.username or "",
                "first_name": user.first_name or "",
                "last_name": user.last_name or "",
                "phone": user.phone or "",
                "is_bot": user.bot or False,
                "source_group": getattr(entity, "title", str(group)),
            })

        offset += len(participants.users)
        print(f"    Fetched {offset} members so far...")

        if offset >= participants.count:
            break

    print(f"  Total: {len(members)} members")
    return members


def deduplicate(members_1, members_2):
    """Merge two member lists, deduplicate by user_id, track which groups they belong to."""
    combined = {}

    for m in members_1:
        uid = m["user_id"]
        combined[uid] = {**m, "groups": m["source_group"]}

    for m in members_2:
        uid = m["user_id"]
        if uid in combined:
            # Member exists in both groups
            combined[uid]["groups"] += f" | {m['source_group']}"
        else:
            combined[uid] = {**m, "groups": m["source_group"]}

    return list(combined.values())


def export_csv(members, filename):
    """Write deduplicated members to CSV."""
    fieldnames = ["user_id", "username", "first_name", "last_name", "phone", "is_bot", "groups"]

    with open(filename, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for m in members:
            writer.writerow({k: m[k] for k in fieldnames})

    print(f"\nExported {len(members)} unique members to {filename}")


async def main():
    if not API_ID or not API_HASH:
        print("ERROR: Set TELEGRAM_API_ID and TELEGRAM_API_HASH environment variables.")
        print("  Get them from https://my.telegram.org")
        sys.exit(1)

    if not GROUP_1 or not GROUP_2:
        print("ERROR: Set TELEGRAM_GROUP_1 and TELEGRAM_GROUP_2 environment variables.")
        print("  Use group usernames (without @), invite links, or numeric IDs.")
        sys.exit(1)

    client = TelegramClient(SESSION_NAME, int(API_ID), API_HASH)
    await client.start()

    print(f"Logged in. Scraping at {datetime.now().isoformat()}\n")

    # Fetch members from both groups
    print(f"[Group 1] {GROUP_1}")
    members_1 = await get_all_participants(client, GROUP_1)

    print(f"\n[Group 2] {GROUP_2}")
    members_2 = await get_all_participants(client, GROUP_2)

    # Deduplicate
    unique = deduplicate(members_1, members_2)

    overlap = (len(members_1) + len(members_2)) - len(unique)
    print(f"\n── Summary ──")
    print(f"  Group 1: {len(members_1)} members")
    print(f"  Group 2: {len(members_2)} members")
    print(f"  Overlap: {overlap} members in both groups")
    print(f"  Unique:  {len(unique)} total unique members")

    # Export
    export_csv(unique, OUTPUT_FILE)

    await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
