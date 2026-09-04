"""
Invite members from the deduplicated CSV into Magic Internet Frens Community.

Resolves users by @username. Verifies each add by checking membership after invite.
Supports rotating phone numbers via CLI argument.

Usage:
  python3 invite_members.py +351XXXXXXXXX
"""

import asyncio
import csv
import os
import random
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient, errors
from telethon.tl.functions.channels import InviteToChannelRequest, GetParticipantRequest
from telethon.tl.types import PeerChannel
from telethon.errors import UserNotParticipantError

load_dotenv(Path(__file__).parent / ".env")

# ── Config ────────────────────────────────────────────────────────────
API_ID = os.getenv("TELEGRAM_API_ID", "")
API_HASH = os.getenv("TELEGRAM_API_HASH", "")

TARGET_GROUP_ID = -1001584055574  # Magic Internet Frens Community
CSV_FILE = Path(__file__).parent / "telegram_members_deduped.csv"

# Delay between each invite (seconds)
MIN_DELAY = 25
MAX_DELAY = 45

# Batch pauses
BATCH_SIZE = 10
BATCH_PAUSE_MIN = 180
BATCH_PAUSE_MAX = 420

MAX_ADDS_PER_RUN = 9999
# ─────────────────────────────────────────────────────────────────────


def load_members(csv_path):
    """Load members from the deduplicated CSV. Only those with usernames."""
    with_username = []
    without_username = []

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["is_bot"] == "True":
                continue
            if row["username"]:
                with_username.append({
                    "user_id": int(row["user_id"]),
                    "username": row["username"],
                    "first_name": row["first_name"],
                })
            else:
                without_username.append({
                    "user_id": int(row["user_id"]),
                    "first_name": row["first_name"],
                })

    return with_username, without_username


def load_log(log_path):
    """Load processed usernames and their status from log."""
    if not log_path.exists():
        return {}
    result = {}
    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|", 1)
            username = parts[0]
            status = parts[1] if len(parts) > 1 else "ok"
            result[username] = status
    return result


def log_entry(log_path, username, status):
    with open(log_path, "a") as f:
        f.write(f"{username}|{status}\n")


async def check_membership(client, target, user):
    """Check if a user is actually in the target group."""
    try:
        await client(GetParticipantRequest(target, user))
        return True
    except UserNotParticipantError:
        return False
    except Exception:
        return None  # unknown


async def main():
    if len(sys.argv) < 2:
        print("Usage: python3 invite_members.py +351XXXXXXXXX")
        print("  Pass the phone number to use for inviting.")
        sys.exit(1)

    phone = sys.argv[1].replace(" ", "")
    # Session name based on phone so each number gets its own session
    session_name = f"tg_invite_{phone.replace('+', '')}"

    if not API_ID or not API_HASH:
        print("ERROR: Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env")
        sys.exit(1)

    log_path = Path(__file__).parent / "added_members.log"
    processed = load_log(log_path)

    with_username, without_username = load_members(CSV_FILE)

    # Filter out already processed (any status) and shuffle
    remaining = [m for m in with_username if m["username"] not in processed]
    random.shuffle(remaining)

    print(f"CSV members with username: {len(with_username)}")
    print(f"CSV members without username: {len(without_username)} (skipped)")
    print(f"Already processed: {len(processed)}")
    print(f"  - confirmed added: {sum(1 for s in processed.values() if s == 'confirmed')}")
    print(f"  - silent fail: {sum(1 for s in processed.values() if s == 'silent_fail')}")
    print(f"  - skipped: {sum(1 for s in processed.values() if s not in ('confirmed', 'silent_fail'))}")
    print(f"Remaining to add: {len(remaining)}")

    if not remaining:
        print("\nAll members with usernames have been processed!")
        return

    # Connect
    client = TelegramClient(session_name, int(API_ID), API_HASH)
    await client.start(phone=phone)
    print(f"\nLogged in as {phone} at {datetime.now().isoformat()}")

    # Resolve target group
    channel_id = int(str(TARGET_GROUP_ID).replace("-100", "", 1))
    target = await client.get_entity(PeerChannel(channel_id))
    print(f"Target group: {target.title}")
    print(f"Starting invites...\n")

    added_count = 0
    failed_count = 0
    skipped_count = 0
    silent_fail_count = 0

    for i, member in enumerate(remaining):
        if added_count >= MAX_ADDS_PER_RUN:
            break

        username = member["username"]
        print(f"[{i+1}/{len(remaining)}] Adding @{username}...", end=" ")

        try:
            user = await client.get_input_entity(username)
            await client(InviteToChannelRequest(target, [user]))

            # Verify they were actually added
            await asyncio.sleep(2)
            is_member = await check_membership(client, target, user)

            if is_member is True:
                print("CONFIRMED")
                log_entry(log_path, username, "confirmed")
                added_count += 1
            elif is_member is False:
                print("SILENT FAIL (invite succeeded but user not in group)")
                log_entry(log_path, username, "silent_fail")
                silent_fail_count += 1
            else:
                print("OK (couldn't verify)")
                log_entry(log_path, username, "unverified")
                added_count += 1

        except errors.FloodWaitError as e:
            print(f"FLOOD WAIT — {e.seconds}s. Pausing...")
            await asyncio.sleep(e.seconds + 10)
            try:
                user = await client.get_input_entity(username)
                await client(InviteToChannelRequest(target, [user]))
                print("OK (after wait)")
                log_entry(log_path, username, "unverified")
                added_count += 1
            except Exception as e2:
                print(f"FAILED after wait: {e2}")
                failed_count += 1

        except errors.UserPrivacyRestrictedError:
            print("SKIPPED (privacy settings)")
            log_entry(log_path, username, "privacy")
            skipped_count += 1

        except errors.UserNotMutualContactError:
            print("SKIPPED (not mutual contact)")
            log_entry(log_path, username, "not_mutual")
            skipped_count += 1

        except errors.UserChannelsTooMuchError:
            print("SKIPPED (user in too many groups)")
            log_entry(log_path, username, "too_many_groups")
            skipped_count += 1

        except errors.ChatAdminRequiredError:
            print("ERROR: Need invite permissions in the target group!")
            break

        except errors.PeerFloodError:
            print("PEER FLOOD — account rate-limited. Try again later (or use a different number).")
            break

        except errors.UserKickedError:
            print("SKIPPED (banned from group)")
            log_entry(log_path, username, "banned")
            skipped_count += 1

        except errors.UserAlreadyParticipantError:
            print("SKIPPED (already in group)")
            log_entry(log_path, username, "already_member")
            skipped_count += 1

        except (ValueError, errors.UsernameNotOccupiedError):
            print("SKIPPED (username not found)")
            log_entry(log_path, username, "not_found")
            skipped_count += 1

        except Exception as e:
            print(f"FAILED: {type(e).__name__}: {e}")
            log_entry(log_path, username, f"error:{type(e).__name__}")
            failed_count += 1

        # Batch pause
        if added_count > 0 and added_count % BATCH_SIZE == 0:
            pause = random.uniform(BATCH_PAUSE_MIN, BATCH_PAUSE_MAX)
            print(f"\n  -- Batch pause: {pause/60:.1f} min --\n")
            await asyncio.sleep(pause)
        else:
            await asyncio.sleep(random.uniform(MIN_DELAY, MAX_DELAY))

    print(f"\n── Summary ──")
    print(f"  Confirmed added: {added_count}")
    print(f"  Silent fails:    {silent_fail_count}")
    print(f"  Skipped:         {skipped_count}")
    print(f"  Failed:          {failed_count}")
    print(f"\nRun again with same or different number to continue.")

    await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
