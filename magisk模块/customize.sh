#!/system/bin/sh
# 注意：这不是占位符！此脚本用于初始化模块并设置默认权限
SKIPUNZIP=0
# 延迟输出函数（带错误流重定向）
Outputs() {
  echo "$@" >&2
  sleep 0.07
}

# 音量键检测优化（超时+事件过滤）
Volume_key_monitoring() {
  local choose
  # 设置10秒超时防止卡死
  timeout=100
  while [ $timeout -gt 0 ]; do
    # 精确匹配按键事件
    choose=$(getevent -qlc 1 | awk -F' ' '/KEY_VOLUME(UP|DOWN)/ {print $3; exit}')
    case "$choose" in
      KEY_VOLUMEUP) echo 0; return 0 ;;
      KEY_VOLUMEDOWN) echo 1; return 0 ;;
    esac
    timeout=$((timeout - 1))
    sleep 0.1
  done
  echo 1
}

# 官方调度选择
ui_print " "
sleep 3
ui_print "请选择是否使用官方调度："
ui_print "  [音量+] 是 - 不解除官方限频"
ui_print "  [音量-] 否 - 解除官方限频（解除后不算官调，最好使用第三方调度，防止功耗爆炸）"
ui_print " "

sched_choice=$(Volume_key_monitoring)

if [ "$sched_choice" = "0" ]; then
  ui_print "已选择：保留官方调度"
  # 删除service.sh中的解除限频代码
  sed -i '/# 解除CPU频率限制/,/^$/d' "$MODPATH/service.sh" 2>/dev/null
else
  ui_print "已选择：解除官方限频（使用第三方调度）"
fi

# 设置必要权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
[ -f "$MODPATH/service.sh" ] && chmod 0755 "$MODPATH/service.sh"
[ -f "$MODPATH/dongtai.sh" ] && chmod 0755 "$MODPATH/dongtai.sh"
[ -d "$MODPATH/bin" ] && chmod -R 0755 "$MODPATH/bin"

Outputs "配置完成！重启后生效"

# module='murongruyan'
# 使用 MODPATH 变量以支持动态安装路径
module="$MODPATH"
dirs="/odm /my_product /vendor /system/vendor /product /system"

xml_override() {
  mkdir -p $(dirname $module$1)
  overrides="$2"

  for file in $(find $dirs -name "$1")
  do
    mkdir -p $(dirname $module$file)
    rows=$(cat $file)
    for override in $overrides; do
      key=$(echo $override | cut -f1 -d '=')
      value=$(echo $override | cut -f2 -d '=')
      rows=$(echo "$rows" | sed "s/<$key>.*</<$key>$value</")
    done
    echo "$rows" > $module$file
  done
}

# sys_thermal_control_config.xml sys_thermal_control_config_gt.xml
boolValues="feature_enable_item feature_safety_test_enable_item aging_thermal_control_enable_item"
intValues="aging_cpu_level_item high_temp_safety_level_item game_high_perf_mode_item normal_mode_item ota_mode_item racing_mode_item"
for file in $(find $dirs -name "sys_thermal_control_config*.xml")
do
  mkdir -p $(dirname $module$file)
  rows=$(cat $file | grep -v -E '(<gear_config|cpu=|fps=|<scene_|</scene_|<category_|</category_|<subitem|<level|\.)')

  for key in $boolValues; do
    rows=$(echo "$rows" | sed "s/<$key.*\/>/<$key booleanVal=\"false\" \/>/")
  done

  for key in $intValues; do
    rows=$(echo "$rows" | sed "s/<$key.*\/>/<$key intVal=\"-1\" \/>/")
  done

  echo "$rows" | tr -s '\n' > $module$file
done

# sys_thermal_config.xml
xml_override 'sys_thermal_config.xml' "isOpen=0
more_heat_threshold=550
heat_threshold=530
less_heat_threshold=500
preheat_threshold=480
preheat_dex_oat_threshold=460
thermal_battery_temp=0
is_feature_on=0
is_upload_log=0
is_upload_errlog=0"

# sys_high_temp_protect_*。xml
xml_override 'sys_high_temp_protect*xml' "isOpen=0
HighTemperatureProtectSwitch=false
HighTemperatureShutdownSwitch=false
HighTemperatureFirstStepSwitch=false
HighTemperatureProtectFirstStepIn=550
HighTemperatureProtectFirstStepOut=530
HighTemperatureProtectThresholdIn=570
HighTemperatureProtectThresholdOut=550
HighTemperatureProtectShutDown=750
MediumTemperatureProtectThreshold=10000
HighTemperatureDisableFlashSwitch=false
HighTemperatureDisableFlashLimit=480
HighTemperatureEnableFlashLimit=470
HighTemperatureDisableFlashChargeSwitch=false
HighTemperatureDisableFlashChargeLimit=460
HighTemperatureEnableFlashChargeLimit=450
camera_temperature_limit=520
HighTemperatureControlVideoRecordSwitch=false
HighTemperatureDisableVideoRecordLimit=550
HighTemperatureEnableVideoRecordLimit=520
ToleranceThreshold=50
ToleranceStart=480
ToleranceStop=460"

# refresh_rate_config.xml
for file in $(find $dirs -name "refresh_rate_config.xml"); do
  mkdir -p $(dirname $module$file)
  # 部分机型如9RT出现游戏锁帧，可能直接清空刷新率配置并不太好
  # cat $file | grep -v -E '(<tpitem|<item|<record)' | tr -s '\n' > $module$file

  # 有些配置出现换行符就炸了，例如：
  # <item package="com.mf.xxyzgame.wpp.game.hlqsgdzz.nearme.gamecenter"
  #        rateId="2-2-2-2" /><!--欢乐切水果大作战-->
  # cat $file | grep -v -E '(2-2-2-2|<record)' | tr -s '\n' > $module$file

  # 不怕换行，但是生成的配置很臃肿
  sed 's/<!--.*-->//' "$file" | grep -v -E '<item.*2-2-2-2.*/>' | sed 's/2-2-2-2/0-0-0-0/' | grep -v -E '<record' > $module$file

  # echo -n '' > $module$file
  # while read line
  # do
  #   case "$line" in
  #     *"<item"*|*"<tpitem"*|*"<record"*)
  #       case "$line" in
  #         *"0-0-0-0"*|*"activity"*)
  #           echo "  $line" >> $module$file
  #         ;;
  #         *"2-2-2-2"*)
  #           continue
  #         ;;
  #       esac
  #     ;;
  #     *)
  #       echo "$line" >> $module$file
  #     ;;
  #   esac
  # done < $file
done

# thermallevel_to_fps.xml
for file in $(find $dirs -name "thermallevel_to_fps.xml")
do
  mkdir -p $(dirname $module$file)
  cat $file | sed "s/fps=\".*\"/fps=\"144\"/" > $module$file
done

# oppo_display_perf_list.xml
# multimedia_display_perf_list.xml
for file in $(find $dirs -name "oppo_display_perf_list.xml")
do
  mkdir -p $(dirname $module$file)
  echo -n '' > $module$file
  skip=0
  while read line; do
    case "$line" in
     *"<name>"*)
       skip=0
       case "$line" in
        *"sf.dps.feature"*|*"com.android"*|*"system_server"*|*"/system"*|*"com.color"*|*"com.oppo"*|*"com.oplus"**"SmartVolume"*)
          skip=0
          echo "  $line" >> $module$file
        ;;
        *)
          skip=1
        ;;
       esac
     ;;
     '<?xml version="1.0" encoding="UTF-8"?>'|'<filter-conf>'|'</filter-conf>')
         echo "$line" >> $module$file
     ;;
     *)
       if [[ $skip == 0 ]]; then
         echo "  $line" >> $module$file
       fi
     ;;
    esac
  done < $file
done

# sys_resolution_switch_config.xml
for file in $(find $dirs -name "sys_resolution_switch_config.xml")
do
  mkdir -p $(dirname $module$file)
  echo -n '' > $module$file
  skip=0
  while read line; do
    case "$line" in
     *"<item package="*|*"<switchop package="*)
       echo "$line" > /dev/null
     ;;
     *)
       echo "$line" >> $module$file
     ;;
    esac
  done < $file
done

# game_thermal_config.xml
for file in $(find $dirs -name "game_thermal_config.xml")
do
  mkdir -p $(dirname $module$file)
  echo -n '' > $module$file
  if [[ $(grep cluster3 $file) != '' ]];then
  echo '<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
    </default_policy>
</game_thermal_config>' > $module$file
  else
  echo '<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
    </default_policy>
</game_thermal_config>' > $module$file
  fi
done

# charging_thermal_config_default.txt charging_hyper_mode_config.txt
for file in $(find $dirs -name "charging_*txt")
do
  mkdir -p $(dirname $module$file)
  echo -n '' > $module$file
  while read line; do
    case "$line" in
     *:=*)
       echo "$line" >> $module$file
     ;;
     *,*,*)
       temp=$(echo "$line" | awk -F, '{print $1}')
       current=$(echo "$line" | awk -F, '{print $2}')
       t=$(echo "$line" | awk -F, '{print $3}')
       temp=$((temp+40)) # + 4℃
       echo "$temp,$current,$t" >> $module$file
     ;;
     *)
       echo "$line" >> $module$file
     ;;
    esac
  done < $file
done

# 确保模块路径
module_path="/data/adb/modules_update/murongruyan"

# 创建系统目录
mkdir -p "$module_path/system"

# 将生成的文件移动到system/vendor目录
if [ -d "$module_path/vendor" ]; then
    mv "$module_path/vendor" "$module_path/system"
fi