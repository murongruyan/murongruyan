#!/system/bin/sh
# 模块操作脚本 - 使用 input keyevent 确保兼容性

MODDIR=${0%/*}
# 温控程序的工作目录
THERMAL_DIR="$MODDIR/bin"
# 温度配置文件
TEMP_FILE="$THERMAL_DIR/temp.txt"

# 获取当前实际温度
get_current_temp() {
    # 尝试读取thermal_zone获取实际温度
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

# 获取温控墙温度（从/proc/shell-temp读取）
get_current_wall() {
    # 优先尝试读取/proc/shell-temp
    if [ -f "/proc/shell-temp" ]; then
        shell_temp=$(head -n1 /proc/shell-temp | awk '{print $NF}')
        if [ -n "$shell_temp" ] && [ "$shell_temp" -eq "$shell_temp" ] 2>/dev/null; then
            # 这就是温控墙温度
            echo $((shell_temp / 1000))
            return
        fi
    fi
    
    echo "N/A"
}

# 获取配置文件中的设置温度
get_config_temp() {
    if [ -f "$TEMP_FILE" ]; then
        temp=$(cat "$TEMP_FILE" 2>/dev/null)
        if [ -n "$temp" ]; then
            # 返回设置的温度（毫摄氏度转换为摄氏度）
            echo $((temp / 1000))
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# 获取计算出的温控墙温度（设置温度+15度）
get_wall_temp() {
    config_temp=$(get_config_temp)
    if [ "$config_temp" != "N/A" ]; then
        # 温控墙温度 = 设置温度 + 15度
        echo $((config_temp + 15))
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
  actual_temp=$(get_current_temp)  # 实际温度
  current_wall=$(get_current_wall)  # 当前温控墙
  config_temp=$(get_config_temp)    # 设置温度
  wall_temp=$(get_wall_temp)        # 计算出的温控墙
  
  echo "=============================="
  echo "  自定义温控墙温度设置"
  echo "  (设置温度，温控墙=设置+15℃)"
  echo "=============================="
  
  i=38  # 设置温度范围：26-38度（对应温控墙41-53度）
  while [ $i -ge 26 ]; do
    if [ $i -eq $current ]; then
      echo "  [*] 设置: ${i}℃ (温控墙: $((i + 15))℃)"
    else
      echo "  [ ] 设置: ${i}℃ (温控墙: $((i + 15))℃)"
    fi
    i=$((i - 1))
  done
  
  echo
  echo "操作说明:"
  echo "  音量+ = 升高温度"
  echo "  音量- = 降低温度"
  echo "  电源键 = 确认选择"
  echo
  echo "当前选择: 设置 ${current}℃ (温控墙: $((current + 15))℃)"
  echo "配置文件温度: 设置 ${config_temp}℃"
  echo "计算温控墙: ${wall_temp}℃"
  
  if [ "$current_wall" != "N/A" ]; then
    echo "实际温控墙: ${wall_temp}℃"
  fi
  
  if [ "$actual_temp" != "N/A" ] && [ "$actual_temp" -gt 0 ] 2>/dev/null; then
    echo "当前实际温度: ${actual_temp}℃"
  fi
  
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
  
  # 写入/proc/shell-temp的是设置温度，不是温控墙温度！
  # 温控程序会自己加上15度作为温控墙
  if [ -f "/proc/shell-temp" ]; then
    for i in 0 1 2 3; do
      echo "$i $new_value" > /proc/shell-temp 2>/dev/null
    done
    echo "已写入/proc/shell-temp（设置温度）: ${new_value}毫摄氏度"
  else
    echo "注意: /proc/shell-temp不存在，温控程序可能未正常运行"
  fi
  
  # 重新启动温控程序确保生效
  stop_thermal_control
  sleep 1
  if start_thermal_control; then
    echo "温控程序已重启"
  else
    echo "警告: 温控程序启动失败"
  fi
  
  echo
  echo "设置完成！"
  echo "设置温度: ${current}℃ (对应 $new_value 毫摄氏度)"
  echo "温控墙温度: $((current + 15))℃"
  echo "配置文件: $TEMP_FILE"
  echo "提示: 温控墙生效可能需要几秒钟时间"
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
  current=45  # 默认设置温度为45度，对应温控墙60度
  
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
        [ $current -lt 38 ] && current=$((current + 1))  # 设置温度上限38度
        ;;
      "down")
        [ $current -gt 26 ] && current=$((current - 1))  # 设置温度下限26度
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