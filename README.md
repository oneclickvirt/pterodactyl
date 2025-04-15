# Pterodactyl

## 说明

目前支持的系统

| 系统类型    | 版本范围                    | 备注         |
|-------------|----------------------------|--------------|
| Ubuntu      | 20.04(推荐), 22.04, 24.04  | 已支持       |
| Debian      | 11(Bullseye), 12(Bookworm) | 已支持       |
| AlmaLinux   | 8, 9                       | 未支持       |
| Rocky Linux | 8, 9                       | 未支持       |

## 更新

2025.04.14

- 测试修复debian上的panel和wings的安装

## Panel

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_pterodactyl.sh -o install_pterodactyl.sh && chmod 777 install_pterodactyl.sh && bash install_pterodactyl.sh
```

## Wings

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_wings.sh -o install_wings.sh && chmod 777 install_wings.sh && bash install_wings.sh
```

## Import

测试中，不要使用

```
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/import_node.py -o import_node.py && chmod 777 import_node.py && python3 import_node.py
```

## Thanks

https://pterodactyl.io/
