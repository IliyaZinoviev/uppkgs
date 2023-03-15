curl --version > /dev/null 2>&1 &&
jq --version > /dev/null 2>&1 &&
config=$(jq -r '.config' ./.env.json) &&
source=$(jq -r '.source' $config) &&
gitlab_host=$(jq -r '.gitlab_host' $config) &&
repos=$(jq -r '.repo_keys' $config) &&
ticket=$(jq -r '.ticket' $config) &&
commit_message=$(jq -r '.commit_message' $config) &&
assignee_id=$(jq -r '.assignee_id' $config) &&
reviewer_ids=$(jq -r '.reviewer_ids' $config) &&
source_branch=feature/${ticket}-packages-updating &&
token=$(jq -r '.token' $config) &&
packages=$(jq -r '.packages' $config)
cd ~"$source" &&
for repo in $(echo $repos | jq -r 'join(" ")')
do
  repo_pkgs=$(jq -r '.repos."'$repo'".packages' $config) &&
  target_branch=$(jq -r '.repos."'$repo'".target_branch' $config) &&
  branch_title=$(echo $repo_pkgs | jq -r 'join("-")' ) &&
  source_branch=feature/${ticket}-${branch_title}-update &&
  project_id=$(jq -r '.repos."'$repo'".project_id' $config) &&
  cd ./$repo &&
  git stash -m "AUTOSTASH" &&
  git fetch -a &&
  git checkout -B $source_branch origin/$target_branch &&
  for package in $(echo $repo_pkgs | jq -r 'join(" ")')
  do
    name=$(echo $packages | jq -r '."'$package'"')
    poetry add $name
  done &&
  source "$(poetry env info --path)"/bin/activate &&
  pytest -x || read &&
  commit=(git commit -a -m "$ticket $commit_message." -m "[ci skip]") &&
  $commit || $commit || read || $commit || $commit &&
  git push origin HEAD &&
  body='{
          "title": "'$ticket' '$commit_message'",
          "source_branch": "'$source_branch'",
          "target_branch": "'$target_branch'",
          "assignee_id": '$assignee_id',
          "reviewer_ids": '$reviewer_ids',
          "remove_source_branch": true
  }' &&
  curl --request POST -H "PRIVATE-TOKEN: $token" \
    -H "Content-Type: application/json" \
    -d "$body" ${gitlab_host}/projects/${project_id}/merge_requests &&
  deactivate &&
  cd ../
done