#!/bin/bash
#
# deployment_history.sh: Record ECS deploys and rollbacks as GitHub Deployments, and look up
# earlier ones to roll back to.
#
# Each account and service is one GitHub environment (e.g. production-web), so the repo's
# Deployments page shows what is live where. Every record's payload carries the task definition
# it deployed, the version people know it by (the release tag, or the short commit sha when
# there is no release) and who triggered it.
#
# Usage (GH_TOKEN needs deployments: write; GITHUB_* are set by Actions):
#   ENVIRONMENT=<env> REF=<sha> TASK_DEFINITION=<arn> [VERSION=<tag>] [DESCRIPTION=<text>] \
#     ./deployment_history.sh start
#       Creates the record, marks it in_progress and writes id=<deployment id> to $GITHUB_OUTPUT.
#   DEPLOYMENT_ID=<id> STATE=<success|failure|error> ./deployment_history.sh finish
#   ENVIRONMENT=<env> [MATCH_SHA=<sha>] [SKIP_SHA=<sha>] [GOOD_ONLY=0] ./deployment_history.sh find
#       Prints the newest record (as one line of JSON: sha, task_definition, version,
#       deployed_by, created_at) whose commit starts with MATCH_SHA and not with SKIP_SHA. Only
#       good records count unless GOOD_ONLY=0: finished successfully and never marked failed or
#       rolled back since. Prints nothing if there is none.
#   ENVIRONMENT=<env> CURRENT_SHA=<sha or short sha> ./deployment_history.sh mark-rolled-back
#       Marks every good record of the running commit as error, so a later rollback never goes
#       back to a version that was rolled back.

set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/${GITHUB_RUN_ID:-0}/attempts/${GITHUB_RUN_ATTEMPT:-1}"
API="repos/$GITHUB_REPOSITORY/deployments"

# "good" if the deploy finished successfully and was never marked failed or rolled back since
# (a later deploy may have added inactive on top), otherwise its latest state.
health() {
  gh api "$API/$1/statuses?per_page=100" --jq '
    [.[].state]
    | if any(.[]; . == "failure" or . == "error") then "bad"
      elif (.[0] == "success" or .[0] == "inactive") then "good"
      else (.[0] // "none") end'
}

# One line of JSON per record in the environment, newest first.
records() {
  gh api --paginate "$API?environment=$ENVIRONMENT&per_page=100" --jq '.[] | {
    id, sha, created_at, deployed_by: (.payload.deployed_by // .creator.login),
    task_definition: .payload.task_definition, version: .payload.version
  } | @json'
}

case "${1:-}" in
  start)
    : "${ENVIRONMENT:?}" "${REF:?}" "${TASK_DEFINITION:?}"
    version=${VERSION:-${REF:0:7}}
    description=${DESCRIPTION:-Deploy $version}
    # auto_merge would merge the default branch into REF, and required_contexts would block
    # the record on commit statuses; neither applies to recording an image that is already built.
    id=$(jq -n --arg ref "$REF" --arg env "$ENVIRONMENT" --arg desc "${description:0:140}" \
      --arg td "$TASK_DEFINITION" --arg version "$version" --arg by "${GITHUB_TRIGGERING_ACTOR:-${GITHUB_ACTOR:-}}" '{
          ref: $ref, environment: $env, description: $desc, auto_merge: false, required_contexts: [],
          production_environment: ($env | startswith("production")),
          payload: {task_definition: $td, version: $version, deployed_by: $by}
        }' | gh api "$API" --input - --jq '.id')
    gh api "$API/$id/statuses" -f state=in_progress -f log_url="$RUN_URL" --silent
    echo "Recorded GitHub deployment $id in $ENVIRONMENT: $description"
    echo "id=$id" >> "$GITHUB_OUTPUT"
    ;;

  finish)
    : "${DEPLOYMENT_ID:?}" "${STATE:?}"
    gh api "$API/$DEPLOYMENT_ID/statuses" -f state="$STATE" -f log_url="$RUN_URL" --silent
    echo "GitHub deployment $DEPLOYMENT_ID: $STATE"
    ;;

  find)
    : "${ENVIRONMENT:?}"
    list=$(records)
    while read -r record; do
      [ -n "$record" ] || continue
      sha=$(jq -r '.sha' <<< "$record")
      [ -z "${MATCH_SHA:-}" ] || [[ "$sha" == "$MATCH_SHA"* ]] || continue
      [ -z "${SKIP_SHA:-}" ] || [[ "$sha" != "$SKIP_SHA"* ]] || continue
      [ -n "$(jq -r '.task_definition // empty' <<< "$record")" ] || continue
      if [ "${GOOD_ONLY:-1}" != 0 ] && [ "$(health "$(jq -r '.id' <<< "$record")")" != good ]; then
        continue
      fi
      echo "$record"
      exit 0
    done <<< "$list"
    ;;

  mark-rolled-back)
    : "${ENVIRONMENT:?}" "${CURRENT_SHA:?}"
    list=$(records)
    while read -r record; do
      [ -n "$record" ] || continue
      read -r id sha < <(jq -r '"\(.id) \(.sha)"' <<< "$record")
      [[ "$sha" == "$CURRENT_SHA"* ]] || continue
      if [ "$(health "$id")" = good ]; then
        gh api "$API/$id/statuses" -f state=error -f description="Rolled back" -f log_url="$RUN_URL" --silent
        echo "Marked GitHub deployment $id ($sha) as rolled back"
      fi
    done <<< "$list"
    ;;

  *)
    echo "usage: $0 start|finish|find|mark-rolled-back" >&2
    exit 1
    ;;
esac
