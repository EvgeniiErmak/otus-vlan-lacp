# Домашнее задание: Строим бонды и вланы (VLAN и LACP)

Курс «Администратор Linux. Professional» (OTUS).

## Структура репозитория

| Путь | Назначение |
|------|------------|
| [Vagrantfile](Vagrantfile) | Разворачивает 7 ВМ и запускает Ansible |
| [ansible/](ansible/) | Конфигурация Ansible: [hosts](ansible/hosts), [provision.yml](ansible/provision.yml), [ansible.cfg](ansible/ansible.cfg) |
| [ansible/templates/](ansible/templates/) | Шаблоны ifcfg (VLAN, bond0, eth1/eth2) и netplan |
| [scripts/](scripts/) | [git-push.sh](scripts/git-push.sh) — создание репозитория на GitHub и push |
| [checks.txt](checks.txt) | Полный вывод проверок |

## Текст задания

В Office1 в тестовой подсети появляются серверы с доп. интерфейсами и адресами в internal-сети **testLAN**:

- testClient1 — 10.10.10.254
- testClient2 — 10.10.10.254
- testServer1 — 10.10.10.1
- testServer2 — 10.10.10.1

Развести вланами:

- testClient1 <-> testServer1
- testClient2 <-> testServer2

Между centralRouter и inetRouter «пробросить» 2 линка (общая internal-сеть) и объединить их в бонд, проверить работу с отключением интерфейсов.

Формат сдачи: Vagrant + Ansible.

## Схема сети

~~~text
                 192.168.56.0/24 — host-only сеть управления (Ansible)

  +----------------------+     router-net (2 линка)     +--------------------------+
  |      inetRouter      | eth1 ----------------- eth1  |      centralRouter       |
  | bond0 192.168.255.1  | eth2 ----------------- eth2  | bond0 192.168.255.2/30   |
  | (active-backup)      |                              | eth3  192.168.255.9/30   |
  +----------------------+                              +------------+-------------+
                                                                     | office1-central
                                                        +------------+-------------+
                                                        |      office1Router       |
                                                        | eth1 192.168.255.10/30   |
                                                        +--------------------------+

                       testLAN (internal, кадры 802.1Q)
  +-----------------------------+------------------------------+
  | VLAN 1                      | VLAN 2                       |
  | testClient1 eth1.1          | testClient2 vlan2 (enp0s8)   |
  |   10.10.10.254/24           |   10.10.10.254/24            |
  | testServer1 eth1.1          | testServer2 vlan2 (enp0s8)   |
  |   10.10.10.1/24             |   10.10.10.1/24              |
  +-----------------------------+------------------------------+
~~~

| ВМ | ОС | Управление | Адреса стенда |
|----|----|------------|---------------|
| inetRouter | CentOS Stream 8 | 192.168.56.10 | bond0 192.168.255.1/30 |
| centralRouter | CentOS Stream 8 | 192.168.56.11 | bond0 192.168.255.2/30, eth3 192.168.255.9/30 |
| office1Router | CentOS Stream 8 | 192.168.56.20 | eth1 192.168.255.10/30 |
| testClient1 | CentOS Stream 8 | 192.168.56.21 | eth1.1 (VLAN 1) 10.10.10.254/24 |
| testServer1 | CentOS Stream 8 | 192.168.56.22 | eth1.1 (VLAN 1) 10.10.10.1/24 |
| testClient2 | Ubuntu 22.04 | 192.168.56.31 | vlan2 (VLAN 2) 10.10.10.254/24 |
| testServer2 | Ubuntu 22.04 | 192.168.56.32 | vlan2 (VLAN 2) 10.10.10.1/24 |

## Запуск

~~~bash
git clone https://github.com/EvgeniiErmak/otus-vlan-lacp.git
cd otus-vlan-lacp
vagrant up
~~~

Ansible запускается автоматически после создания последней ВМ (testServer2) сразу на все хосты.
Повторный прогон — `vagrant provision testServer2` или из корня проекта:

~~~bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/provision.yml
~~~

Протестировано: Ubuntu 26.04 (хост), VirtualBox 7.2.20, Vagrant 2.4.9, ansible-core 2.20.1.

## Что делает playbook ([provision.yml](ansible/provision.yml))

1. **Bootstrap CentOS Stream 8** — переключает репозитории на `vault.centos.org`, ставит `python39`.
2. **Base set up** — vim, traceroute, tcpdump, net-tools на всех хостах.
3. **set up vlan1** — testClient1/testServer1: шаблон [ifcfg-vlan1.j2](ansible/templates/ifcfg-vlan1.j2) → `/etc/sysconfig/network-scripts/ifcfg-vlan1`, рестарт NetworkManager.
4. **set up vlan2** — testClient2/testServer2: шаблон [50-cloud-init.yaml.j2](ansible/templates/50-cloud-init.yaml.j2) → `/etc/netplan/50-cloud-init.yaml`, `netplan apply`.
5. **set up bond0** — inetRouter/centralRouter: [ifcfg-bond0.j2](ansible/templates/ifcfg-bond0.j2), [ifcfg-eth1](ansible/templates/ifcfg-eth1), [ifcfg-eth2](ansible/templates/ifcfg-eth2), перезагрузка.

Параметры `vlan_id`, `vlan_ip`, `bond_ip` задаются в инвентаре [hosts](ansible/hosts).

## Проверка (команды и вывод)

Полный вывод — в [checks.txt](checks.txt).

### VLAN 1: testClient1 <-> testServer1

~~~text
[vagrant@testClient1 ~]$ ip -d link show eth1.1
    link/ether 08:00:27:74:87:82 brd ff:ff:ff:ff:ff:ff
    vlan protocol 802.1Q id 1 <REORDER_HDR>

[vagrant@testClient1 ~]$ ping -c 4 10.10.10.1
64 bytes from 10.10.10.1: icmp_seq=1 ttl=64 time=0.428 ms
...
4 packets transmitted, 4 received, 0% packet loss, time 3101ms

[vagrant@testClient1 ~]$ ip neigh show 10.10.10.1
10.10.10.1 dev eth1.1 lladdr 08:00:27:b6:35:3c REACHABLE     <-- MAC testServer1 (eth1.1)
~~~

### VLAN 2: testClient2 <-> testServer2

~~~text
vagrant@testClient2:~$ ip -d link show vlan2
    link/ether 08:00:27:10:b6:f8 brd ff:ff:ff:ff:ff:ff
    vlan protocol 802.1Q id 2 <REORDER_HDR>

vagrant@testClient2:~$ ping -c 4 10.10.10.1
64 bytes from 10.10.10.1: icmp_seq=1 ttl=64 time=0.420 ms
...
4 packets transmitted, 4 received, 0% packet loss, time 3055ms

vagrant@testClient2:~$ ip neigh show 10.10.10.1
10.10.10.1 dev vlan2 lladdr 08:00:27:67:96:3f REACHABLE      <-- MAC testServer2 (vlan2)
~~~

Оба сервера имеют адрес 10.10.10.1 в одной физической сети testLAN, но каждый клиент получает ответ
только от «своего» сервера (разные MAC в ARP-таблице) — трафик разведён VLAN'ами.

### Bond: состояние

~~~text
[vagrant@inetRouter ~]$ cat /proc/net/bonding/bond0
Bonding Mode: fault-tolerance (active-backup) (fail_over_mac active)
Currently Active Slave: eth2
MII Status: up
MII Polling Interval (ms): 100

Slave Interface: eth2
MII Status: up

Slave Interface: eth1
MII Status: up
~~~

### Bond: отключение интерфейса во время ping

На inetRouter запущен `ping 192.168.255.2`, на centralRouter выполнено `ip link set down eth1`:

~~~text
64 bytes from 192.168.255.2: icmp_seq=6 ttl=64 time=0.326 ms
64 bytes from 192.168.255.2: icmp_seq=8 ttl=64 time=0.681 ms      <-- переключение на eth2
...
20 packets transmitted, 19 received, 5% packet loss, time 9605ms

[root@centralRouter ~]# grep -E 'Currently Active Slave|Slave Interface|MII Status' /proc/net/bonding/bond0
Currently Active Slave: eth2
Slave Interface: eth1
MII Status: down
Slave Interface: eth2
MII Status: up
~~~

Аналогично при `ip link set down eth1` на inetRouter: `20 packets transmitted, 20 received, 0% packet loss`.
После `ip link set up eth1` интерфейс возвращается в bond (`MII Status: up`), связь сохраняется.

## Особенности проектирования и реализации

- **Box CentOS Stream 8.** Версия `20210210.0` из методички удалена с `cloud.centos.org` (HTTP 502),
  используется последняя доступная `20240603.0`, добавленная вручную:

  ~~~bash
  BASE=https://cloud.centos.org/centos/8-stream/x86_64/images
  FILE=CentOS-Stream-Vagrant-8-20240603.0.x86_64.vagrant-virtualbox.box
  curl -fLO $BASE/$FILE
  echo "{\"name\":\"centos/stream8\",\"versions\":[{\"version\":\"20240603.0\",\"providers\":[{\"name\":\"virtualbox\",\"url\":\"file://$PWD/$FILE\"}]}]}" > centos-stream8.json
  vagrant box add centos-stream8.json
  ~~~

- **CentOS Stream 8 — EOL.** Зеркала `mirror.centos.org` отключены, поэтому первым шагом репозитории
  переключаются на `vault.centos.org` (модуль `raw`, т.к. Python-модули ещё не работают).
- **ansible-core 2.17+ не поддерживает Python 3.6** на управляемых хостах (системный Python CentOS 8).
  Через `raw` ставится `python39`, для группы `centos` в инвентаре задан
  `ansible_python_interpreter=/usr/bin/python3.9`. Пакеты на CentOS ставятся командой `dnf`,
  т.к. модулю `dnf` нужны python-биндинги, которые есть только для 3.6.
- **Ubuntu:** box `ubuntu/jammy64` 20241002.0.0. Netplan-файл создаётся с правами `0600`
  (иначе `netplan apply` предупреждает об открытых правах), сетевая конфигурация cloud-init отключена,
  чтобы файл не перезаписывался.
- **Режим bond.** Как в методичке — `mode=1` (active-backup), `miimon=100`, `fail_over_mac=1`.
  Все 4 порта подключены к одной internal-сети VirtualBox `router-net`, которая работает как простой
  коммутатор без поддержки LACP (802.3ad). С `fail_over_mac=1` каждый слейв сохраняет свой MAC,
  поэтому виртуальный коммутатор не путается в таблице MAC-адресов при переключении.
  При отказе теряется максимум 1 пакет (интервал опроса MII 100 мс).
- **Vagrantfile.** Ansible-провижинер вызывается один раз — на последней ВМ с `limit = all`.
  Используются `linked_clone` (экономия места), префикс `vlan-` в именах ВМ VirtualBox
  (нет конфликтов с другими стендами), отключена синхронизация каталога `/vagrant`.

## Заметки

- Интерфейсы office1Router в сетях `vlan1`/`vlan2` создаются Vagrantfile'ом, но по заданию не настраиваются.
- Маршрутизация между сетями не настраивалась, поэтому из testLAN другие хосты недоступны — это ожидаемо.
- Сообщение Vagrant об отсутствии Guest Additions в CentOS-боксе не мешает работе (общие папки отключены).
