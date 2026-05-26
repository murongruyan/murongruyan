#!/system/bin/sh

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 创建日志目录
mkdir -p logs

# 停止所有horae进程
echo "停止horae进程..."
stop horae 2>/dev/null
pkill -9 -f horae 2>/dev/null

# 等待确保进程停止
sleep 2

# 检查是否还有horae进程
if ps | grep -q horae; then
    echo "警告：仍有horae进程在运行"
    # 尝试更多方法停止
    for pid in $(ps | grep horae | grep -v grep | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null
    done
fi

# 启动监控程序
echo "启动温度监控..."
"./thermal_monitor" &

# 记录启动信息
echo "$(date): 温度控制已启动，PID: $!" >> logs/startup.log
echo "温度控制已启动"
echo "日志目录: $SCRIPT_DIR/logs/"
echo "修改 $SCRIPT_DIR/temp.txt 来调整温度"

# 保持脚本运行（可选）
while true; do
    sleep 3600
done