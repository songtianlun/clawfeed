#!/bin/bash
# AI Digest E2E Multi-User Cross Test
# 3 users: Elon(id=1), Kevin(id=2), Coco(id=3)
set -e

API="https://digest.kevinhe.io/api"
ELON="Cookie: session=sess-elon"
KEVIN="Cookie: session=sess-kevin"
COCO="Cookie: session=sess-coco"
PASS=0
FAIL=0
TOTAL=0

check() {
  TOTAL=$((TOTAL+1))
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    PASS=$((PASS+1))
    echo "  ✅ $desc"
  else
    FAIL=$((FAIL+1))
    echo "  ❌ $desc"
    echo "     expected: $expected"
    echo "     got: $actual"
  fi
}

echo ""
echo "========================================="
echo "  AI Digest E2E Test Suite"
echo "========================================="

# ─── 1. AUTH ───
echo ""
echo "─── 1. Auth ───"

r=$(curl -s "$API/auth/me" -H "$ELON")
check "Elon auth" '"name":"Elon He"' "$r"

r=$(curl -s "$API/auth/me" -H "$KEVIN")
check "Kevin auth" '"name":"Kevin He"' "$r"

r=$(curl -s "$API/auth/me" -H "$COCO")
check "Coco auth" '"name":"kevin he"' "$r"

r=$(curl -s "$API/auth/me")
check "No cookie → not authenticated" 'not authenticated' "$r"

# ─── 2. DIGEST BROWSING ───
echo ""
echo "─── 2. Digest Browsing ───"

r=$(curl -s "$API/digests?type=4h&limit=3")
check "Public digest list (no auth)" '"type":"4h"' "$r"

r=$(curl -s "$API/digests?type=daily&limit=1")
check "Daily digest list" 'daily' "$r"

# ─── 3. SOURCES - Visitor ───
echo ""
echo "─── 3. Sources (Visitor) ───"

r=$(curl -s "$API/sources")
check "Visitor sees public sources" '@karpathy' "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/sources" -H "Content-Type: application/json" -d '{"name":"test","type":"rss","config":"{}"}')
check "Visitor cannot create source → 401" "401" "$r"

# ─── 4. SOURCES - Elon creates sources ───
echo ""
echo "─── 4. Sources (Elon creates) ───"

r=$(curl -s -X POST "$API/sources" -H "$ELON" -H "Content-Type: application/json" \
  -d '{"name":"Simon Willison","type":"rss","config":"{\"url\":\"https://simonwillison.net/atom/everything/\"}","isPublic":true}')
ELON_SRC1=$(echo "$r" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
check "Elon creates Simon Willison RSS (public)" '"id":' "$r"

r=$(curl -s -X POST "$API/sources" -H "$ELON" -H "Content-Type: application/json" \
  -d '{"name":"r/MachineLearning","type":"reddit","config":"{\"subreddit\":\"MachineLearning\"}","isPublic":false}')
ELON_SRC2=$(echo "$r" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
check "Elon creates r/ML (private)" '"id":' "$r"

# Elon auto-subscribed to own sources
r=$(curl -s "$API/subscriptions" -H "$ELON")
check "Elon auto-subscribed to Simon Willison" 'Simon Willison' "$r"
check "Elon auto-subscribed to r/ML" 'r/MachineLearning' "$r"

# ─── 5. DATA ISOLATION ───
echo ""
echo "─── 5. Data Isolation ───"

# Coco should NOT see Elon's private source in public list
r=$(curl -s "$API/sources")
check "Public list includes Elon's public source" 'Simon Willison' "$r"
# Private sources should not appear in public list
if echo "$r" | grep -q '"is_public":0'; then
  FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
  echo "  ❌ Private sources leaked to public list"
else
  PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
  echo "  ✅ Private sources hidden from public list"
fi

# Coco has no subscriptions yet
r=$(curl -s "$API/subscriptions" -H "$COCO")
SUB_COUNT=$(echo "$r" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
check "Coco has 0 subscriptions initially" "0" "$SUB_COUNT"

# Kevin's subscriptions are Kevin's only
r=$(curl -s "$API/subscriptions" -H "$KEVIN")
check "Kevin has his 3 subscriptions" '@karpathy' "$r"

# ─── 6. PACKS - Elon creates a pack ───
echo ""
echo "─── 6. Packs (Elon creates + shares) ───"

r=$(curl -s -X POST "$API/packs" -H "$ELON" -H "Content-Type: application/json" \
  -d "{\"name\":\"Elon ML Pack\",\"description\":\"ML sources\",\"sourcesJson\":\"[{\\\"name\\\":\\\"Simon Willison\\\",\\\"type\\\":\\\"rss\\\",\\\"config\\\":\\\"{\\\\\\\"url\\\\\\\":\\\\\\\"https://simonwillison.net/atom/everything/\\\\\\\"}\\\"},{\\\"name\\\":\\\"r/MachineLearning\\\",\\\"type\\\":\\\"reddit\\\",\\\"config\\\":\\\"{\\\\\\\"subreddit\\\\\\\":\\\\\\\"MachineLearning\\\\\\\"}\\\"}]\"}")
ELON_PACK_SLUG=$(echo "$r" | python3 -c "import sys,json; print(json.load(sys.stdin).get('slug',''))" 2>/dev/null)
check "Elon creates pack" '"slug":' "$r"
echo "     Pack slug: $ELON_PACK_SLUG"

# Pack visible to everyone
r=$(curl -s "$API/packs")
check "Public packs list includes Elon's pack" 'Elon ML Pack' "$r"

# Pack detail page
r=$(curl -s "$API/packs/$ELON_PACK_SLUG")
check "Pack detail accessible" 'Elon ML Pack' "$r"

# ─── 7. PACKS - Coco installs Elon's pack ───
echo ""
echo "─── 7. Pack Install (Coco installs Elon's) ───"

r=$(curl -s -X POST "$API/packs/$ELON_PACK_SLUG/install" -H "$COCO")
check "Coco installs Elon's pack" '"ok":true' "$r"
check "Coco gets 2 new sources" '"added":2' "$r"

# Coco now has subscriptions
r=$(curl -s "$API/subscriptions" -H "$COCO")
check "Coco subscribed to Simon Willison" 'Simon Willison' "$r"
check "Coco subscribed to r/ML" 'MachineLearning' "$r"

# ─── 8. PACK DEDUP - Coco installs again ───
echo ""
echo "─── 8. Dedup (Coco re-installs) ───"

r=$(curl -s -X POST "$API/packs/$ELON_PACK_SLUG/install" -H "$COCO")
check "Re-install → 0 added, 2 skipped" '"added":0' "$r"

# ─── 9. PACK INSTALL - Kevin installs (has overlap) ───
echo ""
echo "─── 9. Cross-install (Kevin installs Elon's pack) ───"

r=$(curl -s "$API/subscriptions" -H "$KEVIN")
KEVIN_SUB_BEFORE=$(echo "$r" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)

r=$(curl -s -X POST "$API/packs/$ELON_PACK_SLUG/install" -H "$KEVIN")
check "Kevin installs Elon's pack" '"ok":true' "$r"

r=$(curl -s "$API/subscriptions" -H "$KEVIN")
KEVIN_SUB_AFTER=$(echo "$r" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
check "Kevin gained subscriptions" 'Simon Willison' "$r"
echo "     Kevin subs: $KEVIN_SUB_BEFORE → $KEVIN_SUB_AFTER"

# ─── 10. MARKS - Cross-user isolation ───
echo ""
echo "─── 10. Marks Isolation ───"

# Get a digest ID
DIGEST_ID=$(curl -s "$API/digests?type=4h&limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null)
echo "     Using digest_id: $DIGEST_ID"

if [ -n "$DIGEST_ID" ]; then
  # Elon marks it
  r=$(curl -s -X POST "$API/marks" -H "$ELON" -H "Content-Type: application/json" \
    -d "{\"digestId\":$DIGEST_ID,\"url\":\"https://test.com/elon\",\"title\":\"test mark\",\"note\":\"elon note\"}")
  check "Elon creates mark" '"id":' "$r"
  ELON_MARK_ID=$(echo "$r" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

  # Kevin marks same digest
  r=$(curl -s -X POST "$API/marks" -H "$KEVIN" -H "Content-Type: application/json" \
    -d "{\"digestId\":$DIGEST_ID,\"url\":\"https://test.com/kevin\",\"title\":\"test mark\",\"note\":\"kevin note\"}")
  check "Kevin marks same digest" '"id":' "$r"

  # Elon sees only his marks
  r=$(curl -s "$API/marks" -H "$ELON")
  check "Elon sees his mark" 'elon note' "$r"
  if echo "$r" | grep -q 'kevin note'; then
    FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1))
    echo "  ❌ Elon can see Kevin's mark (data leak!)"
  else
    PASS=$((PASS+1)); TOTAL=$((TOTAL+1))
    echo "  ✅ Elon cannot see Kevin's mark"
  fi

  # Visitor sees no marks
  r=$(curl -s -o /dev/null -w "%{http_code}" "$API/marks")
  check "Visitor cannot access marks → 401" "401" "$r"

  # Elon deletes his mark
  if [ -n "$ELON_MARK_ID" ]; then
    r=$(curl -s -X DELETE "$API/marks/$ELON_MARK_ID" -H "$ELON")
    check "Elon deletes his mark" 'ok' "$r"
  fi
fi

# ─── 11. SOURCE OWNERSHIP ───
echo ""
echo "─── 11. Source Ownership ───"

# Coco tries to delete Elon's source
if [ -n "$ELON_SRC1" ]; then
  r=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API/sources/$ELON_SRC1" -H "$COCO")
  check "Coco cannot delete Elon's source → 403" "403" "$r"

  # Elon can delete his own
  r=$(curl -s -X DELETE "$API/sources/$ELON_SRC2" -H "$ELON")
  check "Elon deletes own private source" 'ok' "$r"
fi

# ─── 12. SUBSCRIPTION MANAGEMENT ───
echo ""
echo "─── 12. Subscription Toggle ───"

# Coco unsubscribes from one
if [ -n "$ELON_SRC1" ]; then
  r=$(curl -s -X DELETE "$API/subscriptions" -H "$COCO" -H "Content-Type: application/json" \
    -d "{\"sourceId\":$ELON_SRC1}")
  check "Coco unsubscribes from Simon Willison" '' "$r"

  r=$(curl -s "$API/subscriptions" -H "$COCO")
  SUB_COUNT=$(echo "$r" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  check "Coco now has 1 subscription" "1" "$SUB_COUNT"

  # Re-subscribe
  r=$(curl -s -X POST "$API/subscriptions" -H "$COCO" -H "Content-Type: application/json" \
    -d "{\"sourceId\":$ELON_SRC1}")
  check "Coco re-subscribes" '' "$r"
fi

# ─── 13. FEED OUTPUT ───
echo ""
echo "─── 13. Feed Output ───"

r=$(curl -s -o /dev/null -w "%{http_code}" "https://digest.kevinhe.io/feed/kevin.json")
check "JSON Feed accessible" "200" "$r"

r=$(curl -s "https://digest.kevinhe.io/feed/kevin.json" | head -c 100)
check "JSON Feed valid format" 'version' "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "https://digest.kevinhe.io/feed/kevin.rss")
check "RSS Feed accessible" "200" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" "https://digest.kevinhe.io/feed/nonexist.json")
check "Invalid slug → 404" "404" "$r"

# ─── 14. API SECURITY ───
echo ""
echo "─── 14. API Security ───"

r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/digests" -H "Content-Type: application/json" -d '{"type":"4h","content":"hack"}')
check "POST digest without API key → 401" "401" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/sources" -H "Content-Type: application/json" -d '{"name":"x","type":"rss","config":"{}"}')
check "Create source without login → 401" "401" "$r"

r=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/packs/kevin-ai-sources/install")
check "Install pack without login → 401" "401" "$r"

# ─── RESULTS ───
echo ""
echo "========================================="
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
