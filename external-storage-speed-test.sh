f=$(mktemp /tmp/ssdtest-script.XXXXXX); cat > "$f" <<'SSDSCRIPT_END'
#!/bin/bash
#
# ssd-speedtest.sh - sequential write/read speed test for external drives and SD cards (macOS)

export LC_ALL=C

# ---- Optional cable info -----------------------------------------------------
# macOS cannot identify a cable, so you are asked for it at run time (Enter to
# skip). To skip the questions, preset it, e.g.:
#   CABLE_NAME="Samsung USB-C 3.2 Gen 2" CABLE_RATING=10 bash ssd-speedtest.sh
CABLE_NAME="${CABLE_NAME:-}"
CABLE_RATING="${CABLE_RATING:-}"
CABLE_GBPS=0
# ------------------------------------------------------------------------------
CHUNK_MIB=64

if [ "$(uname)" != "Darwin" ]; then
  echo "This script is for macOS only."; exit 1
fi

ORIG_PWD="$PWD"
cd / || exit 1          # never keep the shell inside the volume (it blocks unmounting)

WORK_DIR=""; TEST_DIR=""; TESTFILE=""; MP=""; VOL_DEV=""; CLEANED=0

cleanup() {
  [ "$CLEANED" = 1 ] && return
  if [ -n "$VOL_DEV" ] && [ -n "$MP" ] && [ ! -d "$MP" ]; then
    diskutil mount "$VOL_DEV" >/dev/null 2>&1
  fi
  [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
  [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  sync
  CLEANED=1
}
on_interrupt() { echo; echo "Interrupted - cleaning up..."; cleanup; exit 130; }
trap cleanup EXIT
trap on_interrupt INT TERM HUP

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ssdtest.XXXXXX") || { echo "Cannot create temp dir"; exit 1; }

# ---------------------------- helpers ----------------------------------------
now() { perl -MTime::HiRes=time -e 'printf "%.6f\n", time'; }

fmt_bytes() {
  awk -v b="$1" 'BEGIN{ split("B KB MB GB TB",u," "); i=1;
    while (b>=1000 && i<5) { b/=1000; i++ }
    if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i] }'
}

# like fmt_bytes but rounds DOWN, so a displayed limit is never above the real limit
fmt_floor() {
  awk -v b="$1" 'BEGIN{ split("B KB MB GB TB",u," "); i=1;
    while (b>=1000 && i<5) { b/=1000; i++ }
    printf "%.1f %s", int(b*10)/10, u[i] }'
}

# field "<diskutil text>" "<Key>"  -> value
field() { printf '%s\n' "$1" | sed -n "s|^ *$2: *||p" | head -n 1; }

fail() { echo; echo "ERROR: $*"; exit 1; }

# Report filename prefix from the drive model: last word containing a digit
# (e.g. "PSSD T7 Media" -> t7), else the whole cleaned model name, else "ssd".
# Override with REPORT_PREFIX=name if you prefer.
make_prefix() {
  local clean tok last="" slug
  clean=$(printf '%s' "$1" | sed -e 's/ Media$//' -e 's/ Device$//' | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' ' ')
  for tok in $clean; do
    case "$tok" in *[0-9]*) last="$tok";; esac
  done
  if [ -n "$last" ]; then printf '%s' "$last"; return; fi
  slug=$(printf '%s' "$clean" | tr -s ' ' '-' | sed -e 's/^-//' -e 's/-$//')
  printf '%s' "${slug:-ssd}"
}

# ---------------------------- drive detection --------------------------------
describe_volume() {
  MP="$1"
  VINFO=$(diskutil info "$MP" 2>/dev/null)
  VOL_NAME=$(field "$VINFO" "Volume Name")
  VOL_DEV=$(field "$VINFO" "Device Node")
  FS=$(field "$VINFO" "File System Personality")
  [ -z "$FS" ] && FS=$(field "$VINFO" "Type (Bundle)")

  WHOLE=$(field "$VINFO" "APFS Physical Store")
  if [ -n "$WHOLE" ]; then
    WHOLE=$(printf '%s' "$WHOLE" | sed 's/s[0-9]*$//')
  else
    WHOLE=$(field "$VINFO" "Part of Whole")
    ps=$(field "$(diskutil info "/dev/$WHOLE" 2>/dev/null)" "APFS Physical Store")
    [ -n "$ps" ] && WHOLE=$(printf '%s' "$ps" | sed 's/s[0-9]*$//')
  fi

  WINFO=$(diskutil info "/dev/$WHOLE" 2>/dev/null)
  MODEL=$(field "$WINFO" "Device / Media Name")
  CAP=$(field "$WINFO" "Disk Size")
  [ -z "$CAP" ] && CAP=$(field "$WINFO" "Total Size")
  CAP=$(printf '%s' "$CAP" | sed 's/ (exactly.*//')
  PROTO=$(field "$WINFO" "Protocol")

  # Partition map: detected from the disk, then translated to a readable name
  SCHEME_RAW=$(diskutil list "/dev/$WHOLE" 2>/dev/null | awk '$1=="0:"{print $2; exit}')
  [ -z "$SCHEME_RAW" ] && SCHEME_RAW=$(field "$WINFO" "Content (IOContent)")
  case "$SCHEME_RAW" in
    FDisk_partition_scheme) SCHEME="Master Boot Record (MBR)";;
    GUID_partition_scheme)  SCHEME="GUID Partition Map (GPT)";;
    Apple_partition_scheme) SCHEME="Apple Partition Map (APM)";;
    "")                     SCHEME="Not reported";;
    *)                      SCHEME="$SCHEME_RAW";;
  esac

  # Drive type: from the protocol / flags macOS reports for the disk
  REMOV=$(field "$WINFO" "Removable Media")
  case "$PROTO" in
    "Secure Digital") DRIVE_TYPE="SD/microSD card (built-in card slot)";;
    *) case "$(field "$WINFO" "Solid State")" in
         Yes*) DRIVE_TYPE="External SSD";;
         No*)  DRIVE_TYPE="External HDD";;
         *)    case "$MODEL" in
                 *SSD*|*ssd*) DRIVE_TYPE="External SSD";;
                 *) case "$REMOV" in
                      Removable*) DRIVE_TYPE="Removable media (USB card reader / flash drive)";;
                      *)          DRIVE_TYPE="External drive (SSD/HDD not reported)";;
                    esac;;
               esac;;
       esac;;
  esac

  # NAND technology: macOS does not report it. Small built-in lookup by model name.
  case "$MODEL" in
    *PSSD*T7*|*"Portable SSD T7"*) TECH="Samsung V-NAND TLC (3-bit MLC) - from Samsung specs, not reported by macOS";;
    *)                             TECH="Not reported by macOS";;
  esac

  FREE_KB=$(df -k "$MP" | tail -n 1 | awk '{print $4}')
  FREE_B=$((FREE_KB * 1024))
  [ -z "$VOL_NAME" ] && VOL_NAME=$(basename "$MP")
}

VOL_MP=()
for v in /Volumes/*; do
  [ -d "$v" ] || continue
  [ -L "$v" ] && continue
  info=$(diskutil info "$v" 2>/dev/null)
  [ -z "$info" ] && continue
  proto=$(field "$info" "Protocol")
  case "$proto" in *"Disk Image"*) continue;; esac
  loc=$(field "$info" "Device Location")
  internal=$(field "$info" "Internal")
  # External drives, plus SD cards in the Mac's built-in slot (macOS calls those "Internal")
  if [ "$loc" = "External" ] || [ "$internal" = "No" ] || [ "$proto" = "Secure Digital" ]; then
    case "$(field "$info" "Volume Read-Only")" in Yes*) continue;; esac
    [ -w "$v" ] || continue
    VOL_MP[${#VOL_MP[@]}]="$v"
  fi
done

COUNT=${#VOL_MP[@]}
echo "============================================================"
echo " STORAGE SPEED TEST (external drives and SD cards)"
echo "============================================================"
echo

if [ "$COUNT" -eq 0 ]; then
  echo "No writable external or removable volumes found. Connect the drive or insert the card and try again."
  exit 1
fi

if [ "$COUNT" -eq 1 ]; then
  SEL=0
  describe_volume "${VOL_MP[0]}"
  echo "Found 1 volume: $VOL_NAME  [$DRIVE_TYPE, $MODEL, $CAP, $FS, $SCHEME]  ->  $MP"
else
  echo "Found $COUNT volumes:"
  echo
  i=0
  while [ "$i" -lt "$COUNT" ]; do
    describe_volume "${VOL_MP[$i]}"
    printf '  [%d] %s  -  %s, %s, %s, %s, %s  (%s)\n' "$((i+1))" "$VOL_NAME" "$DRIVE_TYPE" "$MODEL" "$CAP" "$FS" "$SCHEME" "$MP"
    i=$((i+1))
  done
  echo
  while true; do
    read -r -p "Choose a volume [1-$COUNT]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$COUNT" ]; then
      SEL=$((choice-1)); break
    fi
    echo "Invalid choice."
  done
  describe_volume "${VOL_MP[$SEL]}"
fi
echo

case "$PROTO" in USB) IS_USB=1;; *) IS_USB=0;; esac

# ---------------------------- free space + safe limit ------------------------
# Safe margin = 2% of free space; for small volumes at least 1 GB or 10% of the free space,
# whichever is smaller. Max test size = free space - margin.
MARGIN_B=$(awk -v f="$FREE_B" 'BEGIN{m=f*0.02; fl=(f*0.10<1000000000)?f*0.10:1000000000; if (m<fl) m=fl; printf "%.0f", m}')
MAX_BYTES=$((FREE_B - MARGIN_B))

# FAT volumes cannot hold a single file larger than 4 GB (FAT32) / 2 GB (FAT16)
FILE_CAP=0; FS_NOTE=""
case "$FS" in
  *FAT32*)                    FILE_CAP=4000000000;;
  *FAT16*|*FAT12*|*"MS-DOS"*) FILE_CAP=2000000000;;
esac
if [ "$FILE_CAP" -gt 0 ] && [ "$MAX_BYTES" -gt "$FILE_CAP" ]; then
  MAX_BYTES=$FILE_CAP
  FS_NOTE=" (limited by the single-file size limit of $FS)"
fi

if [ "$MAX_BYTES" -lt 1000000 ]; then
  fail "Not enough free space on $VOL_NAME for a test ($(fmt_bytes "$FREE_B") free, $(fmt_bytes "$MARGIN_B") safety margin)."
fi
MAX_LABEL=$(fmt_floor "$MAX_BYTES")
echo "Free space:         $(fmt_bytes "$FREE_B")"
echo "Safety margin kept: $(fmt_bytes "$MARGIN_B")"
echo "Maximum test size:  $MAX_LABEL$FS_NOTE"
case "$DRIVE_TYPE" in
  SD*|Removable*) echo "Note: memory cards have limited write endurance; 1-4 GB is enough for a speed reading." ;;
esac
echo

# ---------------------------- test size --------------------------------------
parse_size() {
  local s num unit bin e base re
  s=$(printf '%s' "$1" | tr -d ' ' | tr 'A-Z' 'a-z')
  re='^([0-9]+(\.[0-9]+)?)(k|m|g|t)?(i?b)?$'
  [[ "$s" =~ $re ]] || return 1
  num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[3]}"; bin="${BASH_REMATCH[4]}"
  [ -z "$unit" ] && [ -n "$bin" ] && return 1
  [ -z "$unit" ] && unit="m"
  case "$unit" in k) e=1;; m) e=2;; g) e=3;; t) e=4;; esac
  case "$bin" in i*) base=1024;; *) base=1000;; esac
  SIZE_BYTES=$(awk -v n="$num" -v b="$base" -v e="$e" 'BEGIN{printf "%.0f", n*(b^e)}')
  [ "$SIZE_BYTES" -ge 1000000 ] || return 1
  local U; U=$(printf '%s' "$unit" | tr 'a-z' 'A-Z')
  case "$bin" in i*) SIZE_LABEL="${num}${U}iB"; SIZE_FILE="${num}${unit}i";;
                  *) SIZE_LABEL="${num}${U}B";  SIZE_FILE="${num}${unit}";; esac
  return 0
}

while true; do
  read -r -p "Test size (e.g. 100MB, 5GB, 100GB; max $MAX_LABEL): " size_in
  if parse_size "$size_in"; then
    [ "$SIZE_BYTES" -le "$MAX_BYTES" ] && break
    echo "Too large. Maximum is $MAX_LABEL (free space minus the safety margin)."
  else
    echo "Could not understand that. Use a number plus MB/GB/TB (minimum 1MB)."
  fi
done
MIB=$(( (SIZE_BYTES + 1048575) / 1048576 ))
ACTUAL_BYTES=$((MIB * 1048576))
REPORT_PREFIX="${REPORT_PREFIX:-$(make_prefix "$MODEL")}"
REPORT="$ORIG_PWD/${REPORT_PREFIX}-${SIZE_FILE}-speed-test-report.txt"

# ---------------------------- cable (optional, user-entered) -----------------
if [ "$IS_USB" = 1 ]; then
if [ -z "$CABLE_NAME$CABLE_RATING" ]; then
  read -r -p "Cable used (optional, e.g. Samsung USB-C 3.2 Gen 2; Enter to skip): " CABLE_NAME
  if [ -n "$CABLE_NAME" ]; then
    read -r -p "Cable rating in Gbps (optional, e.g. 10; Enter to skip): " CABLE_RATING
  fi
  echo
fi
CABLE_GBPS=$(printf '%s' "$CABLE_RATING" | sed -n 's/^[^0-9]*\([0-9][0-9]*\.\{0,1\}[0-9]*\).*/\1/p')
[ -n "$CABLE_GBPS" ] || CABLE_GBPS=0
case "$(printf '%s' "$CABLE_RATING" | tr 'A-Z' 'a-z')" in
  *mb*) CABLE_GBPS=$(awk -v g="$CABLE_GBPS" 'BEGIN{printf "%g", g/1000}');;
esac
if [ -n "$CABLE_NAME" ]; then CABLE_TXT="$CABLE_NAME (entered by user)"; else CABLE_TXT="Not specified"; fi
if awk -v g="$CABLE_GBPS" 'BEGIN{exit !(g>0)}'; then
  RATING_TXT="$CABLE_GBPS Gbps (entered by user)"
else
  RATING_TXT="Not specified"
fi
else
  CABLE_NAME=""; CABLE_GBPS=0
  CABLE_TXT="Not applicable (not a USB device)"; RATING_TXT="Not applicable"
fi

# ---------------------------- host + link info -------------------------------
HW=$(system_profiler SPHardwareDataType 2>/dev/null)
HW_NAME=$(field "$HW" "Model Name"); HW_ID=$(field "$HW" "Model Identifier")
COMPUTER="${HW_NAME:-Mac} (${HW_ID:-unknown})"
CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null) ($(sysctl -n hw.ncpu) cores)"
MEM="$(awk -v b="$(sysctl -n hw.memsize)" 'BEGIN{printf "%d GB", b/1073741824}')"
MACOS="$(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"

map_speed() {
  local lc; lc=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$lc" in
    "")                              LINK="Not detected"; LINK_GBPS=0;;
    *"40 gb"*)                       LINK="40 Gbps";  LINK_GBPS=40;;
    *"20 gb"*)                       LINK="USB 3.2 Gen 2x2 (20 Gbps)"; LINK_GBPS=20;;
    *super_speed_plus*|*"10 gb"*)    LINK="USB 3.2 Gen 2 (10 Gbps)"; LINK_GBPS=10;;
    *super_speed*|*"5 gb"*)          LINK="USB 3.2 Gen 1 (5 Gbps)";  LINK_GBPS=5;;
    *high_speed*|*"480 mb"*)         LINK="USB 2.0 High Speed (480 Mbps)"; LINK_GBPS=0.48;;
    *)                               LINK="$1"; LINK_GBPS=0;;
  esac
}

gather_link() {
  BUS="${PROTO:-Unknown}"; LOCID="Not detected"; LINK="Not detected"; LINK_GBPS=0
  if [ "$IS_USB" != 1 ]; then
    case "$PROTO" in "Secure Digital") BUS="Secure Digital (built-in card slot)";; esac
    LOCID="Not applicable"; LINK="Not applicable (not a USB device)"
    return
  fi
  local f="$WORK_DIR/usb.json" js="$WORK_DIR/usb.js" out loc speed
  system_profiler SPUSBDataType -json > "$f" 2>/dev/null
  cat > "$js" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  try {
    var raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, $()));
    var disk = argv[1], data = JSON.parse(raw), found = null;
    function owns(node) {
      var media = node.Media || [];
      for (var i = 0; i < media.length; i++) {
        if (media[i].bsd_name === disk) return true;
        var vols = media[i].volumes || [];
        for (var j = 0; j < vols.length; j++)
          if (vols[j].bsd_name && vols[j].bsd_name.indexOf(disk + 's') === 0) return true;
      }
      return false;
    }
    function walk(list) {
      for (var i = 0; i < list.length; i++) {
        if (owns(list[i])) { found = list[i]; return true; }
        if (list[i]._items && walk(list[i]._items)) return true;
      }
      return false;
    }
    walk(data.SPUSBDataType || []);
    if (!found) return '';
    var speed = '';
    for (var k in found) { if (/speed/i.test(k) && typeof found[k] === 'string') { speed = found[k]; break; } }
    return 'loc=' + (found.location_id || '') + '\nspeed=' + speed;
  } catch (e) { return ''; }
}
JXA
  out=$(osascript -l JavaScript "$js" "$f" "$WHOLE" 2>/dev/null)
  loc=$(printf '%s\n' "$out" | sed -n 's/^loc=//p')
  speed=$(printf '%s\n' "$out" | sed -n 's/^speed=//p')
  [ -n "$loc" ] && LOCID="$loc"
  map_speed "$speed"
}
gather_link

# Mac-side port: map the top byte of the USB Location ID to the host bus number,
# then read that bus's port speed from the Thunderbolt/USB4 data.
find_port() {
  local hexid byte n tb name gb
  hexid=$(printf '%s' "$LOCID" | sed -n 's/^0x\([0-9a-fA-F]*\).*/\1/p')
  [ -n "$hexid" ] || return
  byte=$(printf '%s' "$hexid" | cut -c1-2)
  n=$((16#$byte))
  tb=$(system_profiler SPThunderboltDataType 2>/dev/null)
  name=$(printf '%s\n' "$tb" | sed -n "s/^ *\(.*Bus $n\): *$/\1/p" | head -n 1)
  if [ -n "$name" ]; then
    gb=$(printf '%s\n' "$tb" | awk -v n="$n" '
      /Bus [0-9]+: *$/ { inb = ($0 ~ ("Bus " n ": *$")); next }
      inb && /Speed:/ { print; exit }' | sed -n 's/.*[^0-9]\([0-9][0-9]*\) *Gb\/s.*/\1/p')
    if [ -n "$gb" ]; then
      BUS="$name ($gb Gbps)"
    else
      BUS="$name (USB device)"
    fi
  else
    BUS="USB, host bus $n (from Location ID)"
  fi
}
find_port

# ---------------------------- confirmation -----------------------------------
build_confirmation() {
cat <<EOF
============================================================
 TEST CONFIRMATION
============================================================

Drive
  Model: $MODEL
  Type: $DRIVE_TYPE
  Technology: $TECH
  Capacity: $CAP
  Volume: $VOL_NAME ($MP)
  Filesystem: $FS
  Partition map: $SCHEME
  Free space: $(fmt_bytes "$FREE_B")

Host
  Computer: $COMPUTER
  CPU: $CPU
  Memory: $MEM
  macOS: $MACOS

Cable
  Cable: $CABLE_TXT
  Rating: $RATING_TXT

Connection
  Bus: $BUS
  Location ID: $LOCID
  Negotiated link: $LINK

TEST
  Test volume: $SIZE_LABEL ($(fmt_bytes "$ACTUAL_BYTES") written)

EOF
}

echo
CONFIRM_TEXT=$(build_confirmation)
printf '%s\n' "$CONFIRM_TEXT"
echo "WARNING:"
echo "  The test will write $SIZE_LABEL to the $VOL_NAME."
echo "  Make sure the $VOL_NAME has enough free space."
echo

if [ "$FREE_B" -lt $((ACTUAL_BYTES + 67108864)) ]; then
  fail "Not enough free space on $VOL_NAME ($(fmt_bytes "$FREE_B") free, $(fmt_bytes "$ACTUAL_BYTES") needed)."
fi

read -r -p "Press Enter to start the test (Ctrl-C to cancel): " _
TEST_START=$(date '+%Y-%m-%d %H:%M:%S %Z')
echo

# ---------------------------- test -------------------------------------------
progress() { printf '\r  %-8s %3d%%  (%d / %d MiB)   ' "$1" "$(( $2 * 100 / MIB ))" "$2" "$MIB"; }

TEST_DIR=$(mktemp -d "$MP/.ssd-speedtest.XXXXXX") || fail "Cannot write to $MP"
TEST_REL=$(basename "$TEST_DIR")
TESTFILE="$TEST_DIR/testfile.bin"

CM=$CHUNK_MIB; [ "$MIB" -lt "$CM" ] && CM=$MIB
CHUNK="$WORK_DIR/chunk.bin"
echo "Preparing random test data..."
dd if=/dev/urandom of="$CHUNK" bs=1048576 count="$CM" 2>/dev/null || fail "Cannot create test data"

# ---- WRITE ----
LOOPS=$((MIB / CM)); REM=$((MIB % CM))
: > "$TESTFILE"
T0=$(now)
i=0
while [ "$i" -lt "$LOOPS" ]; do
  cat "$CHUNK" >> "$TESTFILE" || fail "Write failed (drive full or disconnected?)"
  i=$((i+1)); progress "Writing" $((i * CM))
done
if [ "$REM" -gt 0 ]; then
  dd if="$CHUNK" bs=1048576 count="$REM" 2>/dev/null >> "$TESTFILE" || fail "Write failed"
  progress "Writing" "$MIB"
fi
printf '\r  %-8s 100%%  flushing to disk...        ' "Writing"
sync
T1=$(now)
echo
W_SEC=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')
W_MB=$(awk -v n="$ACTUAL_BYTES" -v s="$W_SEC" 'BEGIN{printf "%.1f", n/1e6/s}')
W_MIB=$(awk -v n="$ACTUAL_BYTES" -v s="$W_SEC" 'BEGIN{printf "%.1f", n/1048576/s}')

[ "$(stat -f %z "$TESTFILE")" = "$ACTUAL_BYTES" ] || fail "Test file has the wrong size after writing."

# ---- flush the read cache ----
flush_cache() {
  local n=0 newmp
  while [ "$n" -lt 3 ]; do
    if diskutil unmount "$MP" >/dev/null 2>&1; then
      diskutil mount "$VOL_DEV" >/dev/null 2>&1 || diskutil mount "$VOL_DEV" >/dev/null 2>&1 \
        || fail "Volume was unmounted but could not be remounted. Unplug and replug the drive; the hidden folder $TEST_REL can then be deleted."
      newmp=$(field "$(diskutil info "$VOL_DEV" 2>/dev/null)" "Mount Point")
      [ -n "$newmp" ] && MP="$newmp"
      TEST_DIR="$MP/$TEST_REL"; TESTFILE="$TEST_DIR/testfile.bin"
      [ -f "$TESTFILE" ] || fail "Test file disappeared after remount."
      CACHE_METHOD="volume unmount/remount (RAM cache cleared)"
      return
    fi
    n=$((n+1)); sleep 2
  done
  if purge >/dev/null 2>&1 || sudo -n purge >/dev/null 2>&1; then
    CACHE_METHOD="purge (RAM cache cleared)"
  else
    CACHE_METHOD="none - read result may be inflated by RAM cache (use a larger test size)"
  fi
}
echo "  Clearing disk cache before the read test..."
flush_cache

# ---- READ ----
OFF=0
T0=$(now)
while [ "$OFF" -lt "$MIB" ]; do
  N=$CHUNK_MIB; [ $((MIB - OFF)) -lt "$N" ] && N=$((MIB - OFF))
  dd if="$TESTFILE" of=/dev/null bs=1048576 skip="$OFF" count="$N" 2>/dev/null || fail "Read failed"
  OFF=$((OFF + N)); progress "Reading" "$OFF"
done
T1=$(now)
echo
R_SEC=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')
R_MB=$(awk -v n="$ACTUAL_BYTES" -v s="$R_SEC" 'BEGIN{printf "%.1f", n/1e6/s}')
R_MIB=$(awk -v n="$ACTUAL_BYTES" -v s="$R_SEC" 'BEGIN{printf "%.1f", n/1048576/s}')

# ---------------------------- cleanup ----------------------------------------
echo "  Cleaning up..."
rm -rf "$TEST_DIR" "$WORK_DIR"
sync
if [ ! -e "$TEST_DIR" ] && [ ! -e "$WORK_DIR" ]; then
  CLEAN_MSG="OK - test file removed from the drive, temp files removed from the Mac"
else
  CLEAN_MSG="WARNING - some test files may remain: $TEST_DIR"
fi
CLEANED=1

# ---------------------------- results ----------------------------------------
LINK_NOTE=""
if awk -v a="$LINK_GBPS" -v b="$CABLE_GBPS" 'BEGIN{exit !(a>0 && a<b)}'; then
  LINK_NOTE="NOTE: negotiated link ($LINK) is slower than the cable rating you entered ($CABLE_GBPS Gbps). Check the port, cable and adapters."
fi

build_results() {
cat <<EOF
============================================================
 RESULTS
============================================================

Date:  $TEST_START
Drive: $MODEL - $VOL_NAME ($FS, $SCHEME)
Link:  $LINK
Test:  $SIZE_LABEL sequential, ${CM} MiB blocks, random data

Write
  Speed: $W_MB MB/s  ($W_MIB MiB/s)
  Time:  $W_SEC s (includes final flush to disk)

Read
  Speed: $R_MB MB/s  ($R_MIB MiB/s)
  Time:  $R_SEC s
  Cache handling: $CACHE_METHOD

Cleanup: $CLEAN_MSG
${LINK_NOTE:+
$LINK_NOTE
}
Notes:
  * MB/s = 1,000,000 bytes/s (vendor units); MiB/s = 1,048,576 bytes/s
  * Write time includes the final flush to disk
  * Short tests may be inflated by the drive's SLC cache; use a larger size for sustained speed
  * Cable details are entered by the user (or skipped); macOS cannot detect them
  * Port/bus is inferred from the USB Location ID; the Gbps shown on the Bus line is the Mac port's speed as reported by macOS, not the drive's link
  * Drive type comes from macOS; NAND technology comes from a built-in model lookup, not from the drive
  * Sequential transfer test only; not an endurance, TBW or temperature test; memory-card speed/application class ratings (U3, V30, A1/A2) are not verified
EOF
}

RESULTS_TEXT=$(build_results)
echo
printf '%s\n' "$RESULTS_TEXT"

{
  echo "STORAGE SPEED TEST REPORT"
  echo
  printf '%s\n\n' "$CONFIRM_TEXT"
  printf '%s\n' "$RESULTS_TEXT"
} > "$REPORT"

echo
echo "Report saved: $REPORT"
SSDSCRIPT_END
cd ~/Desktop && bash "$f"; rm -f "$f"