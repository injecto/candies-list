#!/usr/bin/env bash
# Собирает общие правила для mihomo и Shadowrocket.
# Usage: ./build.sh [OUT_DIR]   env: SRC_BASE (источник itdoginfo), CDN_BASE (адрес раздачи)
# Всё сначала собирается во временный каталог; OUT_DIR трогается только если всё прошло.
set -euo pipefail
export LC_ALL=C   # детерминированная сортировка: иначе в en_US «DOMAIN,» и «DOMAIN-SUFFIX,» меняются местами

OUT=${1:-.}
SRC_BASE=${SRC_BASE:-https://raw.githubusercontent.com/itdoginfo/allow-domains/main}
CDN_BASE=${CDN_BASE:-https://cdn.jsdelivr.net/gh/injecto/candies-list@main}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/rules"

die() { echo "build: $*" >&2; exit 1; }
fetch() { curl -fsSL --retry 3 --max-time 60 "$SRC_BASE/$1" || die "не скачался $1"; }
clean() { tr -d '\r' | sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' | { grep -v '^$' || true; }; }

# Единый формат строки правила — используется и для custom-proxy.list, и для тела
# каждого сгенерированного списка (чтобы, например, HTML-страница ошибки, отданная
# вместо файла источником, не превратилась молча в "правило").
# Кириллические домены сюда не проходят — только punycode (xn--…).
OCT='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
IPV4="${OCT}\\.${OCT}\\.${OCT}\\.${OCT}"
PREFIX='(3[0-2]|[12]?[0-9])'
RULE_RE="^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD),[A-Za-z0-9._-]+\$|^IP-CIDR,${IPV4}/${PREFIX}(,no-resolve)?\$"
is_rule() { [[ $1 =~ $RULE_RE ]]; }

# write_list <name> <source> : тело со stdin → TMP/rules/<name>.list, с проверками размера и формата
write_list() {
  local name=$1 src=$2 body old new n=0 l
  body=$(sort -u)
  new=$(grep -c . <<<"$body" || true)
  [[ $new -gt 0 ]] || die "$name: источник $src пуст"
  while IFS= read -r l; do
    n=$((n+1))
    is_rule "$l" || die "$name.list: строка $n не похожа на правило (источник $src): '$l'"
  done <<<"$body"
  if [[ -f $OUT/rules/$name.list ]]; then
    old=$(grep -vc '^#' "$OUT/rules/$name.list" || true)
    (( new * 2 >= old )) || die "$name: было $old строк, стало $new — источник, похоже, сломан"
  fi
  { echo "# NAME: $name.list"
    echo "# SOURCE: $src"
    echo "# UPDATED: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# TOTAL: $new"
    echo "$body"; } > "$TMP/rules/$name.list"
}

# domains <источник> <имя>: голый список доменов → DOMAIN-SUFFIX (ведущая точка убирается)
domains() { fetch "$1" | clean | sed -E 's/^\.//; s/^/DOMAIN-SUFFIX,/' | write_list "$2" "itdoginfo $1"; }
# subnets <источник> <имя>: список подсетей → IP-CIDR,…,no-resolve
subnets() { fetch "$1" | clean | sed -E 's/^/IP-CIDR,/; s/$/,no-resolve/' | write_list "$2" "itdoginfo $1"; }

fetch Russia/inside-clashx.lst | clean \
  | sed -E 's/^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD),\./\1,/' \
  | write_list ru-inside "itdoginfo Russia/inside-clashx.lst"
domains Categories/hodca.lst        hodca           # сайты на Hetzner/OVH/DO/Cloudflare/AWS/Akamai — их режут по хостингу
domains Services/google_ai.lst      google-ai
domains Services/google_meet.lst    google-meet
domains Services/telegram.lst       telegram
subnets Subnets/IPv4/telegram.lst   telegram-ip
subnets Subnets/IPv4/meta.lst       meta-ip         # Meta по IP: у Quest SNI скрыт за ECH
subnets Subnets/IPv4/google_meet.lst google-meet-ip # медиа звонков Meet — UDP без домена, ловится только по IP

# Ручной список: каждая строка обязана быть правилом, иначе клиенты её молча выбросят.
# Комментарий допустим только на всю строку (первый непробельный символ — '#'):
# инлайн-хвост " # note" mihomo/Shadowrocket не режут — они пропускают строку целиком,
# только если '#' стоит первым символом, поэтому инлайн-комментарий тут — ошибка, а не
# то, что можно молча обрезать.
CUSTOM=$OUT/rules/custom-proxy.list
[[ -f $CUSTOM ]] || die "нет $CUSTOM"
n=0
while IFS= read -r line || [[ -n $line ]]; do
  n=$((n+1))
  l=$(tr -d '\r' <<<"$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [[ -z $l ]] && continue
  [[ $l == \#* ]] && continue
  is_rule "$l" \
    || die "custom-proxy.list:$n: '$l' — нужен вид DOMAIN-SUFFIX,<домен> или IP-CIDR,<сеть>,no-resolve; кириллические домены — в punycode (xn--…)"
done < "$CUSTOM"

cat > "$TMP/shadowrocket.conf" <<EOF
# candies-list: общие правила для Shadowrocket. Сервер добавляется в приложении отдельно.
# Исходники: https://github.com/injecto/candies-list
[General]
bypass-system = true
ipv6 = false
prefer-ipv6 = false
private-ip-answer = true
dns-server = https://1.1.1.1/dns-query, https://8.8.8.8/dns-query
fallback-dns-server = system
dns-direct-fallback-proxy = true
skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, localhost, *.local, captive.apple.com
tun-excluded-routes = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32
update-url = $CDN_BASE/shadowrocket.conf

[Rule]
RULE-SET,$CDN_BASE/rules/custom-proxy.list,PROXY
RULE-SET,$CDN_BASE/rules/ru-inside.list,PROXY
RULE-SET,$CDN_BASE/rules/hodca.list,PROXY
RULE-SET,$CDN_BASE/rules/google-ai.list,PROXY
RULE-SET,$CDN_BASE/rules/google-meet.list,PROXY
RULE-SET,$CDN_BASE/rules/telegram.list,PROXY
RULE-SET,$CDN_BASE/rules/telegram-ip.list,PROXY,no-resolve
RULE-SET,$CDN_BASE/rules/meta-ip.list,PROXY,no-resolve
RULE-SET,$CDN_BASE/rules/google-meet-ip.list,PROXY,no-resolve
FINAL,DIRECT
EOF

mkdir -p "$OUT/rules"
cp "$TMP"/rules/*.list "$OUT/rules/"
cp "$TMP/shadowrocket.conf" "$OUT/"
echo "build: ok ($(grep -h '^# TOTAL' "$OUT"/rules/{ru-inside,hodca,google-ai,google-meet,telegram,telegram-ip,meta-ip,google-meet-ip}.list | awk '{s=s" "$3} END{print s}'))"
