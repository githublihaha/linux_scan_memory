# 搜索linux内存的小脚本
> MAX_PID -> /proc/PID/maps -> /proc/PID/mem -> search <string>

直接在命令行运行时输入要查询的字符串 ./find_mem.sh --busybox www[.]example.com

## 改进
+ 取消搜索除栈地址之外的高位地址
+ 从当前运行的脚本的PID开始倒序扫描，最小PID>2000，小PID的都是系统进程。
+ 按内存段权限过滤，跳过不可读区域
+ 避免不必要的十六进制与十进制反复转换
+ 如果在本目录下存在busybox，并且制定了--busybox，则使用busybox中的命令，针对系统命令被替换了的场景。但是busybox中的命令的参数支持较少，显示效果不如系统自带的好

## 参考
https://github.com/Just-Hack-For-Fun/Linux-INCIDENT-RESPONSE-COOKBOOK/releases/tag/v1.9
