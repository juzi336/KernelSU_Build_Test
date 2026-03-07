#!/bin/bash

patch_files=(
fs/exec.c
fs/open.c
fs/stat.c
kernel/reboot.c
)

for i in "${patch_files[@]}"; do

if grep -q "ksu_handle_" "$i"; then
    echo "Warning: $i already contains KernelSU manual hook"
    continue
fi

case $i in

# fs/exec.c
fs/exec.c)
    sed -i '/static int do_execveat_common/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
attribute((hot))
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
void *argv, void *envp, int *flags);
#endif
' fs/exec.c

    sed -i '/return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
#endif
' fs/exec.c
;;

# fs/open.c
fs/open.c)
    sed -i '/SYSCALL_DEFINE3(faccessat/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
attribute((hot))
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
int *mode, int *flags);
#endif
' fs/open.c

    sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*filename, int, mode)/a\

#ifdef CONFIG_KSU_MANUAL_HOOK
ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
#endif
' fs/open.c
;;

# fs/stat.c
fs/stat.c)
    sed -i '/SYSCALL_DEFINE4(newfstatat/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
attribute((hot))
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,
int *flags);
extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);
#endif
' fs/stat.c

    sed -i '/struct kstat stat;/a\

#ifdef CONFIG_KSU_MANUAL_HOOK
ksu_handle_stat(&dfd, &filename, &flag);
#endif
' fs/stat.c

    sed -i '/return error;/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
ksu_handle_newfstat_ret(&fd, &statbuf);
#endif
' fs/stat.c
;;

# kernel/reboot.c
kernel/reboot.c)
    sed -i '/SYSCALL_DEFINE4(reboot/i\

#ifdef CONFIG_KSU_MANUAL_HOOK
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);
#endif
' kernel/reboot.c

    sed -i '/int ret = 0;/a\

#ifdef CONFIG_KSU_MANUAL_HOOK
ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
#endif
' kernel/reboot.c
;;

esac

done

echo "KernelSU Manual Hook patch applied."