#!/bin/zsh

function read_with_interruption {
  common_message="и после нажмите Enter для продолжения. [q]=Выход;[s]=Пропуск;" &&
  read "is_end?$1 $common_message" &&
  if [[ "$is_end" == "q" ]]; then
    echo "Выполнение прервано." &&
    exit 0
  fi
}
function retry {
  local retval=1
  until [[ $retval -eq 0 ]]; do
      echo "$1" &&
      $1
      retval=$?
      if [[ $retval -ne 0 ]]; then
        read_with_interruption "$2" &&
        if [[ $is_end == "s" ]]; then
          retval=0
        fi
      fi
  done
}
function check_input_params {
  if [ -z "$config" ]; then
    echo "Передайте абсолютный путь до конфига." 1>&2 &&
    exit 1
  fi
}
function check_dependencies {
  not_available=() &&
  for cmd in curl jq docker git poetry pre-commit; do
    if ! command -v "$cmd" &>/dev/null; then
      not_available+=("$cmd")
    fi
  done &&
  if (( ${#not_available[@]} > 0 )); then
    echo "Установите следующие пакеты: ${not_available[@]}" 1>&2 &&
    exit 1
  fi
}
function read_config_vars {
  source=$(jq -r '.source' $config) &&
  gitlab_host=$(jq -r '.gitlab_host' $config) &&
  repos=$(jq -r '.repo_keys' $config) &&
  ticket=$(jq -r '.ticket' $config) &&
  commit_message=$(jq -r '.commit_message' $config) &&
  assignee_id=$(jq -r '.assignee_id' $config) &&
  reviewer_ids=$(jq -r '.reviewer_ids' $config) &&
  token=$(jq -r '.token' $config) &&
  packages=$(jq -r '.packages' $config)
}
function read_repo_vars {
  repo_pkgs=$(jq -r '.repos."'$repo'".packages' $config) &&
  target_branch=$(jq -r '.repos."'$repo'".target_branch' $config) &&
  project_id=$(jq -r '.repos."'$repo'".project_id' $config) &&
  mr_id=$(jq -r '.repos."'$repo'".mr_id' $config)
  is_need_changes=$(jq -r '.repos."'$repo'".is_need_changes' $config) &&
  pre_handler=$(jq -r '.repos."'$repo'".pre_handler' $config) &&
  post_handler=$(jq -r '.repos."'$repo'".post_handler' $config)
  do_test_skipping=$(jq -r '.repos."'$repo'".do_test_skipping' $config)
}
function make_branch_name {
  if $is_need_changes; then
    suffix=$(jq -r '.repos."'$repo'".branch.suffix' $config) &&
    dir=$(jq -r '.repos."'$repo'".branch.dir' $config)
  else
    dir=$(jq -r '.branch.dir' $config)
    suffix=$(jq -r 'join("-")' <<< "$repo_pkgs")"-update"
  fi &&
  source_branch=${dir}/${ticket}-$suffix
}
function checkout {
  git fetch -a &&
  make_branch_name &&
  if [[ $(git rev-parse --abbrev-ref HEAD) == "$source_branch" ]]; then
    is_already_checkout=true
  else
    is_already_checkout=false
  fi &&
  if [[ $(git diff --name-only) == "" ]]; then
    diff_before_stash=false
  else
    diff_before_stash=true
  fi &&
  if $diff_before_stash; then
    git stash -m "AUTOSTASH"
    is_stashed=true
  else
    is_stashed=false
  fi &&
  if $is_already_checkout || [ $(git rev-parse --verify "$source_branch" 2>/dev/null) ]; then
    git checkout $source_branch &&
    git rebase origin/$target_branch
  else
    git checkout -b $source_branch origin/$target_branch
  fi &&
  if $is_already_checkout && $is_stashed; then
      git stash pop
      is_stashed=false
  fi
}
function update_poetry_env {
  pkgs=$(echo $repo_pkgs | jq -r 'join(" ")') &&
  if [[ $pkgs == "" ]]; then
    poetry install
  else
    for package in $pkgs
    do
      new_package=$(echo $packages | jq -r '."'$package'"')
      poetry add "$new_package"
    done
  fi
}
function run_handler {
  if [[ $1 != null ]]; then
    $(echo "$1")
  fi
}
function run_pre_handler {
  run_handler "$pre_handler"
}
function run_post_handler {
  run_handler "$post_handler"
}
function run_pytest {
  if ! $do_test_skipping; then
    pytest --lf
  fi
}
function install_pre_commit {
  pre-commit install
}
function commit_updates {
  commit=(git commit -a -m "$ticket $commit_message." -m "[ci skip]") &&
  if [[ $is_need_changes == true ]]; then
    commit+=(-e)
  fi &&
  "${commit[@]}" || "${commit[@]}"
}
function push {
  git fetch -a &&
  git rebase origin/$target_branch &&
  git push --force origin HEAD
}
function create_mr {
  if [[ $mr_id == null ]]; then
    body='{
        "title": "Draft: '$source_branch'",
        "source_branch": "'$source_branch'",
        "target_branch": "'$target_branch'",
        "assignee_id": '$assignee_id',
        "reviewer_ids": '$reviewer_ids',
        "remove_source_branch": true
    }' &&
    local mr_id=$(curl --request POST -H "PRIVATE-TOKEN: $token" \
      -H "Content-Type: application/json" \
      -d "$body" "${gitlab_host}/projects/${project_id}/merge_requests" | jq '.iid') &&
    result=$(jq '.repos."'"$repo"'" += {"mr_id": '"$mr_id"'}' "$config") &&
    echo "$result" > "$config"
  fi
}
function handle_branch {
  read_repo_vars &&
  checkout &&
  update_poetry_env &&
  run_pre_handler &&
  if $is_need_changes; then
    read_with_interruption "Внесите изменения"
  fi &&
  if [[ $(git diff --name-only --cached) != "" || $(git diff --name-only) != "" ]]; then
    docker ps &&
    retry run_pytest "Почините тесты" &&
    retry install_pre_commit "Настройте pre-commit" &&
    retry commit_updates "Поправьте формат кода"
  fi &&
  run_post_handler &&
  push &&
  create_mr
}
function main {
  check_input_params "$1" &&
  check_dependencies &&
  read_config_vars &&
  cd "$source" &&
  for repo in $(echo $repos | jq -r 'join(" ")'); do
    echo "Разработка в $repo начата." &&
    cd ./$repo &&
    source "$(poetry env info --path)"/bin/activate &&
    handle_branch &&
    deactivate &&
    cd ../ &&
    echo "Разработка в ${repo} завершена."
  done &&
  echo "uppkgs успешно завершил работу!" &&
  exit 0
}



function append {
  local key_to_list=$1 &&
  local username=$2 &&
  local id=$(curl --header "PRIVATE-TOKEN: $token" "${gitlab_host}/users/\?username\=$username" | jq '.[].id') &&
  if ! local result=$(jq '.'"$key_to_list"' |= . + ['"$id"']' "$config"); then
    echo "$result" > "$config"
  else
    exit 1
  fi
}
function assign {
  local key_to_list=$1 &&
  local username=$2 &&
  local id=$(curl --header "PRIVATE-TOKEN: $token" ${gitlab_host}/users/\?username\=$username | jq '.[].id') &&
  if ! local result=$(jq '.'"$key_to_list"' |= '"$id"'' "$config"); then
    echo "$result" > "$config"
  else
    exit 1
  fi
}
function append_reviewer_id {
  append "reviewer_ids" "$1"
}
function assign_assignee_id {
  assign "assignee_id" "$1"
}
