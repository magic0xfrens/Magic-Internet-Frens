"""List all Telegram groups/channels you're in so you can find the correct IDs."""

import os
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient
from telethon.tl.types import Channel, Chat

load_dotenv(Path(__file__).parent / ".env")

API_ID = os.getenv("TELEGRAM_API_ID", "")
API_HASH = os.getenv("TELEGRAM_API_HASH", "")

client = TelegramClient("tg_scraper_session", int(API_ID), API_HASH)


async def main():
    await client.start()
    print("Logged in. Listing your groups/channels...\n")
    print(f"{'ID':<20} {'Type':<12} {'Title'}")
    print("-" * 70)

    async for dialog in client.iter_dialogs():
        entity = dialog.entity
        if isinstance(entity, (Channel, Chat)):
            etype = "supergroup" if getattr(entity, "megagroup", False) else (
                "channel" if isinstance(entity, Channel) else "group"
            )
            print(f"{dialog.id:<20} {etype:<12} {dialog.title}")

    await client.disconnect()


client.loop.run_until_complete(main())
