#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <sys/wait.h>
#include <dirent.h>

#define PROC_THERMAL_PATH "/proc/shell-temp"
#define DEFAULT_LOG_DIR "./logs"
#define MAX_BUF_SIZE 4096

static FILE *log_fp = NULL;
static int daemon_pid = 0;
static char log_dir[512];

// 获取当前执行目录
void get_current_dir(char *buf, size_t size) {
    ssize_t len = readlink("/proc/self/exe", buf, size - 1);
    if (len != -1) {
        buf[len] = '\0';
        char *last_slash = strrchr(buf, '/');
        if (last_slash) {
            *last_slash = '\0';
        }
    } else {
        strncpy(buf, ".", size);
    }
}

// 确保日志目录存在
void ensure_log_dir() {
    char current_dir[512];
    get_current_dir(current_dir, sizeof(current_dir));
    
    // 使用 snprintf 避免重复追加
    snprintf(log_dir, sizeof(log_dir), "%s/logs", current_dir);
    
    struct stat st = {0};
    if (stat(log_dir, &st) == -1) {
        mkdir(log_dir, 0755);
    }
}

// 日志函数
void write_log(const char *msg) {
    if (!log_fp) {
        ensure_log_dir();
        
        char log_path[1024];
        snprintf(log_path, sizeof(log_path), "%s/thermal_monitor.log", log_dir);
        log_fp = fopen(log_path, "a");
        if (!log_fp) return;
    }
    
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);
    
    fprintf(log_fp, "[%s] PID=%d %s\n", timestamp, getpid(), msg);
    fflush(log_fp);
}

// 使用stop命令停止horae
void stop_horae_with_command() {
    write_log("使用stop命令停止horae进程");
    
    pid_t pid = fork();
    if (pid == 0) {
        // 子进程执行stop命令
        execlp("stop", "stop", "horae", NULL);
        
        // 如果stop失败，尝试其他方法
        execlp("pkill", "pkill", "-9", "-f", "/system_ext/bin/horae", NULL);
        execlp("killall", "killall", "horae", NULL);
        _exit(0);
    } else if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
        write_log("stop命令执行完成");
    }
}

// 检查horae是否在运行
int is_horae_running() {
    FILE *fp = popen("ps -A | grep horae | grep -v grep", "r");
    if (!fp) return 0;
    
    char buf[256];
    int running = 0;
    while (fgets(buf, sizeof(buf), fp)) {
        if (strstr(buf, "/system_ext/bin/horae")) {
            running = 1;
            break;
        }
    }
    pclose(fp);
    return running;
}

// 启动带有LD_PRELOAD的horae
int start_horae_with_hook(const char *hook_lib_path) {
    write_log("启动带有LD_PRELOAD的horae");
    
    char current_dir[1024];
    get_current_dir(current_dir, sizeof(current_dir));

    pid_t pid = fork();
    if (pid == 0) {
        // 子进程
        
        // 设置环境变量
        setenv("LD_PRELOAD", hook_lib_path, 1);
        setenv("THERMAL_WORK_DIR", current_dir, 1);
        
        // 执行horae - execl会自动继承环境变量
        execl("/system_ext/bin/horae", "horae", NULL);
        
        // 如果执行失败
        char msg[256];
        snprintf(msg, sizeof(msg), "execl失败: %s", strerror(errno));
        write_log(msg);
        _exit(1);
    } else if (pid > 0) {
        daemon_pid = pid;
        
        char msg[256];
        snprintf(msg, sizeof(msg), "horae已启动，PID=%d", pid);
        write_log(msg);
        return 0;
    } else {
        write_log("fork失败");
        return -1;
    }
}

// 监控文件变化
void monitor_thermal_file() {
    write_log("开始监控温度文件");
    
    int inotify_fd = inotify_init();
    if (inotify_fd < 0) {
        write_log("inotify初始化失败");
        return;
    }
    
    // 监控shell-temp文件的写入
    int wd = inotify_add_watch(inotify_fd, PROC_THERMAL_PATH, 
                               IN_CLOSE_WRITE | IN_MODIFY | IN_ACCESS);
    if (wd < 0) {
        char msg[256];
        snprintf(msg, sizeof(msg), "无法监控 %s: %s", 
                PROC_THERMAL_PATH, strerror(errno));
        write_log(msg);
        close(inotify_fd);
        return;
    }
    
    char buffer[MAX_BUF_SIZE];
    
    while (1) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(inotify_fd, &readfds);
        
        struct timeval timeout = {1, 0}; // 1秒超时
        
        int ret = select(inotify_fd + 1, &readfds, NULL, NULL, &timeout);
        
        if (ret < 0) {
            if (errno == EINTR) continue;
            write_log("select错误");
            break;
        } else if (ret == 0) {
            // 超时，检查horae进程状态
            static time_t last_check = 0;
            time_t now = time(NULL);
            if (now - last_check >= 5) {
                if (daemon_pid > 0) {
                    if (kill(daemon_pid, 0) < 0) {
                        write_log("horae进程已退出，正在重启");
                        // 重新启动
                        char hook_path[1024];
                        get_current_dir(hook_path, sizeof(hook_path));
                        strncat(hook_path, "/libthermal_hook.so", 
                               sizeof(hook_path) - strlen(hook_path) - 1);
                        start_horae_with_hook(hook_path);
                    }
                }
                last_check = now;
            }
            continue;
        }
        
        // 有事件
        ssize_t len = read(inotify_fd, buffer, sizeof(buffer));
        if (len < 0) {
            if (errno == EINTR) continue;
            break;
        }
        
        char *ptr = buffer;
        while (ptr < buffer + len) {
            struct inotify_event *event = (struct inotify_event *)ptr;
            
            if (event->mask & (IN_CLOSE_WRITE | IN_MODIFY)) {
                // 读取文件内容
                FILE *fp = fopen(PROC_THERMAL_PATH, "r");
                if (fp) {
                    char content[256];
                    if (fgets(content, sizeof(content), fp)) {
                        // 减少日志刷屏，不再记录每次内容变化
                        // char msg[256];
                        // snprintf(msg, sizeof(msg), 
                        //         "文件被修改，当前内容: %s", content);
                        // write_log(msg);
                    }
                    fclose(fp);
                }
            }
            
            ptr += sizeof(struct inotify_event) + event->len;
        }
    }
    
    close(inotify_fd);
}

// 信号处理
void signal_handler(int sig) {
    write_log("收到退出信号");
    
    if (daemon_pid > 0) {
        kill(daemon_pid, SIGTERM);
        waitpid(daemon_pid, NULL, 0);
    }
    
    if (log_fp) fclose(log_fp);
    exit(0);
}

int main(int argc, char *argv[]) {
    // 设置信号处理
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    write_log("温度监控守护进程启动");
    
    // 获取当前目录
    char current_dir[1024];
    get_current_dir(current_dir, sizeof(current_dir));
    write_log(current_dir);
    
    // 1. 停止原有的horae
    stop_horae_with_command();
    sleep(1);
    
    // 2. 检查是否还有horae运行，如果有则再次停止
    if (is_horae_running()) {
        write_log("检测到horae仍在运行，再次停止");
        stop_horae_with_command();
        sleep(1);
    }
    
    // 3. 构建hook库路径
    char hook_lib_path[1024];
    snprintf(hook_lib_path, sizeof(hook_lib_path), 
            "%s/libthermal_hook.so", current_dir);
    
    // 4. 启动带劫持的horae
    if (access(hook_lib_path, F_OK) != 0) {
        char msg[256];
        snprintf(msg, sizeof(msg), "劫持库不存在: %s", hook_lib_path);
        write_log(msg);
        return 1;
    }
    
    start_horae_with_hook(hook_lib_path);
    
    // 5. 开始监控文件变化
    monitor_thermal_file();
    
    return 0;
}