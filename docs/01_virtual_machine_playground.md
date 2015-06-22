# Part 1: Virtual Machine overview

This repository includes a [Vagrantfile](https://raw.githubusercontent.com/aschmidt75/docker-selinux-playground/master/Vagrantfile) that
uses a Fedora21 Box from [TFDuesing/Fedora-21](https://vagrantcloud.com/TFDuesing/boxes/Fedora-21).

The provisioning section has been put into scripts under `provision.d/`, they
do a yum update, install selinux components and tools and install docker.

Starting up the vm, we can take a look at the status of selinux:

```bash
$ vagrant ssh
$ sudo -i
# sestatus
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Max kernel policy version:      29
```

So, selinux is enable and the current policy is `targeted`, and it's in `enforcing`
mode:

```bash
# getenforce
Enforcing
```

This means that selinux is "turned on" and ready to protect the system. We're
able to look at things such as users, processes, files etc. using the `-Z` option
on many commands, i.e. looking at the current user reveals:


```bash
# id -Z
unconfined_u:unconfined_r:unconfined_t:SystemLow-SystemHigh
```

Here, `Unconfined` means (more or less) that i (being user root) have full access and
selinux is not going to limit my actions. That of course changes when processes
are started. Lets look at the docker daemon using `-Z`:


```bash
# ps -f -p $(cat /var/run/docker.pid) -Z
LABEL                           UID        PID  PPID  C STIME TTY          TIME CMD
system_u:system_r:docker_t:SystemLow root  363     1  0 16:27 ?        00:00:09 /usr/bin/docker -d --selinux-enabled
```

It's running in the `docker_t` domain, role `system_r`. So that process is confined in a way
that is described by the selinux policy for Docker. Note also the docker switch `--selinux-enabled`,
this is set automatically in `/etc/sysconfig/docker`.

On systemd with a custom docker installation, this is not necessarily the case. If not, take a look at
`/usr/lib/systemd/system/docker.service` an add `--selinux-enabled` to the ExecStart= line if necessary,
reload and restart service:

```bash
~# grep ^ExecStart /usr/lib/systemd/system/docker.service
ExecStart=/usr/bin/docker -d -H fd:// --selinux-enabled
~# systemctl daemon-reload
~# systemctl restart docker.service
```

`ls` understands `-Z` as well, lets look at the docker socket:

```bash
# ls -alZ /var/run/docker.sock
srw-rw----. root root system_u:object_r:docker_var_run_t:SystemLow /var/run/docker.sock
```

It's of type `docker_var_run_t`, so it's treated in a special way by selinux.

To find out more on docker_t, we can use `seinfo`:

```bash
# seinfo -tdocker_t -x
 docker_t
  can_change_process_identity
  fixed_disk_raw_write
  fixed_disk_raw_read
  kernel_system_state_reader
  syslog_client_type
  corenet_unlabeled_type
  can_change_process_role
  netlabel_peer_type
  daemon
  nsswitch_domain
  domain
```

We can see that this type is able to i.e. "can_change_process_identity" and "can_change_process_role".
`seinfo` offers a lot more parameters to show various things within the active policy.

Lets start a container and look around. The VM provision script automatically pulls a Fedora21 image
as well as a busybox.

```bash
# docker run -ti fedora:21 /bin/bash
bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c281,c501 1 ? 00:00:00 bash
system_u:system_r:svirt_lxc_net_t:s0:c281,c501 10 ? 00:00:00 ps
```

The container bash process is also confined, but in another domain (`svirt_lxc_net_t`). We'll explore
the rest of this label later. For now it's ok to see that selinux is working for our containers.

Some people might be tempted to turn it off altogether when running into sort of PermissionDenied problems,
but we aim to make systems more secure, not less secure. So we stay `setenforce 1`.

Working with and configuring selinux requires some tools to be present, some binaries, some in python, unfortunately
scattered across different packages that are not all named selinx-*, so we have to search a bit.
The [provision script for selinux](https://github.com/aschmidt75/docker-selinux-playground/blob/master/provision.d/05_selinux.sh) installs
those:

```bash
# yum install -y \
attr \
libselinux-python \
mcstrans \
policycoreutils \
policycoreutils-python \
selinux-policy-devel \
selinux-policy-targeted \
selinux-policy-sandbox \
setroubleshoot \
setroubleshoot-server \
setools-console
```

Maybe this would be a bit too much for a production system, but for a playground it's probably ok. Then it puts
selinux into enforcing mode (`setenforce 1`), starts/enables the `mcstransd` daemon for translating category numbers into names.
Finally it git-clones the [selinux-policy](git clone git://git.fedorahosted.org/selinux-policy.git) repository, we need this later
when looking on policy modules.

## More on `-Z`

We've seen the -Z option on ps when looking at the docker daemon process and a container process. It's also available to
netstat:

```bash
# docker run -tdi -p 8080 fedora:21 /bin/bash
748e0d6c49e002e4d73b889749b564b89dce78cdacb8943530be1ef11a307c97

# docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS                     NAMES
748e0d6c49e0        fedora:latest       "/bin/bash"         2 seconds ago       Up 1 seconds        0.0.0.0:49154->8080/tcp   suspicious_darwin

# netstat -nltpZ | grep 49154
tcp6       0      0 :::49154                :::*                    LISTEN      3208/docker-proxy    system_u:system_r:docker_t:SystemLow
```

The port forwarding is done outside of the container and handled by the docker daemon, so its security label is `docker_t`.

Now what happens when mounting a volume? 

```bash
# mkdir /container-data
# docker run -ti -v /container-data:/mnt fedora:21 /bin/bash
bash-4.3# cd /mnt
bash-4.3# ls -al
ls: cannot open directory .: Permission denied
```

Meh, what happened? Lets look at the mounted volume with `-Z`:

```bash
# ls -alZ /
(...)
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c90,c644 media
drwxr-xr-x. root root unconfined_u:object_r:default_t:s0 mnt
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c90,c644 opt
(...)
```

Other directories carry the `svirt_sandbox_file_t` label, whereas our /mnt is on `default_t`. The selinux policy make docker start containers with a `svirt_lxc_net_t`
(see with ps -Z), it transitions the container process from docker_t into svirt_lxc_net_t. When a file is created inside, there is some sort of transition into
`svirt_sandbox_file_t`, but not for the one we mounted (because it has been created outside). We'd need to change this on the host level, i.e. using `chcon`:

```bash
# exit    # from container

# chcon -R --type svirt_sandbox_file_t /container-data

# ls -alZ /container-data
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:SystemLow .
dr-xr-xr-x. root root system_u:object_r:root_t:SystemLow ..

# docker run -ti -v /container-data:/mnt fedora:21 /bin/bash
bash-4.3# ls -alZ /mnt/
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c59,c154 ..

bash-4.3# touch /mnt/some_file

bash-4.3# ls -alZ /mnt/
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c59,c154 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0 some_file
```

After changing the context of `/container-data` to `svirt_sandbox_file_t`, we're able to access this directory and put files in there.
They automatically get the same context.

**Note: Starting from docker 1.7.0**, the `-v` argument understands a special parameter suffix, `-z`. Using this, the docker daemon automatically assigns the
right label to the volume being mounted:

```bash
~# rm -fr /container-data/
~# mkdir /container-data
~# ls -alZ /container-data/
drwxr-xr-x. root root unconfined_u:object_r:default_t:SystemLow .
dr-xr-xr-x. root root system_u:object_r:root_t:SystemLow ..

# its default_t

~# docker run -ti -v /container-data:/mnt:z fedora:21 /bin/bash
bash-4.3# cd /mnt
bash-4.3# ls -alZ
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c29,c960 ..
bash-4.3# exit
exit

[root@localhost ~]# ls -alZ /container-data/
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:SystemLow .
dr-xr-xr-x. root root system_u:object_r:root_t:SystemLow ..

# now its svirt_sandbox_file_t
```

Note the last part of the security label, on the host it's a name like `SystemLow`. This is what mcstransd is doing for us, translating category numbers into names.
Inside the container we see the plain categories (i.e. `so:c59,c154`). More about that in Part 2.

Where are all these transitions and types defined? Looking at the git repo we clone, we find some files for docker:

```bash
# ls -al /root/selinux-policy/docker.*
-rw-r--r--. 1 root root  947 13. Mär 12:01 /root/selinux-policy/docker.fc
-rw-r--r--. 1 root root 7655 13. Mär 12:01 /root/selinux-policy/docker.if
-rw-r--r--. 1 root root 8103 13. Mär 12:01 /root/selinux-policy/docker.te
```

as well as the transition from docker_t to svirt_* in `virt.te`. We'll return to policy modules in Part 3.

The [2nd part](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/02_categories.md) shows how to
isolate volume mounts between containers of different tenants.
