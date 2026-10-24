# gbOS86 quiet boot: sourced by stage0 through gbos.cfg, so it runs as soon as the gbos volume is mounted.
# The kernel's built-in command line has loglevel=8 ignore_loglevel, so every kernel and init message (thousands of SELinux
# audit lines) is drawn on the screen until the boot animation, and again at shutdown; drawing them on the framebuffer
# console also slows the boot. From here on only emergencies (a panic) reach the screen. Nothing is lost: every message
# still goes to logs/boot-N/kmsg.log. QUIET_BOOT=0 in gbos.cfg keeps the text. The text before this point (the first
# seconds, while the kernel finds the drive) comes from the built-in command line and stays.
# The installer talks on the screen itself and needs the cursor, so it is left alone.
if [ "${QUIET_BOOT:-1}" != 0 ] && [ "$SELMODE" != install ] && ! { [ "$MODE" = install ] && [ "$FROM" = stick ]; }; then
  echo 0 > /sys/module/printk/parameters/ignore_loglevel
  echo 1 > /proc/sys/kernel/printk
  echo 0 > /sys/class/graphics/fbcon/cursor_blink 2>/dev/null
  printf '\033[?25l\033[2J\033[H' > /dev/tty1
  # stage0's rescue shell (a failure, or SHELL_AT): bring the text back first, with the messages that led there.
  shell() {
    echo 1 > /sys/module/printk/parameters/ignore_loglevel; echo 8 > /proc/sys/kernel/printk
    printf '\033[?25h' > /dev/tty1; dmesg | tail -n 30 > /dev/tty1
    log "DROPPING TO SHELL ($1). type 'exit' to continue boot."
    setsid cttyhack sh </dev/tty1 >/dev/tty1 2>&1
  }
fi
