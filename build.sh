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

# write_list <name> <source> : тело со stdin → TMP/rules/<name>.list, с проверками размера
write_list() {
  local name=$1 src=$2 body old new
  body=$(sort -u)
  new=$(grep -c . <<<"$body" || true)
  [[ $new -gt 0 ]] || die "$name: источник $src пуст"
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

fetch Russia/inside-clashx.lst | clean \
  | sed -E 's/^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD),\./\1,/' \
  | write_list ru-inside "itdoginfo Russia/inside-clashx.lst"
fetch Services/telegram.lst | clean | sed -E 's/^\.//; s/^/DOMAIN-SUFFIX,/' \
  | write_list telegram "itdoginfo Services/telegram.lst"
fetch Subnets/IPv4/telegram.lst | clean | sed -E 's/^/IP-CIDR,/; s/$/,no-resolve/' \
  | write_list telegram-ip "itdoginfo Subnets/IPv4/telegram.lst"
fetch Subnets/IPv4/meta.lst | clean | sed -E 's/^/IP-CIDR,/; s/$/,no-resolve/' \
  | write_list meta-ip "itdoginfo Subnets/IPv4/meta.lst"

# Ручной список: каждая строка обязана быть правилом, иначе клиенты её молча выбросят.
CUSTOM=$OUT/rules/custom-proxy.list
[[ -f $CUSTOM ]] || die "нет $CUSTOM"
n=0
while IFS= read -r line; do
  n=$((n+1))
  l=$(clean <<<"$line")
  [[ -z $l ]] && continue
  [[ $l =~ ^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD),[A-Za-z0-9._-]+$ \
     || $l =~ ^IP-CIDR,[0-9.]+/[0-9]{1,2}(,no-resolve)?$ ]] \
    || die "custom-proxy.list:$n: '$l' — нужен вид DOMAIN-SUFFIX,<домен> или IP-CIDR,<сеть>,no-resolve"
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
RULE-SET,$CDN_BASE/rules/telegram.list,PROXY
RULE-SET,$CDN_BASE/rules/telegram-ip.list,PROXY,no-resolve
RULE-SET,$CDN_BASE/rules/meta-ip.list,PROXY,no-resolve
FINAL,DIRECT
EOF

mkdir -p "$OUT/rules"
cp "$TMP"/rules/*.list "$OUT/rules/"
cp "$TMP/shadowrocket.conf" "$OUT/"
echo "build: ok ($(grep -h '^# TOTAL' "$OUT"/rules/{ru-inside,telegram,telegram-ip,meta-ip}.list | awk '{s=s" "$3} END{print s}'))"
