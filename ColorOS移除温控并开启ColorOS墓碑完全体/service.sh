#!/system/bin/sh
MODDIR=${0%/*}

# 等待系统启动完成
wait_sys_boot_completed() {
	local i=9
	until [ "$(getprop sys.boot_completed)" == "1" ] || [ $i -le 0 ]; do
		i=$((i-1))
		sleep 9
	done
}
wait_sys_boot_completed

# 启动动态温控守护进程
{
  # 避免僵尸进程
  trap 'exit 0' TERM
  # 执行动态温控脚本
  sh "$MODDIR/dongtai.sh" &
  wait $!
} &

# 初始化FreezerV2
for dir in frozen unfrozen; do
  mkdir -p "/sys/fs/cgroup/${dir}" || Outputs "目录创建失败: /sys/fs/cgroup/${dir}"
  chown system:system "/sys/fs/cgroup/${dir}/cgroup."{procs,freeze} 2>/dev/null
  echo 1 > "/sys/fs/cgroup/${dir}/cgroup.freeze" 2>/dev/null
done

# 解除CPU频率限制
[ -f /proc/game_opt/disable_cpufreq_limit ] && {
  echo 1 > /proc/game_opt/disable_cpufreq_limit
  chmod 444 /proc/game_opt/disable_cpufreq_limit
}
[ -f /sys/kernel/msm_performance/parameters/cpu_max_freq ] && {
max_freq=9999999
echo "0:$max_freq 1:$max_freq 2:$max_freq 3:$max_freq 4:$max_freq 5:$max_freq 6:$max_freq 7:$max_freq" >/sys/kernel/msm_performance/parameters/cpu_max_freq
chmod 444 /sys/kernel/msm_performance/parameters/cpu_max_freq
}