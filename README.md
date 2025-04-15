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

2025.04.15

- 测试修复节点导入

## Panel

panel端执行：

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_pterodactyl.sh -o install_pterodactyl.sh && chmod 777 install_pterodactyl.sh && bash install_pterodactyl.sh
```

## Wings

wings端执行：

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_wings.sh -o install_wings.sh && chmod 777 install_wings.sh && bash install_wings.sh
```

## Import

panel端执行：

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/import_node.py -o import_node.py && chmod 777 import_node.py && python3 import_node.py
```

或

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/import_node.sh -o import_node.sh && chmod 777 import_node.sh && bash import_node.sh
```

会生成需要在wings端执行的命令

生成的命令执行完毕后，wings端再执行：

```shell
bash install_wings.sh
```

## Thanks

https://pterodactyl.io/
