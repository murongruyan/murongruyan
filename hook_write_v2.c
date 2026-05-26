#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <time.h>
#include <dirent.h>
#include <sys/wait.h>

typedef ssize_t (*write_t)(int, const void *, size_t);
typedef int (*open_t)(const char *, int, ...);
typedef ssize_t (*read_t)(int, void *, size_t);
typedef ssize_t (*pread_t)(int, void *, size_t, off_t);

static write_t real_write = NULL;
static open_t real_open = NULL;
static read_t real_read = NULL;
static pread_t real_pread = NULL;

// 全局变量
static int is_hooked = 0;
static int last_temperature = 36000;
static char log_buffer[256];
static char log_dir[512] = "./logs";
static FILE *log_fp = NULL;

// 获取工作目录
static void get_work_dir(char *buf, size_t size) {
    char *env_dir = getenv("THERMAL_WORK_DIR");
    if (env_dir) {
        strncpy(buf, env_dir, size - 1);
        buf[size - 1] = '\0';
    } else {
        // 默认回退路径
        strncpy(buf, "/data/adb/modules/murongruyan", size - 1);
        buf[size - 1] = '\0';
    }
}

// 确保日志目录存在
static void ensure_log_dir() {
    char work_dir[512];
    get_work_dir(work_dir, sizeof(work_dir));
    
    // 正确拼接路径
    snprintf(log_dir, sizeof(log_dir), "%s/logs", work_dir);
    
    struct stat st = {0};
    if (stat(log_dir, &st) == -1) {
        mkdir(log_dir, 0777); // 使用 0777 确保权限足够
        chmod(log_dir, 0777);
    }
}

// 日志函数 - 写到执行目录下的logs文件夹
static void write_log(const char *msg) {
    if (!log_fp) {
        ensure_log_dir();
        
        char log_path[1024];
        snprintf(log_path, sizeof(log_path), "%s/thermal_hook.log", log_dir);
        log_fp = fopen(log_path, "a");
        if (!log_fp) return;
        // 确保日志文件权限宽泛，防止不同用户写入失败
        chmod(log_path, 0666);
    }
    
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);
    
    fprintf(log_fp, "[%s] PID=%d PPID=%d %s\n", 
            timestamp, getpid(), getppid(), msg);
    fflush(log_fp);
}

// 从配置文件读取温度
static void read_temperature() {
    char config_path[1024];
    get_work_dir(config_path, sizeof(config_path));
    strncat(config_path, "/temp.txt", sizeof(config_path) - strlen(config_path) - 1);
    
    FILE *fp = fopen(config_path, "r");
    if (fp) {
        if (fscanf(fp, "%d", &last_temperature) != 1) {
            last_temperature = 36000;
        }
        fclose(fp);
        
        // 减少日志刷屏，仅在出错时记录
        // snprintf(log_buffer, sizeof(log_buffer), 
        //         "从 %s 读取温度: %d", config_path, last_temperature);
        // write_log(log_buffer);
    } else {
        snprintf(log_buffer, sizeof(log_buffer),
                "无法打开配置文件: %s，使用默认温度36000", config_path);
        write_log(log_buffer);
        last_temperature = 36000;
    }
}

// 检查是否是目标文件
static int is_thermal_file(int fd) {
    char path[256];
    char proc_path[64];
    
    snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
    ssize_t len = readlink(proc_path, path, sizeof(path)-1);
    
    if (len != -1) {
        path[len] = '\0';
        if (strstr(path, "shell-temp") != NULL) {
            return 1;
        }
        // 增加对 thermal_zone 的检测
        if (strstr(path, "thermal_zone") != NULL && strstr(path, "temp") != NULL) {
             return 2; // 2 表示 thermal_zone 节点
        }
    }
    return 0;
}

// 劫持write函数
ssize_t write(int fd, const void *buf, size_t count) {
    if (!real_write) {
        real_write = (write_t)dlsym(RTLD_NEXT, "write");
    }
    
    int file_type = is_thermal_file(fd);
    
    // 如果是shell-temp文件或thermal_zone/temp，修改写入内容
    if (file_type > 0) {
        // 从配置文件读取最新温度
        read_temperature();
        
        char new_content[128];
        int len;
        
        if (file_type == 1) { // shell-temp
             if (!is_hooked) {
                snprintf(log_buffer, sizeof(log_buffer),
                        "拦截到对shell-temp的写入，原始内容: %.*s",
                        (int)count, (const char*)buf);
                write_log(log_buffer);
                is_hooked = 1;
            }
            
            len = snprintf(new_content, sizeof(new_content), 
                          "0 %d\n1 %d\n2 %d\n3 %d\n",
                          last_temperature, last_temperature,
                          last_temperature, last_temperature);
        } else { // thermal_zone
             // 减少日志
             // snprintf(log_buffer, sizeof(log_buffer),
             //        "拦截到对thermal_zone的写入，目标温度: %d", last_temperature);
             // write_log(log_buffer);
             
             len = snprintf(new_content, sizeof(new_content), "%d\n", last_temperature);
        }
        
        // 记录日志（为了防止日志刷屏，仅在 shell-temp 时频繁记录，thermal_zone 偶尔记录）
        if (file_type == 1 && rand() % 100 == 0) {
             snprintf(log_buffer, sizeof(log_buffer),
                    "覆盖写入: %s", new_content);
             write_log(log_buffer);
        }
        
        return real_write(fd, new_content, len);
    }
    
    return real_write(fd, buf, count);
}

// 劫持read函数
ssize_t read(int fd, void *buf, size_t count) {
    if (!real_read) {
        real_read = (read_t)dlsym(RTLD_NEXT, "read");
    }

    int file_type = is_thermal_file(fd);
    if (file_type > 0) {
        // 从配置文件读取最新温度
        read_temperature();
        
        char fake_content[128];
        int len = snprintf(fake_content, sizeof(fake_content), "%d\n", last_temperature);
        
        // 如果缓冲区太小，截断
        if (len > count) {
            len = count;
        }
        
        memcpy(buf, fake_content, len);
        
        // 极少记录日志 (1/5000 概率)
        if (rand() % 5000 == 0) {
            snprintf(log_buffer, sizeof(log_buffer),
                    "拦截到读取操作，返回伪造温度: %d", last_temperature);
            write_log(log_buffer);
        }
        
        return len;
    }

    return real_read(fd, buf, count);
}

// 劫持pread函数
ssize_t pread(int fd, void *buf, size_t count, off_t offset) {
    if (!real_pread) {
        real_pread = (pread_t)dlsym(RTLD_NEXT, "pread");
    }

    int file_type = is_thermal_file(fd);
    if (file_type > 0) {
        // 从配置文件读取最新温度
        read_temperature();
        
        char fake_content[128];
        int full_len = snprintf(fake_content, sizeof(fake_content), "%d\n", last_temperature);
        
        // 处理offset
        if (offset >= full_len) {
            return 0; // EOF
        }
        
        int remaining = full_len - offset;
        int len = (remaining > count) ? count : remaining;
        
        memcpy(buf, fake_content + offset, len);
        
        return len;
    }

    return real_pread(fd, buf, count, offset);
}

// 劫持open函数
int open(const char *pathname, int flags, ...) {
    mode_t mode = 0;
    
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    
    if (!real_open) {
        real_open = (open_t)dlsym(RTLD_NEXT, "open");
    }
    
    // 记录对shell-temp的打开操作
    // if (strstr(pathname, "shell-temp") != NULL) {
    //    snprintf(log_buffer, sizeof(log_buffer),
    //            "进程 %d 打开了文件: %s", getpid(), pathname);
    //    write_log(log_buffer);
    // }
    
    if (mode) {
        return real_open(pathname, flags, mode);
    } else {
        return real_open(pathname, flags);
    }
}

// 构造函数，在库加载时执行
__attribute__((constructor))
static void init_hook() {
    char msg[256];
    snprintf(msg, sizeof(msg), "热控制劫持库已加载，PID=%d", getpid());
    write_log(msg);
    
    // 初始读取温度
    read_temperature();
}