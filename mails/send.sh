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
read -rp "Test email (your inbox for monitoring): " TEST_EMAIL
read -rp "Send test email every N emails (default 1000): " TEST_INTERVAL
TEST_INTERVAL=${TEST_INTERVAL:-1000}

# --- Validate test interval is integer
if ! [[ "$TEST_INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "Error: Test interval must be a positive integer"
  exit 1
fi

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
echo "Will send test email to your inbox every $TEST_INTERVAL emails"

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

# --- Function: send test email to your inbox
send_test_to_inbox() {
  echo "Sending test email to your inbox: $TEST_EMAIL"
  
  local test_msg="$TMPDIR/test_$$.eml"
  {
    printf 'From: %s\n' "$FROM_ADDR"
    printf 'To: %s\n' "$TEST_EMAIL"
    printf 'Subject: [TEST] %s\n' "$SUBJECT"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: text/html; charset="UTF-8"\n'
    printf '\n'
    printf '<html><body>\n'
    printf '<h1>Test Email - Progress Update</h1>\n'
    printf '<p>This is a test email sent to your inbox for monitoring.</p>\n'
    printf '<p><strong>Total emails sent so far:</strong> %d</p>\n' "$count"
    printf '<p><strong>Time:</strong> %s</p>\n' "$(date)"
    printf '<p><strong>Original Subject:</strong> %s</p>\n' "$SUBJECT"
    printf '</body></html>\n'
    printf '\n'
  } > "$test_msg"

  if ! "$SENDMAIL_BIN" -i -f "$FROM_ADDR" -- "$TEST_EMAIL" < "$test_msg"; then
    echo "ERROR: Failed to send test email to your inbox!" >&2
  else
    echo "Test email sent to your inbox successfully"
  fi
}

# --- Process recipients
count=0
while IFS= read -r recipient; do
  [[ -z "$recipient" ]] && continue
  
  # Send the actual email
  send_one "$recipient"
  count=$((count+1))

  # Send test email to your inbox every TEST_INTERVAL emails
  if (( count > 1 )) && (( count % TEST_INTERVAL == 0 )); then
    echo "---"
    echo "Reached $count emails, sending test email to your inbox..."
    send_test_to_inbox
    
    # Also extract delivered list
    echo "Extracting delivered list..."
    sudo grep "status=sent" /var/log/mail.log \
      | grep -oP 'to=<\K[^>]*' \
      | grep -E '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' \
      | sort -u > sent_emails.txt
    echo "Delivered addresses exported to sent_emails.txt"
    echo "---"
  fi
  
done < "$TMPDIR/send_list.txt"

# --- Send final test email when done
echo "---"
echo "Finished sending $count emails, sending final test email to your inbox..."
send_test_to_inbox

# --- Final extraction
echo "Performing final extraction of delivered addresses..."
sudo grep "status=sent" /var/log/mail.log \
  | grep -oP 'to=<\K[^>]*' \
  | grep -E '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' \
  | sort -u > sent_emails.txt
echo "Delivered addresses exported to sent_emails.txt"

echo "Done."