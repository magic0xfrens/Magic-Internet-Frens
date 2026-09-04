#!/usr/bin/env python3
"""
Telegram Desktop - Add Members Automation (v4)
===============================================
- CoreGraphics events for reliable mouse/keyboard on macOS
- Clipboard paste (no raw keypresses = no emoji popups)
- Timed countdowns for position capture (no Enter key needed)
- Screenshot + Claude CLI verification before clicking any result

Usage:
  python3 add_telegram_members.py           # start from beginning
  python3 add_telegram_members.py 50        # resume from index 50

Abort: Ctrl+C in terminal
"""

import time
import sys
import re
import subprocess
import pyperclip
import Quartz
from AppKit import NSEvent

# ── Timing (seconds) ─────────────────────────────────────────────────
CALIBRATION_WAIT = 8    # Time to position mouse during calibration
SEARCH_WAIT = 2.0       # Wait for Telegram search results to load
AFTER_CLICK = 0.7       # Wait after clicking a result
AFTER_CLEAR = 0.3       # Wait after clearing search field
BEFORE_START = 5        # Countdown before automation begins

SCREENSHOT_PATH = "/tmp/tg_verify.png"

USERNAMES = [
    "fvckn390", "bc1q1", "petersgu", "MOTOManChuck", "Educrypto2",
    "Tommex7", "XwhitewindowX", "VrychithmosLiontari", "asig186", "Joaoo93",
    "Arl419", "yuling03", "MichaelSherlock", "krainxc", "barikuta",
    "spinningbas", "rzbtcmaxi", "DegeNi", "bc1poseidon", "rrr0817282",
    "felix1688", "ProspectingCat", "dudemyguy", "orscar142857", "ppands",
    "coryinsiderz", "bensomores", "tupacmoon", "Happypath404", "OxGrug",
    "Guy_from_kathmandu", "JeffreySiii", "Yasseen95100", "Lil_Dougall",
    "Nyxgod", "KemarKecin", "chief_riverboat", "fckftmny", "TopNoxx",
    "Scruffmcbuff", "ShamanChaman", "tgeus_cromis", "Matt_the_vulture",
    "pema_mikes", "adoranths", "bc1juul", "bzbsbsbnn", "OxYukkii",
    "awesomekush", "chadmasterxbt", "RektDegenerate", "guunduul",
    "xiguabababa", "DMorganETH", "jonnyhimalaya", "penderito", "Delta8970",
    "MotusAK", "mazebitcoin", "TopherM", "OxElimelech", "TheWizard80",
    "ilminghello", "Ciuana", "captainfatcat", "Big_Shout", "willowbreem",
    "Hridoiyy", "future7896", "trapnscam1", "fool799", "o0o0o00o0o1",
    "Maryfunmi", "TitiusMaximus", "bwgen2", "iamthelizardking123",
    "CodeineXBT", "Ruggedbydiversityxbt", "Looper001", "MikeV666",
    "TwitchRaz", "wavycrypt2", "azoulammtooro", "Gachiato", "tapiocabtc",
    "Kryptonite_the_real_one", "Yo_ANnN", "franklinisbased002",
    "TheOneAndOnlyAllMight", "Apollo_231", "julerz12", "zorolamoto",
    "Jameswymer", "alyssaa77", "Mrelive23", "E9XBT", "aliciafinds",
    "StKelvin_02", "Vickkker", "Ceyzou", "Jansplin", "Devatron",
    "fanfiction919", "Hobert82", "SobyXBT", "AnArchOnIst",
    "EfficientFrontTier", "ignantly", "prof_writer", "KaleemCoinstore1",
    "linkystaystinky", "the_guy_from_brainyield", "killerdog7000",
    "shaka_soul_man", "z_y_x_o", "sshardull", "TheKingofChateau",
    "Sun_Spear", "dant3_btc", "koenanb", "yoounix", "Zac_pe", "casuwutg",
    "ogmercoxadv", "lil_dammy12345", "yellowb0y", "Thegooddev", "crptogrl2",
    "warlord_xyz", "Bluechipjpegeth", "degennQuant", "Stacco_ETH",
    "ritualramen", "Jamie_aDev", "HemmiGG", "vp10296", "ungupungu",
    "mattgroot", "doc_greenback", "abrahamlincoln69420", "Tacey1",
    "innov8tor", "ooostrateg", "WSaiH6VX", "Rolpheekkard", "sergiisukhanov",
    "Saanjana_Nikita", "jeffedj", "askobinks", "cute0x", "jelk0",
    "Stopppmee", "blazed_bison", "brehjd", "zacdoteth", "Blegsone",
    "shawnwer", "tim0the3", "RazzMaTazz0", "LJack121", "Libreearn",
    "wangjinshan", "sky2278", "GetAudited", "M7Bones", "JohannChan132",
    "notgranola", "bitbull888", "Tresast", "bopsy", "phylipjo2", "zkmike11",
    "toozwu", "biubiuQAQ", "RazeAgainst", "HONKAYO", "senior_bono",
    "HanzieX", "Pepedem676", "ataggart", "iam_balviin", "exexhuman",
    "Keepeeeeer", "nagasavas", "William_W", "rtunioka", "GreasyNutz69",
    "MR2muchBOOST", "p9598", "samoness", "zeggss", "BrickCityBass",
    "braxbraxbrax", "Xeni0", "acecrypsalt", "trubus_x", "tenertoyourtl",
    "notprocrypt", "Bitzim", "John00935", "EcologyofGrind", "StateOfSats",
    "BTCjennifer", "mrymmio", "bish543", "Haikeys", "TDV030", "dcfpascal",
    "Uju_Nzeh", "outbackhodler", "OxXinu", "LukidDreamer", "trubs_x",
    "OfficialARC", "normalperson04", "alexm012", "Khasper_D_G",
    "parallel369", "jpegbagholderx", "againes30", "NipSlip14",
    "inscriptioner", "bqntex", "MetroBooms", "zackbrenner", "bc1david",
    "DrLasagnaa", "crypto_cord", "Trulsh", "marie621", "jonnyw_ld",
    "stoneeffect0", "deep_xbt", "vito1900", "XKYQSY", "gumibera",
    "bigbluebears", "Big_Scosche", "jvale83", "dogoshiielstampede",
    "Jukemaestro", "samizerox", "Ddraig117", "Billy8oy", "zeroxcarnation",
    "ikinguking", "NewsyJohnson", "Ja_mie", "kingbootoshi", "tdrowe",
    "jiminycricketts_son_ric", "gammichan", "KingWhiskersVIIII",
    "gooogooogaaagaaa", "tokencell", "DrJayDD", "mahonebtc",
    "masterblueblue", "Rafles1a", "KingSalmon28", "yomasolomon",
    "michaeldees", "nameless22211", "jjnosss", "paradigmeth0", "rekt2richez",
    "godedTG", "pikaqiu676", "OpenCrabsMind", "pwnlord69", "zevza0",
    "JamieERC", "ihzn7", "pikaqiuxiaozi", "qtebe", "wintr_soljr",
    "tornguard", "The_real_BasedOG", "Su1fy", "Th_ony", "majumapanturu",
    "veloqx", "Li_King54", "HashBadgers420", "FigmentXBT", "ShogunKC",
    "Weptsons", "matt_h997", "Smartmerchant1", "dario2richx", "Rom_ulus",
    "Akandz360", "pedrolucio123", "ab2k21", "ImJustBrokeG", "Raging0x",
    "nevinyrral", "Rafaelx741", "zehxxx", "anemone2023", "Sereinwis_h",
    "Jonathan_moore1", "ch0mx2", "nerdmn1", "GAndRoses", "ling707070",
    "venzeg", "bigpappiuno", "d3v0t3dd", "Leorichy", "callereneth",
    "Kmr0x", "linocook", "icepeak88", "justzatila", "AutisticBuy",
    "condeNFT", "senzu_bro", "sicerzs", "svintu5", "miseryof", "lucasff40",
    "xorosho_O", "potajpeg", "wenxora", "Aar33199", "fooking_jpn",
    "ShimmyMadeIt", "chaotic_hell", "neededthis", "jonahfp", "swissknifeav",
    "mrdrank1", "coco_nunts", "Naughynerd", "sargez", "kritikalbtc",
    "defiparker", "Ferrunss", "nathanielem", "Lectronicaa", "abhitwoX",
    "ibraxblr", "glasderg", "CarterxD", "Eonbase", "Dandimonn", "duckkyy",
    "LaLiLuLeLi", "clu79", "Inthemaking", "rvy0345", "I_am_riley",
    "aresky67", "zgs5600", "TrencherBoss", "tanduy81", "hukusik",
    "lilchuddies", "redmart09", "Lswagg333", "Cocorn", "MediciFX",
    "omarrbts", "binancebully", "Cocoabuds", "nikit_ta23", "majoubijoub",
    "callmedavee", "rekt3877", "Bi5cUT", "luxcidi", "Democarh", "Swayszn11",
    "dontbelikefemi", "FUCKNORMALCORP", "onchainracist", "grappal",
    "imman0000", "KazokuNoTameNi", "yoprint", "begho0", "chaojidapao4",
    "styx_xo", "beastbased", "Cleary_7", "pepemaxi", "xbrazilzz",
    "Ranoboo", "cryptozi",
]


# ── Low-level macOS input (CoreGraphics) ─────────────────────────────

def cg_move(x, y):
    """Move mouse cursor."""
    ev = Quartz.CGEventCreateMouseEvent(
        None, Quartz.kCGEventMouseMoved, (x, y), 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)


def cg_click(x, y):
    """Move to position then click."""
    cg_move(x, y)
    time.sleep(0.08)
    ev = Quartz.CGEventCreateMouseEvent(
        None, Quartz.kCGEventLeftMouseDown, (x, y), 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
    time.sleep(0.05)
    ev = Quartz.CGEventCreateMouseEvent(
        None, Quartz.kCGEventLeftMouseUp, (x, y), 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)


def cg_triple_click(x, y):
    """Triple-click to select all text in a field."""
    cg_move(x, y)
    time.sleep(0.05)
    for i in range(3):
        ev_down = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseDown, (x, y), 0)
        ev_up = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseUp, (x, y), 0)
        Quartz.CGEventSetIntegerValueField(
            ev_down, Quartz.kCGMouseEventClickState, i + 1)
        Quartz.CGEventSetIntegerValueField(
            ev_up, Quartz.kCGMouseEventClickState, i + 1)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev_down)
        time.sleep(0.03)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev_up)
        time.sleep(0.03)


def cg_key(keycode, flags=0):
    """Press and release a key."""
    ev = Quartz.CGEventCreateKeyboardEvent(None, keycode, True)
    if flags:
        Quartz.CGEventSetFlags(ev, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
    ev = Quartz.CGEventCreateKeyboardEvent(None, keycode, False)
    if flags:
        Quartz.CGEventSetFlags(ev, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)


# macOS virtual key codes
VK_DELETE = 51
VK_V = 9
VK_A = 0
FLAG_CMD = Quartz.kCGEventFlagMaskCommand


def paste_text(text):
    """Copy to clipboard + Cmd+V."""
    pyperclip.copy(text)
    time.sleep(0.05)
    cg_key(VK_V, FLAG_CMD)
    time.sleep(0.15)


def clear_field(x, y):
    """Triple-click to select all + delete."""
    cg_triple_click(x, y)
    time.sleep(0.1)
    cg_key(VK_DELETE)
    time.sleep(AFTER_CLEAR)


def get_mouse_pos():
    """Get current mouse position (top-left origin for CoreGraphics)."""
    loc = NSEvent.mouseLocation()
    screen_h = Quartz.CGDisplayPixelsHigh(Quartz.CGMainDisplayID())
    return (loc.x, screen_h - loc.y)


def activate_telegram():
    """Bring Telegram to front."""
    subprocess.run(
        ["osascript", "-e", 'tell application "Telegram" to activate'],
        capture_output=True)
    time.sleep(0.5)


def countdown(seconds, msg):
    """Visible countdown."""
    print(msg)
    for i in range(seconds, 0, -1):
        print(f"  {i}...", flush=True)
        time.sleep(1)
    print("  >>> CAPTURED!", flush=True)


# ── Screenshot + Claude verification ────────────────────────────────

def screenshot_region(x, y, w, h, path=SCREENSHOT_PATH):
    """Capture a screen region to a file."""
    subprocess.run(
        ["screencapture", "-R", f"{int(x)},{int(y)},{int(w)},{int(h)}",
         "-x", path],
        capture_output=True)


def ask_claude_username(expected_username):
    """Ask Claude CLI to read the screenshot and return the @username it sees."""
    prompt = (
        f"Read the image file at {SCREENSHOT_PATH}. "
        f"This is a screenshot of Telegram 'Add Members' search results. "
        f"I searched for @{expected_username}. "
        f"Look at the FIRST person result row. What is their exact @username? "
        f"Reply with ONLY the @username (like @example). "
        f"If no results or unclear, reply NONE."
    )
    try:
        result = subprocess.run(
            ["claude", "-p", prompt,
             "--model", "haiku",
             "--allowedTools", "Read",
             "--dangerously-skip-permissions"],
            capture_output=True, text=True, timeout=30)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR:{e}"


def verify_first_result(expected_username, result_x, result_y):
    """
    Screenshot the first result area, ask Claude to read the @username,
    and return (is_match, found_username_string).
    """
    # Capture a region around the first result row
    cap_x = max(0, int(result_x - 220))
    cap_y = max(0, int(result_y - 30))
    cap_w = 460
    cap_h = 70
    screenshot_region(cap_x, cap_y, cap_w, cap_h)

    # Ask Claude
    response = ask_claude_username(expected_username)

    # Extract @username from response
    match = re.search(r"@([\w]+)", response)
    if match:
        found = match.group(1).lower()
        expected = expected_username.lower()
        return found == expected, f"@{match.group(1)}"

    return False, response


# ── Main ─────────────────────────────────────────────────────────────

def main():
    total = len(USERNAMES)

    start_from = 0
    if len(sys.argv) > 1:
        try:
            start_from = int(sys.argv[1])
        except (ValueError, IndexError):
            print(f"Invalid start index: {sys.argv[1]}")
            sys.exit(1)

    print("=" * 55)
    print("  Telegram Add Members Automation v4 (with AI verify)")
    print("=" * 55)
    print(f"  Usernames: {total - start_from} remaining (of {total})")
    if start_from > 0:
        print(f"  Resuming from: [{start_from}] @{USERNAMES[start_from]}")
    print()
    print("  ABORT: Ctrl+C at any time")
    print()

    # ── CALIBRATION ──────────────────────────────────────────────────

    # Step 1: Search field
    print("STEP 1 / 2")
    print("  Open the 'Add Members' dialog in Telegram.")
    print("  Hover your mouse over the SEARCH FIELD.")
    countdown(CALIBRATION_WAIT,
              f"  Capturing in {CALIBRATION_WAIT}s:")
    search_x, search_y = get_mouse_pos()
    print(f"  Search field: ({search_x:.0f}, {search_y:.0f})\n")

    # Paste a test search
    print("  Pasting test search '@petersgu'...")
    activate_telegram()
    cg_click(search_x, search_y)
    time.sleep(0.3)
    clear_field(search_x, search_y)
    paste_text("@petersgu")
    time.sleep(SEARCH_WAIT)

    # Step 2: First result row
    print("\nSTEP 2 / 2")
    print("  Hover your mouse over the FIRST USER result")
    print("  (the person row, NOT 'Invite via Link').")
    countdown(CALIBRATION_WAIT,
              f"  Capturing in {CALIBRATION_WAIT}s:")
    result_x, result_y = get_mouse_pos()
    print(f"  Result row: ({result_x:.0f}, {result_y:.0f})\n")

    # Verify calibration with Claude
    print("  Verifying calibration with Claude...")
    is_match, found = verify_first_result("petersgu", result_x, result_y)
    if is_match:
        print(f"  Calibration OK! Claude sees: {found}")
    else:
        print(f"  Warning: Claude sees '{found}' (expected @petersgu)")
        print(f"  Continuing anyway - positions may need adjustment.")

    # Clear test search
    activate_telegram()
    cg_click(search_x, search_y)
    time.sleep(0.2)
    clear_field(search_x, search_y)

    # Calculate offset
    offset_y = result_y - search_y
    print(f"\n  Y offset: {offset_y:.0f}px")
    print()

    # ── GO ────────────────────────────────────────────────────────────
    print("All set! Switch to Telegram and DON'T TOUCH THE MOUSE.")
    countdown(BEFORE_START, f"  Starting in {BEFORE_START}s:")
    print()

    activate_telegram()
    time.sleep(0.5)

    added = []
    skipped = []
    errors = []
    last_i = start_from

    for i in range(start_from, total):
        last_i = i
        username = USERNAMES[i]
        try:
            print(f"[{i + 1}/{total}] @{username} ", end="", flush=True)

            # 1. Click + clear search field
            cg_click(search_x, search_y)
            time.sleep(0.2)
            clear_field(search_x, search_y)

            # 2. Paste @username
            paste_text(f"@{username}")

            # 3. Wait for results
            time.sleep(SEARCH_WAIT)

            # 4. Screenshot + verify with Claude
            click_y = search_y + offset_y
            is_match, found = verify_first_result(
                username, result_x, click_y)

            if is_match:
                # 5. Click the result
                cg_click(result_x, click_y)
                time.sleep(AFTER_CLICK)
                added.append(username)
                print(f"-> ADDED ({found})", flush=True)
            else:
                skipped.append((i, username, found))
                print(f"-> SKIPPED (saw: {found})", flush=True)

        except KeyboardInterrupt:
            print(f"\n\nSTOPPED at index {i}")
            print(f"Resume: python3 {sys.argv[0]} {i}")
            break
        except Exception as e:
            print(f"-> ERROR: {e}")
            errors.append((i, username, str(e)))

    # ── Summary ──────────────────────────────────────────────────────
    print(f"\n{'=' * 55}")
    print(f"  RESULTS")
    print(f"{'=' * 55}")
    print(f"  Added:   {len(added)}")
    print(f"  Skipped: {len(skipped)} (wrong/no match)")
    print(f"  Errors:  {len(errors)}")

    if skipped:
        print(f"\n  Skipped usernames (add manually):")
        for idx, name, saw in skipped:
            print(f"    [{idx}] @{name}  (Claude saw: {saw})")

    if errors:
        print(f"\n  Errors:")
        for idx, name, err in errors:
            print(f"    [{idx}] @{name}  ({err})")

    print(f"\n  Click 'Add' in Telegram to confirm!")
    print(f"  Resume: python3 {sys.argv[0]} {last_i + 1}")


if __name__ == "__main__":
    main()
