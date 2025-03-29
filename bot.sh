#!/bin/bash

# === FETCH CONFIG FROM ENVIRONMENT VARIABLES ===
URL="${URL}"
BASE_URL="${BASE_URL}"
FIREBASE_URL="${FIREBASE_URL}"
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# === FETCH TOP 3 NOTICES ===
NOTICES=$(curl -s "$URL" |
    awk -v RS="</ul>" '/<ul class="notice">/ {print $0 RS}' |
    grep -oP '<li>.*?<a .*?</a>.*?</li>' | head -n 3)

# Exit if no notices are fetched
if [ -z "$NOTICES" ]; then
    echo "No notices found!"
    exit 1
fi

NEW_NOTICES=()
while read -r line; do
    link=$(echo "$line" | grep -oP '(?<=href=")[^"]*')

    # Ensure absolute URL
    if [[ "$link" != http* ]]; then
        link="$BASE_URL$link"
    fi

    text=$(echo "$line" | sed -E -n 's/.*<a[^>]*>(.*)<\/a>.*/\1/p' | sed -E 's/<[^>]*>//g' | xargs)

    # Generate a unique hash for each notice
    notice_hash=$(echo -n "$link" | md5sum | cut -d ' ' -f1)

    # Check if notice exists in Firebase
    if curl -s "$FIREBASE_URL/sent_notices/$notice_hash.json" | grep -q "sent"; then
        echo "Notice already in database: $link"
    else
        echo "New Notice: $link | $text"
        NEW_NOTICES+=("$notice_hash|$link|$text")
    fi
done <<< "$NOTICES"

# === SEND NEW NOTICES ===
for notice in "${NEW_NOTICES[@]}"; do
    notice_hash=$(echo "$notice" | cut -d '|' -f1)
    link=$(echo "$notice" | cut -d '|' -f2)
    text=$(echo "$notice" | cut -d '|' -f3)

    # Escape special characters for Telegram
    escaped_text=$(echo "$text" | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
    message="<b>📢 New Notice:</b> <a href=\"$link\">$escaped_text</a>"

    # Send to Telegram
    response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
                -d "chat_id=$CHAT_ID" \
                -d "parse_mode=HTML" \
                --data-urlencode "text=$message")

    echo "Telegram Response: $response"

    # Save to Firebase
    SENT_PAYLOAD=$(jq -n '{ "sent": true, "timestamp": now | floor }')
    curl -s -X PUT -d "$SENT_PAYLOAD" "$FIREBASE_URL/sent_notices/$notice_hash.json"

    echo "Sent: $link | $text"
done
