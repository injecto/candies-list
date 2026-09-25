#!/usr/bin/env bash
# Тесты build.sh на локальных фикстурах. Запуск: test/run.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIX="file://$ROOT/test/fixtures"
fail=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }
new_out() { local d; d=$(mktemp -d); mkdir -p "$d/rules"; cp "$ROOT/rules/custom-proxy.list" "$d/rules/"; echo "$d"; }
body() { grep -v '^#' "$1"; }

# 1. нормализация: CRLF, комментарии, пустые, ведущая точка, дубли
O=$(new_out); SRC_BASE=$FIX "$ROOT/build.sh" "$O" >/dev/null 2>&1 || bad "build succeeds on fixtures"
[[ $(body "$O/rules/ru-inside.list") == $'DOMAIN,exact.example.org\nDOMAIN-SUFFIX,1337x.to\nDOMAIN-SUFFIX,ua' ]] && ok "ru-inside normalized" || bad "ru-inside normalized: $(body "$O/rules/ru-inside.list" | tr '\n' '|')"
[[ $(body "$O/rules/telegram.list") == $'DOMAIN-SUFFIX,cdn-telegram.org\nDOMAIN-SUFFIX,t.me\nDOMAIN-SUFFIX,telegram.org' ]] && ok "telegram domains" || bad "telegram domains: $(body "$O/rules/telegram.list" | tr '\n' '|')"
[[ $(body "$O/rules/telegram-ip.list") == $'IP-CIDR,5.28.192.0/18,no-resolve\nIP-CIDR,91.108.4.0/22,no-resolve' ]] && ok "telegram ips" || bad "telegram ips: $(body "$O/rules/telegram-ip.list" | tr '\n' '|')"
grep -q '^# TOTAL: 2$' "$O/rules/meta-ip.list" && ok "header TOTAL" || bad "header TOTAL"
grep -q $'\r' "$O"/rules/*.list && bad "no CR in output" || ok "no CR in output"

# 2. порядок правил в shadowrocket.conf
rules=$(sed -n '/^\[Rule\]/,$p' "$O/shadowrocket.conf" | grep -oE 'rules/[a-z-]+\.list|FINAL,DIRECT' | tr '\n' ' ')
[[ $rules == "rules/custom-proxy.list rules/ru-inside.list rules/telegram.list rules/telegram-ip.list rules/meta-ip.list FINAL,DIRECT " ]] && ok "rule order" || bad "rule order: $rules"
grep -q '^RULE-SET,https://cdn.jsdelivr.net/gh/injecto/candies-list@main/rules/meta-ip.list,PROXY,no-resolve$' "$O/shadowrocket.conf" && ok "ip rule-set has no-resolve" || bad "ip rule-set has no-resolve"
grep -q '^\[Proxy\]' "$O/shadowrocket.conf" && bad "no [Proxy] section" || ok "no [Proxy] section"
grep -q '^update-url = https://cdn.jsdelivr.net/gh/injecto/candies-list@main/shadowrocket.conf$' "$O/shadowrocket.conf" && ok "update-url" || bad "update-url"

# 3. идемпотентность: повторная сборка ничего не меняет (кроме строки UPDATED)
cp -r "$O" "$O.prev"; SRC_BASE=$FIX "$ROOT/build.sh" "$O" >/dev/null 2>&1
diff -r -I '^# UPDATED' "$O.prev" "$O" >/dev/null && ok "idempotent" || bad "idempotent"

# 4. голый домен в custom-proxy.list → ошибка, артефакты не тронуты
O=$(new_out); echo "example.com" >> "$O/rules/custom-proxy.list"
if SRC_BASE=$FIX "$ROOT/build.sh" "$O" 2>"$O/err"; then bad "bare domain rejected"; else grep -q 'custom-proxy.list:.*example.com' "$O/err" && ok "bare domain rejected with line" || bad "bare domain message: $(cat "$O/err")"; fi
[[ ! -e $O/shadowrocket.conf ]] && ok "nothing written on bad custom" || bad "nothing written on bad custom"

# 5. опечатка в типе правила
O=$(new_out); echo "DOMAN-SUFFIX,example.com" >> "$O/rules/custom-proxy.list"
SRC_BASE=$FIX "$ROOT/build.sh" "$O" 2>/dev/null && bad "typo rejected" || ok "typo rejected"

# 6. пустой источник → ошибка, старые списки целы
O=$(new_out); SRC_BASE=$FIX "$ROOT/build.sh" "$O" >/dev/null 2>&1; cp "$O/rules/meta-ip.list" "$O/meta.before"
E=$(mktemp -d); cp -r "$ROOT/test/fixtures/." "$E/"; : > "$E/Subnets/IPv4/meta.lst"
SRC_BASE="file://$E" "$ROOT/build.sh" "$O" 2>/dev/null && bad "empty source rejected" || ok "empty source rejected"
cmp -s "$O/meta.before" "$O/rules/meta-ip.list" && ok "old list kept on empty source" || bad "old list kept on empty source"

# 7. сокращение больше чем вдвое → ошибка
O=$(new_out); SRC_BASE=$FIX "$ROOT/build.sh" "$O" >/dev/null 2>&1
E=$(mktemp -d); cp -r "$ROOT/test/fixtures/." "$E/"; printf 'DOMAIN-SUFFIX,1337x.to\n' > "$E/Russia/inside-clashx.lst"
SRC_BASE="file://$E" "$ROOT/build.sh" "$O" 2>/dev/null && bad "shrink >2x rejected" || ok "shrink >2x rejected"

# 8. 404 источника → ошибка
O=$(new_out); SRC_BASE="file:///nonexistent" "$ROOT/build.sh" "$O" 2>/dev/null && bad "missing source rejected" || ok "missing source rejected"

# 9. последняя строка custom-proxy.list без завершающего перевода строки (веб-редактор GitHub так сохраняет)
O=$(new_out); printf 'example.org' >> "$O/rules/custom-proxy.list"
if SRC_BASE=$FIX "$ROOT/build.sh" "$O" 2>"$O/err"; then bad "no trailing newline: bad last line rejected"; else grep -q 'custom-proxy.list:.*example.org' "$O/err" && ok "no trailing newline: bad last line rejected with line" || bad "no trailing newline: bad last line message: $(cat "$O/err")"; fi
O=$(new_out); printf 'DOMAIN-SUFFIX,example.org' >> "$O/rules/custom-proxy.list"
SRC_BASE=$FIX "$ROOT/build.sh" "$O" >/dev/null 2>&1 && ok "no trailing newline: valid last line still builds" || bad "no trailing newline: valid last line still builds"

exit $fail
