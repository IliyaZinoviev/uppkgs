function retry {
    command=$1
    message="$2"
    retval=1
    is_end=''
    until [[ $retval -eq 0 ]]; do
        eval $command
        retval=$?
        if [[ $retval -ne 0 ]]; then
          read "?${message} и после нажмите Enter для продолжения. (Введите \"y\" для завершения скрипта)" is_end
        fi
        if [[ $is_end == "y" ]]; then
          echo "Выполнение прервано." 1>&2
          exit 0
        fi
    done
}

if [ -z "$1" ]
  then
    echo "Передайте абсолютный путь до конфига." 1>&2
    exit 1
fi

not_available=() &&
for cmd in curl jq docker git poetry pre-commit; do
  if ! command -v "$cmd" &>/dev/null; then
    not_available+=("$cmd")
  fi
done &&
if (( ${#not_available[@]} > 0 )); then
  echo "Установите следующие пакеты: ${not_available[@]}" 1>&2
  exit 1
fi &&

config=$1 &&
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

cd "$source" &&
for repo in $(echo $repos | jq -r 'join(" ")')
do
  echo "Обновление зависимостей в ${repo} начато." &&
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
    new_package=$(echo $packages | jq -r '."'$package'"')
    poetry add new_package
  done &&
  source "$(poetry env info --path)"/bin/activate &&
  retry "pytest -x" "Почините тесты" &&
  retry "pre-commit install" "Настройте pre-commit" &&
  commit=(git commit -a -m "$ticket $commit_message." -m "[ci skip]") &&
  retry "${commit[@]} || ${commit[@]}" "Поправьте формат кода и после можете продолжить скрипт, нажав Enter" &&
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
  cd ../ &&
  echo "Обновление зависимостей в ${repo} завершено."
done &&
echo "uppkgs успешно завершил работу!"
