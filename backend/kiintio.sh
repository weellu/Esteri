#!/usr/bin/env bash
# Workerin pyyntömäärä Cloudflaren analytiikasta.
#
# Wranglerin oma tunnus ei riitä: sillä on vain account (read). Luo token
# osoitteessa dash.cloudflare.com/profile/api-tokens oikeudella
#   Account > Account Analytics > Read
# ja tallenna se tiedostoon ~/.esteri-cf-token (chmod 600).
#
# Token ei kulje komentorivillä eikä päädy shell-historiaan.
#
#   ./kiintio.sh          # kuluva vuorokausi
#   ./kiintio.sh 7        # viimeiset 7 vrk päivittäin

set -euo pipefail

TOKEN_FILE="${ESTERI_CF_TOKEN_FILE:-$HOME/.esteri-cf-token}"
ACCOUNT="4434264dd53bfa0bf92c7ed7054eb58f"
SCRIPT_NAME="esteri-api"
DAYS="${1:-1}"

if [ ! -r "$TOKEN_FILE" ]; then
  echo "Tokenia ei löydy: $TOKEN_FILE" >&2
  echo "Luo se osoitteessa dash.cloudflare.com/profile/api-tokens" >&2
  echo "oikeudella Account > Account Analytics > Read." >&2
  exit 1
fi

TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
SINCE="$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
UNTIL="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

read -r -d '' QUERY <<'GQL' || true
query($account: String!, $script: String!, $since: Time!, $until: Time!) {
  viewer {
    accounts(filter: { accountTag: $account }) {
      workersInvocationsAdaptive(
        limit: 100
        filter: { scriptName: $script, datetime_geq: $since, datetime_leq: $until }
        orderBy: [datetimeHour_ASC]
      ) {
        sum { requests errors subrequests }
        dimensions { datetimeHour status }
      }
    }
  }
}
GQL

PAYLOAD="$(jq -n --arg q "$QUERY" --arg a "$ACCOUNT" --arg s "$SCRIPT_NAME" \
  --arg since "$SINCE" --arg until "$UNTIL" \
  '{query: $q, variables: {account: $a, script: $s, since: $since, until: $until}}')"

RESPONSE="$(curl -sS https://api.cloudflare.com/client/v4/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$PAYLOAD")"

if echo "$RESPONSE" | jq -e '.errors != null and (.errors | length > 0)' >/dev/null; then
  echo "Kysely epäonnistui:" >&2
  echo "$RESPONSE" | jq -r '.errors[].message' >&2
  exit 1
fi

echo "Aikaväli: $SINCE .. $UNTIL"
echo "$RESPONSE" | jq -r '
  .data.viewer.accounts[0].workersInvocationsAdaptive as $rows
  | if ($rows | length) == 0 then "Ei pyyntöjä tällä aikavälillä."
    else
      ($rows | map(.sum.requests) | add) as $total
      | ($rows | map(.sum.errors) | add) as $errors
      | ($rows | map(.sum.subrequests) | add) as $subs
      | "Pyyntöjä yhteensä: \($total)",
        "  virheitä:        \($errors)",
        "  alipyyntöjä:     \($subs)   (nämä menevät MML:lle)",
        "",
        "Ilmaistason raja on 100 000 pyyntöä/vrk (nollautuu keskiyöllä UTC).",
        "Osuus rajasta: \((($total / 100000) * 1000 | floor) / 10) %"
    end'
