#!/bin/bash

##############################################################################
# 函数：输出帮助信息并退出
##############################################################################
usage() {
    echo "Usage: $0 [options] <SEARCH_STRING>"
    echo
    echo "Options:"
    echo "  --busybox       Use BusyBox commands from the current directory if available."
    echo "  -h, --help      Show this help message and exit."
    echo
    echo "Example:"
    echo "  $0 www.baidu1"
    echo "  $0 --busybox www.baidu1"
    exit 1
}

##############################################################################
# 解析命令行参数
##############################################################################

USE_BUSYBOX=0
SEARCH_STRING=""

# 如果用户没有传任何参数，直接输出帮助
[ $# -eq 0 ] && usage

# 遍历所有参数
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --busybox)
            USE_BUSYBOX=1
            shift
            ;;
        # 如果不是以上两种，就当做搜索字符串
        *)
            SEARCH_STRING="$1"
            shift
            ;;
    esac
done

# 如果最后仍没有获得 SEARCH_STRING，则退出
if [ -z "$SEARCH_STRING" ]; then
    echo "Error: SEARCH_STRING not specified!"
    usage
fi

##############################################################################
# 根据 USE_BUSYBOX 的值，决定使用 BusyBox 还是系统命令
##############################################################################

if [ "$USE_BUSYBOX" -eq 1 ]; then
    # 检查当前目录下是否存在可执行的 ./busybox
    if [ -x "./busybox" ]; then
        echo "Using BusyBox commands..."

        CMD_LS="./busybox ls"
        CMD_GREP="./busybox grep"  # 后续脚本里会加 -qa
        CMD_AWK="./busybox awk"
        CMD_CUT="./busybox cut"
        CMD_DD="./busybox dd"
        
        # BusyBox ps: 这几个参数通常可用
        CMD_PS="./busybox ps -o pid,ppid,user,group,args"
        
        CMD_READLINK="./busybox readlink"
        
        # 给 pstree 设置 -p，显示 PID。如果 BusyBox 不支持 -p，可去掉
        CMD_PSTREE="./busybox pstree -p"
        
        CMD_TR="./busybox tr"
        CMD_SORT="./busybox sort"
    else
        echo "Error: --busybox specified, but ./busybox not found or not executable."
        exit 1
    fi
else
    echo "Using system commands..."

    CMD_LS="ls"
    CMD_GREP="grep"
    CMD_AWK="awk"
    CMD_CUT="cut"
    CMD_DD="dd"
    
    # 系统命令行可用更复杂的 ps 参数
    CMD_PS="ps -axjf"
    
    CMD_READLINK="readlink"
    
    # 系统自带 pstree 假设支持 -aps
    CMD_PSTREE="pstree -aps"
    
    CMD_TR="tr"
    CMD_SORT="sort"
fi

##############################################################################
# 脚本核心逻辑：搜索进程内存，匹配指定字符串
##############################################################################

# 获取当前脚本的 PID
SCRIPT_PID=$$
echo "Current FIND Process PID is $SCRIPT_PID"
echo "SEARCH_STRING is '$SEARCH_STRING'"

# 从 /proc 中获取所有有效的 PID，大于等于 2000，并且小于当前脚本 PID
for pid in $($CMD_LS /proc \
    | $CMD_GREP -E '^[0-9]+$' \
    | $CMD_AWK -v script_pid="$SCRIPT_PID" '$1 >= 2000 && $1 < script_pid' \
    | $CMD_SORT -nr); do

    echo "Scanning PID $pid..."

    map_file="/proc/$pid/maps"
    if [ ! -e "$map_file" ]; then
        continue
    fi

    # 遍历内存映射中的每一行
    while IFS= read -r line; do
        # 提取内存区域的起始地址和结束地址
        address=$($CMD_AWK '{print $1}' <<< "$line")
        start_addr=$($CMD_CUT -d- -f1 <<< "$address")
        end_addr=$($CMD_CUT -d- -f2 <<< "$address")

        # 提取权限
        perms=$($CMD_AWK '{print $2}' <<< "$line")
        # 第 6 列：映射文件路径或 [stack]/[heap] 等
        region=$($CMD_AWK '{print $6}' <<< "$line")

        # 1) 跳过无读权限的内存段
        if [[ "$perms" != *"r"* ]]; then
            continue
        fi

        # 2) 跳过 7f/ff 高位地址段（通常是共享库/内核空间），除非是 [stack]
        if [[ ("$start_addr" == 7f* || "$start_addr" == ff*) && "$region" != "[stack]" ]]; then
            continue
        fi

        # 3) 计算本段内存大小
        skip_bytes=$((0x$start_addr))
        size_bytes=$((0x$end_addr - 0x$start_addr))
        [ "$size_bytes" -le 0 ] && continue

        mem_file="/proc/$pid/mem"
        if [ -e "$mem_file" ]; then
            # 使用 dd + grep 搜索
            $CMD_DD if="$mem_file" bs=1 skip="$skip_bytes" count="$size_bytes" 2>/dev/null \
            | $CMD_GREP -qa "$SEARCH_STRING" && {
                
                echo "[+] Found '$SEARCH_STRING' in PID $pid"
                echo "---- Process Info ----"

                # (1) cmdline
                if [ -r "/proc/$pid/cmdline" ]; then
                    cmdline=$($CMD_TR '\0' ' ' < "/proc/$pid/cmdline")
                    echo "cmdline : $cmdline"
                fi

                # (2) /proc/<pid>/exe 链接
                if [ -L "/proc/$pid/exe" ]; then
                    exe_path=$($CMD_READLINK "/proc/$pid/exe")
                    echo "exe     : $exe_path"
                fi

                # (3) 使用上面定义的 CMD_PS
                echo "ps info :"
                # 打印所有进程，然后过滤出标题 + PID 行
                $CMD_PS | $CMD_AWK -v thepid="$pid" 'NR==1 || $1 == thepid'

                # (4) 使用 pstree
                echo "pstree info :"
                if command -v $CMD_PSTREE >/dev/null 2>&1; then
                    $CMD_PSTREE "$pid"
                else
                    echo "pstree not available."
                fi

                echo "----------------------"
            }
        fi
    done < "$map_file"
done