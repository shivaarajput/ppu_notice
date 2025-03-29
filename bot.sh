#!/bin/bash

# === FETCH CONFIG FROM ENVIRONMENT VARIABLES ===
URL="${URL}"
BASE_URL="${BASE_URL}"
FIREBASE_URL="${FIREBASE_URL}"
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# === FETCH TOP 3 NOTICES ===
TMP_FILE=$(mktemp)
curl -s "$URL" |
awk -v RS="</ul>" '/<ul class="notice">/ {print $0 RS}' |
grep -oP '<li>.*?<a .*?</a>.*?</li>' | head -n 3 | while read -r line; do
    # Extract URL
    link=$(echo "$line" | grep -oP '(?<=href=")[^"]*')

    # Ensure absolute URL
    if [[ "$link" != http* ]]; then
        link="$BASE_URL$link"
    fi

    # Extract text inside <a> tag, removing HTML tags
    text=$(echo "$line" | sed -E -n 's/.*<a[^>]*>(.*)<\/a>.*/\1/p' | sed -E 's/<[^>]*>//g' | xargs)

    # Save the extracted notice
    echo "$link | $text" >> "$TMP_FILE"
done

# === FETCH EXISTING NOTICES FROM FIREBASE ===
EXISTING_NOTICES=$(curl -s "$FIREBASE_URL/notices.json" | jq -r '.[].link' 2>/dev/null)
SENT_NOTICES=$(curl -s "$FIREBASE_URL/sent_notices.json" | jq -r 'keys[]' 2>/dev/null)

# === PROCESS NOTICES ===
while IFS='|' read -r link text; do
    # Check if the notice already exists in Firebase
    if echo "$EXISTING_NOTICES" | grep -q "$link"; then
        echo "Notice already in database: $link"
    else
        # Save the notice in Firebase
        JSON_PAYLOAD=$(jq -n --arg link "$link" --arg text "$text" '{ "link": $link, "text": $text, "timestamp": now | floor }')
        curl -s -X POST -d "$JSON_PAYLOAD" "$FIREBASE_URL/notices.json"
    fi

    # Check if the notice was already sent to Telegram
    if echo "$SENT_NOTICES" | grep -q "$link"; then
        echo "Notice already sent: $text"
    else
        # Send the notice to Telegram
        escaped_text=$(echo "$text" | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
        message="<b>📢 New Notice:</b> <a href=\"$link\">$escaped_text</a>"
        response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
                    -d "chat_id=$CHAT_ID" \
                    -d "parse_mode=HTML" \
                    --data-urlencode "text=$message")

        echo "Telegram Response: $response"

        # Mark the notice as sent in Firebase
        SENT_PAYLOAD=$(jq -n '{ "sent": true, "timestamp": now | floor }')
        curl -s -X PUT -d "$SENT_PAYLOAD" "$FIREBASE_URL/sent_notices/$(echo -n $link | md5sum | cut -d ' ' -f1).json"

        echo "Sent: $link | $text"
    fi
done < "$TMP_FILE"

rm "$TMP_FILE"  # Cleanup temp file
