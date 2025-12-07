#!/system/bin/sh
# 模块操作脚本 - 使用 input keyevent 确保兼容性

MODDIR=${0%/*}
# 温控程序的工作目录
THERMAL_DIR="$MODDIR/bin"
# 温度配置文件
TEMP_FILE="$THERMAL_DIR/temp.txt"

# 获取当前实际温度墙函数
get_current_wall() {
    # 优先尝试读取/proc/shell-temp
    if [ -f "/proc/shell-temp" ]; then
        shell_temp=$(head -n1 /proc/shell-temp | awk '{print $NF}')
        if [ -n "$shell_temp" ] && [ "$shell_temp" -eq "$shell_temp" ] 2>/dev/null; then
            echo $((shell_temp / 1000))
            return
        fi
    fi
    
    # 如果失败，尝试读取thermal_zone
    for type in "shell_front" "shell_frame" "shell_back"; do
        zone=$(grep -l "$type" /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -n1)
        if [ -n "$zone" ]; then
            temp=$(cat "${zone%/type}/temp" 2>/dev/null)
            if [ -n "$temp" ]; then
                echo $((temp / 1000))
                return
            fi
        fi
    done
    
    echo "N/A"
}

# 获取temp.txt中的温度设置
get_config_temp() {
    if [ -f "$TEMP_FILE" ]; then
        temp=$(cat "$TEMP_FILE" 2>/dev/null)
        if [ -n "$temp" ]; then
            echo $((temp / 1000))
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# 初始化温度设置
init_temp() {
    # 如果temp.txt不存在，创建默认值
    if [ ! -f "$TEMP_FILE" ]; then
        mkdir -p "$THERMAL_DIR"
        echo "36000" > "$TEMP_FILE"
        echo "已创建默认温度配置文件: $TEMP_FILE"
    fi
}

# 启动温控程序
start_thermal_control() {
    # 检查温控程序是否在运行
    if pgrep -f "thermal_monitor" > /dev/null; then
        echo "温控程序已在运行"
        return 0
    fi
    
    # 检查文件是否存在
    if [ ! -f "$THERMAL_DIR/thermal_monitor" ]; then
        echo "错误: 温控程序未找到: $THERMAL_DIR/thermal_monitor"
        echo "请先安装温控程序"
        return 1
    fi
    
    if [ ! -f "$THERMAL_DIR/libthermal_hook.so" ]; then
        echo "错误: 劫持库未找到: $THERMAL_DIR/libthermal_hook.so"
        return 1
    fi
    
    # 设置权限
    chmod 755 "$THERMAL_DIR/thermal_monitor" 2>/dev/null
    chmod 644 "$THERMAL_DIR/libthermal_hook.so" 2>/dev/null
    
    # 启动温控程序
    cd "$THERMAL_DIR" && ./thermal_monitor &
    
    sleep 1
    if pgrep -f "thermal_monitor" > /dev/null; then
        echo "温控程序已启动"
        return 0
    else
        echo "错误: 温控程序启动失败"
        return 1
    fi
}

# 停止温控程序
stop_thermal_control() {
    # 停止温控监控程序
    pkill -f "thermal_monitor" 2>/dev/null
    
    # 停止带有劫持的horae进程
    pkill -f "LD_PRELOAD.*libthermal_hook.so" 2>/dev/null
    
    # 停止所有horae进程
    stop horae 2>/dev/null
    
    # 确保停止
    pkill -9 -f "/system_ext/bin/horae" 2>/dev/null
    
    echo "温控程序已停止"
}

# 清屏函数
clear_screen() {
  printf "\033c" 2>/dev/null || printf "\033[2J\033[1;1H" 2>/dev/null || {
    i=0
    while [ $i -lt 30 ]; do
      echo
      i=$((i + 1))
    done
  }
}

# 显示菜单
show_menu() {
  actual_wall=$(get_current_wall)
  config_temp=$(get_config_temp)
  
  echo "=============================="
  echo "  自定义温控墙温度设置"
  echo "  (默认52℃，电源键确认)"
  echo "=============================="
  
  i=53
  while [ $i -ge 41 ]; do
    if [ $i -eq $current ]; then
      echo "  [*] $i℃"
    else
      echo "  [ ] $i℃"
    fi
    i=$((i - 1))
  done
  
  echo
  echo "操作说明:"
  echo "  音量+ = 升高温度"
  echo "  音量- = 降低温度"
  echo "  电源键 = 确认选择"
  echo
  echo "当前选择: $current℃"
  echo "配置文件温度: $config_temp℃"
  echo "实际温度墙: $actual_wall℃"
  echo
  echo "温控程序状态: $thermal_status"
}

# 设置温度
set_temperature() {
  # 计算毫摄氏度值（直接使用摄氏度的1000倍）
  new_value=$((current * 1000))
  
  # 更新配置文件
  mkdir -p "$THERMAL_DIR"
  echo "$new_value" > "$TEMP_FILE"
  
  # 立即写入/proc/shell-temp（可选，温控程序会自动覆盖）
  for i in 0 1 2 3; do
    echo "$i $new_value" > /proc/shell-temp 2>/dev/null
  done
  
  # 重新启动温控程序确保生效
  stop_thermal_control
  sleep 1
  start_thermal_control
  
  echo "已设置温控墙为 ${current}℃ (对应 $new_value 毫摄氏度)"
  echo "配置文件: $TEMP_FILE"
}

# 使用 input keyevent 检测按键
detect_key() {
  # 监听按键事件（兼容所有设备）
  while :; do
    # 获取按键事件
    events=$(getevent -l -c 1 2>/dev/null)
    
    if [ -z "$events" ]; then
      # 尝试使用其他方法
      events=$(dumpsys input | grep "KeyEvent" | tail -1)
    fi
    
    # 解析按键（只匹配按下事件，忽略释放事件）
    case "$events" in
      *KEY_VOLUMEUP*DOWN*|*VOLUME_UP*DOWN*|*KEY_VOLUME_UP*DOWN*|*KEY_VOLUMEUP*)
        echo "up"
        # 添加延迟防止连击
        sleep 0.3
        return
        ;;
      *KEY_VOLUMEDOWN*DOWN*|*VOLUME_DOWN*DOWN*|*KEY_VOLUME_DOWN*DOWN*|*KEY_VOLUMEDOWN*)
        echo "down"
        sleep 0.3
        return
        ;;
      *KEY_POWER*DOWN*|*POWER*DOWN*|*KEY_ENTER*DOWN*|*KEY_POWER*)
        echo "enter"
        sleep 0.3
        return
        ;;
    esac
    
    # 如果没有检测到事件，使用更简单的检测方法
    if [ -z "$events" ]; then
      # 检查按键状态文件
      if [ -f /sys/class/input/input*/name ]; then
        for input in /sys/class/input/input*; do
          name=$(cat "$input/name" 2>/dev/null)
          case "$name" in
            *volume*)
              if grep -q "KEY_VOLUMEUP" "$input/event*/device/uevent" 2>/dev/null; then
                echo "up"
                return
              elif grep -q "KEY_VOLUMEDOWN" "$input/event*/device/uevent" 2>/dev/null; then
                echo "down"
                return
              fi
              ;;
            *power*|*Power*)
              if grep -q "KEY_POWER" "$input/event*/device/uevent" 2>/dev/null; then
                echo "enter"
                return
              fi
              ;;
          esac
        done
      fi
    fi
    
    # 短延迟避免CPU占用过高
    sleep 0.1
  done
}

# 主程序
main() {
  current=45
  
  # 初始化温度设置
  init_temp
  
  # 获取当前配置温度
  config_temp=$(get_config_temp)
  if [ "$config_temp" != "N/A" ]; then
    current=$config_temp
  fi
  
  # 检查温控程序状态
  if pgrep -f "thermal_monitor" > /dev/null; then
    thermal_status="运行中"
  else
    thermal_status="未运行"
  fi
  
  # 询问是否启动温控程序
  if [ "$thermal_status" = "未运行" ]; then
    echo "温控程序未运行，是否启动？(音量+ = 是, 音量- = 否)"
    while :; do
      key=$(detect_key)
      case "$key" in
        "up")
          if start_thermal_control; then
            thermal_status="运行中"
          fi
          break
          ;;
        "down")
          echo "跳过启动温控程序"
          break
          ;;
      esac
    done
  fi
  
  while true; do
    clear_screen
    show_menu
    
    # 获取按键方向
    key=$(detect_key)
    
    case "$key" in
      "up")
        [ $current -lt 53 ] && current=$((current + 1))
        ;;
      "down")
        [ $current -gt 41 ] && current=$((current - 1))
        ;;
      "enter")
        set_temperature
        echo "设置完成！3秒后返回..."
        sleep 3
        return
        ;;
    esac
  done
}

# 启动主程序
main