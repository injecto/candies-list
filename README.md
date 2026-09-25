# candies-list

Общие правила «что пускать через VPN» для mihomo и Shadowrocket.
Через VPN идёт только то, что есть в списках; всё остальное — напрямую.

## Shadowrocket на новом устройстве
1. Добавить сервер: в приложении Amnezia создать клиента xray для устройства,
   скопировать `vless://…` и в Shadowrocket нажать «+» (или отсканировать QR).
2. Config → «+» → Download from URL:
   `https://cdn.jsdelivr.net/gh/injecto/candies-list@main/shadowrocket.conf`
3. Выбрать этот конфиг и сервер, включить.

## Добавить исключение
Дописать строку в [`rules/custom-proxy.list`](rules/custom-proxy.list):
`DOMAIN-SUFFIX,example.com`. В течение нескольких минут правило работает на pi
(jsDelivr иногда отдаёт старую версию до ~10 минут), в Shadowrocket — после
обновления конфига (Config → потянуть вниз).
Строка не того вида сломает сборку — это нарочно: иначе клиенты
молча выбросили бы её.

## Списки
| Файл | Источник |
|---|---|
| custom-proxy.list | вручную |
| ru-inside.list | itdoginfo/allow-domains Russia/inside |
| telegram.list, telegram-ip.list | itdoginfo Services/telegram, Subnets/IPv4/telegram |
| meta-ip.list | itdoginfo Subnets/IPv4/meta (Meta только по IP: SNI скрыт за ECH) |
