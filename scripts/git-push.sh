#!/usr/bin/env bash
# Создание репозитория на GitHub (REST API + Personal access token classic) и push проекта.
set -euo pipefail

GH_USER="EvgeniiErmak"
GH_EMAIL="djermak3000@mail.ru"
REPO="otus-vlan-lacp"
DESC="OTUS Linux Professional: VLAN и LACP (bonding) - Vagrant + Ansible"

cd "$(dirname "$0")/.."

# Токен: из GH_TOKEN, из ~/.git-credentials или запрос с клавиатуры
TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f ~/.git-credentials ]; then
  TOKEN=$(sed -n 's#^https://[^:]*:\([^@]*\)@github\.com.*#\1#p' ~/.git-credentials | head -1)
fi
if [ -z "$TOKEN" ]; then
  read -rsp "Personal access token (classic): " TOKEN; echo
  printf 'https://%s:%s@github.com\n' "$GH_USER" "$TOKEN" > ~/.git-credentials
  chmod 600 ~/.git-credentials
fi

# Создаём репозиторий, если его ещё нет
CODE=$(curl -s -o /tmp/gh_repo.json -w '%{http_code}' \
  -H "Authorization: token $TOKEN" "https://api.github.com/repos/$GH_USER/$REPO")
if [ "$CODE" = "404" ]; then
  curl -sf -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO\",\"description\":\"$DESC\",\"private\":false}" >/dev/null
  echo "Репозиторий $GH_USER/$REPO создан"
elif [ "$CODE" = "200" ]; then
  echo "Репозиторий $GH_USER/$REPO уже существует"
else
  echo "Ошибка GitHub API (HTTP $CODE):"; cat /tmp/gh_repo.json; exit 1
fi

# Git: инициализация, коммит, пуш
git config --global user.name  "$GH_USER"
git config --global user.email "$GH_EMAIL"
git config --global credential.helper store
[ -d .git ] || git init -b main
git checkout -B main
git add -A
git commit -m "VLAN и LACP (bonding): Vagrantfile, Ansible, README" || echo "Нечего коммитить"
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$GH_USER/$REPO.git"
git push -u origin main

echo
echo "Готово: https://github.com/$GH_USER/$REPO"
