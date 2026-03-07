#!/bin/bash

# 定义需要修改的文件列表
patch_files=(
    fs/exec.c
    fs/stat.c
    fs/open.c
    kernel/reboot.c
    kernel/sys.c
)

for i in "${patch_files[@]}"; do

    # 检查是否已经存在相关 Hook，避免重复修改
    if grep -q "CONFIG_KSU_MANUAL_HOOK" "$i"; then
        echo "跳过: $i 已包含 KSU 手动挂钩 (Manual Hook)"
        continue
    fi

    case $i in

    ## 1.patch: fs/exec.c
    fs/exec.c)
        echo "正在修改: $i"
        # 插入外部函数声明 (在 do_execveat_common 之前)
        sed -i '/static int do_execveat_common/i\#ifdef CONFIG_KSU_MANUAL_HOOK\n__attribute__((hot))\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n\t\t\t\tvoid *argv, void *envp, int *flags);\n#endif' fs/exec.c
        
        # 在 do_execve 中插入 Hook
        sed -i '/struct user_arg_ptr envp = { .ptr.native = __envp };/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n#endif' fs/exec.c
        
        # 在 compat_do_execve 中插入 Hook
        sed -i '/.ptr.compat = __envp,/a\ \t};\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n#endif' fs/exec.c
        # 注意：上面的 sed 可能会因为原本的括号闭合逻辑略有偏移，建议检查 compat 结构体结尾
        ;;

    ## 2.patch: fs/stat.c
    fs/stat.c)
        echo "正在修改: $i"
        # 插入声明
        sed -i '/SYSCALL_DEFINE2(newlstat/i\#ifdef CONFIG_KSU_MANUAL_HOOK\n__attribute__((hot)) \nextern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *flags);\n\nextern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);\n#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\nextern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);\n#endif\n#endif' fs/stat.c
        
        # newfstatat Hook
        sed -i '/struct kstat stat;/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_stat(&dfd, &filename, &flag);\n#endif' fs/stat.c
        
        # newfstat 返回值 Hook
        sed -i '/error = cp_new_stat(&stat, statbuf);/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_newfstat_ret(&fd, &statbuf);\n#endif' fs/stat.c
        
        # fstat64 返回值 Hook
        sed -i '/error = cp_new_stat64(&stat, statbuf);/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_fstat64_ret(&fd, &statbuf);\n#endif' fs/stat.c
        ;;

    ## 3.patch & 4.patch: fs/open.c
    fs/open.c)
        echo "正在修改: $i"
        # 插入 faccessat 声明
        sed -i '/long do_faccessat/i\#ifdef CONFIG_KSU_MANUAL_HOOK\n__attribute__((hot)) \nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *mode, int *flags);\n#endif' fs/open.c
        
        # 在 SYSCALL_DEFINE3(faccessat, ...) 中插入 Hook
        # 匹配 access() 逻辑中的 flags/mode 校验位置
        sed -i '/if (mode & ~S_IRWXO)/i\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n#endif' fs/open.c
        ;;

    ## 5.patch: kernel/reboot.c
    kernel/reboot.c)
        echo "正在修改: $i"
        sed -i '/SYSCALL_DEFINE4(reboot/i\#ifdef CONFIG_KSU_MANUAL_HOOK\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n#endif' kernel/reboot.c
        sed -i '/int ret = 0;/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n#endif' kernel/reboot.c
        ;;

    ## 6.patch: kernel/sys.c
    kernel/sys.c)
        echo "正在修改: $i"
        # 有些内核 reboot 实现在 sys.c
        sed -i '/static DEFINE_MUTEX(reboot_mutex);/a\#ifdef CONFIG_KSU_MANUAL_HOOK\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n#endif' kernel/sys.c
        sed -i '/SYSCALL_DEFINE4(reboot/a\#ifdef CONFIG_KSU_MANUAL_HOOK\n       ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n#endif' kernel/sys.c
        ;;

    esac
done

echo "KSU Manual Hook Patching 完成。"