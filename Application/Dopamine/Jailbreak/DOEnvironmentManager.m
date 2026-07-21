
- (void)respring
{
    [self runAsRoot:^{
        __block int pid = 0;
        __block int r = 0;
        [self runUnsandboxed:^{
            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/sbreload\"), NULL);
            if (r == 0) {
                kill(pid, SIGCONT);
            }
        }];
        if (r == 0) {
            if (cmd_wait_for_exit(pid) != 0) {
                // Fallback
                [self runUnsandboxed:^{
                    killall(\"/usr/libexec/backboardd\", SIGTERM);
                }];
            }
        }
    }];
}

- (void)semiReboot
{
    [self runAsRoot:^{
        __block int pid = 0;
        __block int r = 0;
        [self runUnsandboxed:^{
            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/killall\"), \"-9\", \"backboardd\", NULL);
            if (r == 0) kill(pid, SIGCONT);

            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/killall\"), \"-9\", \"mediaserverd\", NULL);
            if (r == 0) kill(pid, SIGCONT);

            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/killall\"), \"-9\", \"installd\", NULL);
            if (r == 0) kill(pid, SIGCONT);

            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/killall\"), \"-9\", \"userd\", NULL);
            if (r == 0) kill(pid, SIGCONT);

            r = exec_cmd_suspended(&pid, JBROOT_PATH(\"/usr/bin/killall\"), \"-9\", \"networkd\", NULL);
            if (r == 0) kill(pid, SIGCONT);
        }];
        if (r == 0) {
            cmd_wait_for_exit(pid);
        }
    }];
}

- (void)reboot
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            reboot3(0x8000000000000000, 0);
        }];
    }];
}

@end