# Part 2: Setting MCS categories to isolate containers with mounted volumes

My first thoughts on selinux for docker were "how to isolate containers for multiple tenants".
Ok, containers are quite isolated, but what happens in a case of misconfiguration? A Container
of - let's say - CustomerA should never be able to communicate with containers of CustomerB.

This applies to both networking and file access. The first can be handled by isolating networks
on layer 2, and there are already solutions on the way (socketplane, weave, your-custom-layer2-vlan-wiring-stuff etc).

The latter case - File Access on mounted volumes - could be solved with selinux and its Multi Category Magic.

Let's look at the category definition on the host level, it's in `/etc/selinux/targeted/setrans.conf`

```bash
# cat /etc/selinux/targeted/setrans.conf
#
# Multi-Category Security translation table for SELinux
#
...
s0=SystemLow
s0-s0:c0.c1023=SystemLow-SystemHigh
s0:c0.c1023=SystemHigh
```

These are the default levels (`s0`) and categories (`cxxx`) for the targeted policy. Only a single level
(s0) is supported, otherwise we would need the MLS policy. But multiple categories are supported and we're free
to edit the file and add categories for two customers:

```bash
# echo 's0:c100.c109=CustomerA' >>/etc/selinux/targeted/setrans.conf
# echo 's0:c110.c119=CustomerB' >>/etc/selinux/targeted/setrans.conf
```

They're available immediately:
```bash
# chcat -L
(..)
s0:c100.c109                   CustomerA
s0:c110.c119                   CustomerB
```

We'll create data directories for each customer (to be mounted by docker containers), and assign the categories as well
as the correct domain type for volumes to be used by docker containers.

```bash
# mkdir /container-data-customera
# mkdir /container-data-customerb
# chcon --type svirt_sandbox_file_t --range s0:c100,c109 /container-data-customera
# chcon --type svirt_sandbox_file_t --range s0:c110,c119 /container-data-customerb
# ls -alZ / | grep container-data-
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100,c109 container-data-customera
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c110,c119 container-data-customerb
```

Starting a container and mounting a customer directory yields:

```bash
# docker run -ti -v /container-data-customera:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash: cd: /mnt: Permission denied

bash-4.3# ls -alZ / | grep mnt
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100,c109 mnt

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c119,c593 1 ? 00:00:00 bash
system_u:system_r:svirt_lxc_net_t:s0:c119,c593 12 ? 00:00:00 ps
```

The mounted volume has `s0:c100,c109` (as we created), but docker assigned `s0:c119,c593` to our container process. That does not match well.

### --security-opt

The `--security-opt` switch offers a `label:level` mode where we're able to specify the level and category our container
should have:

```bash
# docker run -ti --security-opt label:level:s0:c100,c109 -v /container-data-customera:/mnt fedora /bin/bash

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c100,c109 1 ?  00:00:00 bash
system_u:system_r:svirt_lxc_net_t:s0:c100,c109 14 ? 00:00:00 ps

bash-4.3# cd /mnt
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100,c109 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 ..

bash-4.3# touch x
bash-4.3# ls -alZ x
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 x
```

Now that works! Our container process is now labeled `system_u:system_r:svirt_lxc_net_t:s0:c100,c109`, and we can enter /mnt and
put files there. So our container is a "CustomerA" container.

Lets see what happens if we start a "CustomerB" container with level s0:c110 and access "CustomerA" data:

```bash
# docker run -ti --security-opt label:level:s0:c110,c119 -v /container-data-customera:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash: cd: /mnt: Permission denied
```

Bäm, doesn't work. However, using Category `s0:c110,c119` on its CustomerBs `/container-data-customerb` is fine:

```bash
# docker run -ti --security-opt label:level:s0:c110,c119 -v /container-data-customerb:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash-4.3# touch y
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c110,c119 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c110,c119 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c110,c119 y
```

This could also be done by defining regular linux users and assigning access to the directories. A drawback of doing so is
that the container would need to be run as a particular user (--user). So that user would have to be defined
inside the container (useradd ...) and the application needs to support this, i.e. files being writeable/executable by that user.
But mostly applications define their own application-users (httpd, tomcat, ...), which breaks with a one-distinct-user-per-tenant approach, or
at least make it more complicated.

What happens when taking over volumes from other containers with --volumes-from?
Lets create a container `volcont1` with Category of customer a, mounting directory from host:

```bash
# docker run -tdi --security-opt label:level:s0:c100,c109 -v /container-data-customera:/mnt --name volcont1 fedora /bin/bash

bash-4.3# cd /mnt
bash-4.3# echo "123" >x
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100,c109 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 x

# <CTRL-P> + <CTRL-Q>
```

A new container mounting volumes from `volcont1` without proper categories is not able to access it:

```bash
# docker run -ti --volumes-from volcont1 fedora /bin/bash
bash-4.3# cd /mnt
bash: cd: /mnt: Permission denied
bash-4.3# exit
```

A new container with the same category is able to access it:

```bash
# docker run -ti --security-opt label:level:s0:c100,c109 --volumes-from volcont1 fedora /bin/bash
bash-4.3# cd /mnt
bash-4.3# cat x
123
bash-4.3# echo "456" >y
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100,c109 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 x
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 y
bash-4.3# exit
```

Unfortunately this does not work out well when using a volume created by docker daemon, i.e. `-v /data`. Docker creates
a directory on the host but it does not assign the MCS category to it. Inside a container we're not allowed to change
its category, probably because its the mount point we're trying to change:

```bash
# docker run -tdi --security-opt label:level:s0:c100,c109 -v /data --name volcont1 fedora /bin/bash
c28cfbfc35bf459bbb5266de5f6fd220cf90ef51c31dff088102e9a8487841d6

# docker attach volcont1
bash-4.3# cd /data
bash-4.3# ls -alZ
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 ..

bash-4.3# chcon -R --range s0:c100,c109 .
chcon: failed to change context of '.' to 'system_u:object_r:svirt_sandbox_file_t:s0:c100,c109': Permission denied

bash-4.3# touch x
bash-4.3# ls -alZ
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100,c109 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0 x
```

New files created in the container will have the security label of the parent directory, and that's not what we want.
Additionally we're not allowed to `chcon` our own files.

What happens in Privileged containers?

```bash
# docker run -ti --privileged -v /container-data-customerb:/mnt fedora /bin/bash

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:docker_t:s0       1 ?        00:00:00 bash
system_u:system_r:docker_t:s0       9 ?        00:00:00 ps

bash-4.3# cd /mnt
bash-4.3# ls -al
total 8
drwxrwxr-x.  2 root root 4096 Mar 20 12:55 .
drwxr-xr-x. 18 root root 4096 Mar 20 12:56 ..
-rw-r--r--.  1 1494 root    0 Mar 20 12:55 v
-rw-rw-r--.  1 root root    0 Mar 20 12:52 y
bash-4.3# rm y
```

The ps output shows that a privileged container has a `s0` sensitivity and is in the `docker_t` domain (not in `svirt_lxc_net_t`). The policy for this type seems to allow access.

Selinux categories can be applied without defining something in the container, and be combined with linux users
inside:

```bash
# docker run -ti --user 1494 --security-opt label:level:s0:c110,c119 -v /container-data-customerb:/mnt fedora /bin/bash

bash-4.3$ id
uid=1494 gid=0(root)

bash-4.3$ $ ps -efZ
LABEL                           UID        PID  PPID  C STIME TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c110,c119 1494 1 0  0 12:54 ?     00:00:00 /bin/bash
system_u:system_r:svirt_lxc_net_t:s0:c110,c119 1494 10 1  0 12:54 ?    00:00:00 ps -efZ
```

UID=1494, Category=s0:c110,c119. What happens if we access our mounted volume?

```bash
# bash-4.3$ cd /mnt
bash-4.3$ touch v
touch: cannot touch 'v': Permission denied

bash-4.3$ ls -al /mnt
total 8
drwxr-xr-x.  2 root root 4096 Mar 20 06:51 .
drwxr-xr-x. 18 root root 4096 Mar 20 06:57 ..
-rw-r--r--.  1 root root    0 Mar 20 06:51 y
```

Probably our selinux categories are fine, but on a regular linux DAC level, this directory is
accessible to all, but writeable to root only. So we'd have to assign the regular
linux access rights accordingly, i.e. by making it group-writable to root group (or some other
  group defined inside the container).

```bash
# chmod -R g+w /container-data-customerb
# docker run -ti --user 1494 --security-opt label:level:s0:c110,c119 -v /container-data-customerb:/mnt fedora /bin/bash
bash-4.3$ touch /mnt/v
bash-4.3$ ls -alZ /mnt/v
-rw-r--r--. 1494 root system_u:object_r:svirt_sandbox_file_t:s0:c110,c119 /mnt/v
```

On the host level however, all of this does not buy us much:

```bash
# su - vagrant
$ cat /container-data-customera/x
```

Gives no error. `id -Z` shows that the vagrant user is "unconfined" and its level/category is "SystemLow-SystemHigh",
which is s0-s0:c0.c1023 and "beats" s0:c100,c109. We're left with standard linux access rights here unless we define additional selinux users etc.

But in a container-only scenario this should be fine. Confined containers can be launched for individual customers,
with selinux making sure that even in case of a mistake (i.e. mounting the wrong volume) data is isolated per customer.

Seems like isolating tenant data is a valid use case for `--security-opt label:level`.

The [3rd part](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/03_custom_domain_types.md) shows how to create
custom domain types for containers.
