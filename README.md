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
Строка не того вида — это нарочно красная сборка: Action упадёт, GitHub
пришлёт письмо, а списки не обновятся, пока строку не поправить (сам
custom-proxy.list при этом раздаётся как есть, так что до правки битая строка
может дойти до клиентов).

GitHub сам отключает scheduled workflow в публичном репозитории, если 60 дней
подряд не было активности (пуш/коммит); если списки перестали обновляться —
проверить и включить workflow заново во вкладке Actions (или просто запушить
любой коммит).

## Списки
| Файл | Источник |
|---|---|
| custom-proxy.list | вручную |
| ru-inside.list | itdoginfo/allow-domains Russia/inside |
| hodca.list | itdoginfo Categories/hodca — сайты на Hetzner/OVH/DigitalOcean/Cloudflare/AWS/Akamai, которые режут по хостингу |
| google-ai.list | itdoginfo Services/google_ai (Gemini, AI Studio…) |
| google-meet.list, google-meet-ip.list | itdoginfo Services/google_meet, Subnets/IPv4/google_meet (звук и видео звонков идут по UDP без домена — только по IP) |
| telegram.list, telegram-ip.list | itdoginfo Services/telegram, Subnets/IPv4/telegram |
| meta-ip.list | itdoginfo Subnets/IPv4/meta (Meta только по IP: SNI скрыт за ECH) |
