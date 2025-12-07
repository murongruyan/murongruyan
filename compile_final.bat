@echo off
chcp 65001 >nul
set NDK_ROOT=D:\android-ndk-r27c
set TARGET_ARCH=aarch64-linux-android29

if not exist "%NDK_ROOT%" (
    echo 错误: 找不到 NDK 目录 "%NDK_ROOT%"
    echo 请修改脚本中的 NDK_ROOT 变量为正确的 NDK 路径。
    pause
    exit /b 1
)

echo 正在编译最终热控制方案...

REM 1. 编译劫持库
echo 编译劫持库...
"%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe" ^
--target=%TARGET_ARCH% ^
--sysroot="%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\sysroot" ^
-shared -fPIC -Wall -O3 ^
-o libthermal_hook.so ^
hook_write_v2.c ^
-ldl -lc

if exist libthermal_hook.so (
    echo 劫持库编译成功: libthermal_hook.so
) else (
    echo 劫持库编译失败!
    pause
    exit /b 1
)

echo.

REM 2. 编译监控守护进程
echo 编译监控守护进程...
"%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe" ^
--target=%TARGET_ARCH% ^
--sysroot="%NDK_ROOT%\toolchains\llvm\prebuilt\windows-x86_64\sysroot" ^
-Wall -O3 -fPIE -pie ^
-o thermal_monitor ^
thermal_monitor_v2.c ^
-lc

if exist thermal_monitor (
    echo 监控程序编译成功: thermal_monitor
) else (
    echo 监控程序编译失败!
    pause
    exit /b 1
)

echo.
echo 编译全部完成！
echo.
echo 使用说明：
echo 1. 在Android设备上创建一个工作目录，例如：/data/local/tmp/thermal_control/
echo    adb shell mkdir -p /data/local/tmp/thermal_control/logs
echo.
echo 2. 将以下文件推送到工作目录：
echo    adb push libthermal_hook.so /data/local/tmp/thermal_control/
echo    adb push thermal_monitor /data/local/tmp/thermal_control/
echo    adb push temp.txt /data/local/tmp/thermal_control/
echo.
echo 3. 设置权限：
echo    adb shell chmod +x /data/local/tmp/thermal_control/thermal_monitor
echo    adb shell chmod 644 /data/local/tmp/thermal_control/libthermal_hook.so
echo.
echo 4. 进入工作目录并启动监控：
echo    adb shell
echo    cd /data/local/tmp/thermal_control
echo    ./thermal_monitor
echo.
echo 5. 查看日志：
echo    ls logs/
echo    cat logs/thermal_hook.log
echo    cat logs/thermal_monitor.log
echo.
echo 6. 修改温度设置：
echo    编辑temp.txt文件即可，程序会自动读取新温度值
echo.
echo 注意：
echo - 需要root权限执行
echo - 程序会自动停止原有的horae进程
echo - 日志会保存在当前目录的logs文件夹下

pause