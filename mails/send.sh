#!/usr/bin/env bash
# send.sh
# Send offer.html to all.txt recipients using Postfix sendmail interface
# GCP Cloud Shell variant

set -euo pipefail

# --- Pre-flight checks
if [ ! -f "offer.html" ]; then
  echo "offer.html not found"
  exit 1
fi

if [ ! -f "all.txt" ]; then
  echo "all.txt not found"
  exit 1
fi

SENDMAIL_BIN="/usr/sbin/sendmail"
[ -x "$SENDMAIL_BIN" ] || { echo "sendmail not found at $SENDMAIL_BIN"; exit 1; }

# --- Prompt user (ONLY 3 questions)
read -rp "From address: " FROM_ADDR
read -rp "Subject: " SUBJECT
read -rp "Test email (sent first): " TEST_EMAIL

# --- Build recipient list (test email first, then all.txt unique)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

awk 'NF{gsub(/\r/,""); print}' all.txt | sed 's/^[ \t]*//;s/[ \t]*$//' > "$TMPDIR/raw_list.txt"
{
  echo "$TEST_EMAIL"
  cat "$TMPDIR/raw_list.txt"
} | awk '!seen[$0]++' > "$TMPDIR/send_list.txt"

TOTAL=$(wc -l < "$TMPDIR/send_list.txt")
echo "Total recipients (including test): $TOTAL"

# --- Function: send one email
send_one() {
  local to_addr="$1"
  [[ -z "$to_addr" ]] && return
  if ! [[ "$to_addr" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Skipping invalid: $to_addr"
    return
  fi

  local msg="$TMPDIR/msg_$$.eml"
  {
    printf 'From: %s\n' "$FROM_ADDR"
    printf 'To: %s\n' "$to_addr"
    printf 'Subject: %s\n' "$SUBJECT"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: text/html; charset="UTF-8"\n'
    printf '\n'
    cat offer.html
    printf '\n'
  } > "$msg"

  if ! "$SENDMAIL_BIN" -i -f "$FROM_ADDR" -- "$to_addr" < "$msg"; then
    echo "sendmail failed for $to_addr" >&2
  else
    echo "Sent: $to_addr"
  fi
}

# --- Process recipients
count=0
while IFS= read -r recipient; do
  [[ -z "$recipient" ]] && continue
  send_one "$recipient"
  count=$((count+1))

  if (( count % 100000 == 0 )); then
    echo "Reached $count emails, extracting delivered list..."
    sudo grep "status=sent" /var/log/mail.log \
      | grep -oP 'to=<\K[^>]*' \
      | grep -E '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' \
      | sort -u > sent_emails.txt
    echo "Delivered addresses exported to sent_emails.txt"
  fi
done < "$TMPDIR/send_list.txt"

# --- Final extraction
echo "Finished sending $count emails, final extraction..."
sudo grep "status=sent" /var/log/mail.log \
  | grep -oP 'to=<\K[^>]*' \
  | grep -E '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' \
  | sort -u > sent_emails.txt
echo "Delivered addresses exported to sent_emails.txt"

echo "Done."
