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
# echo 's0:c100=CustomerA' >>/etc/selinux/targeted/setrans.conf
# echo 's0:c110=CustomerB' >>/etc/selinux/targeted/setrans.conf
```

They're available immediately:
```bash
# chcat -L
(..)
s0:c100                        CustomerA
s0:c110                        CustomerB
```

We'll create data directories for each customer (to be mounted by docker containers), and assign the categories as well
as the correct domain type for docker containers.

```bash
# mkdir /container-data-customera
# mkdir /container-data-customerb
# chcon --type svirt_sandbox_file_t --range s0:c100 /container-data-customera
# chcon --type svirt_sandbox_file_t --range s0:c110 /container-data-customerb
# ls -alZ / | grep container-data-
drwxr-xr-x. root    root    unconfined_u:object_r:svirt_sandbox_file_t:s0:c100 container-data-customera
drwxr-xr-x. root    root    unconfined_u:object_r:svirt_sandbox_file_t:s0:c110 container-data-customerb
```

Starting a container and mounting a customer directory yields:

```bash
# docker run -ti -v /container-data-customera:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash: cd: /mnt: Permission denied

bash-4.3# ls -alZ / | grep mnt
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100 mnt

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c119,c593 1 ? 00:00:00 bash
system_u:system_r:svirt_lxc_net_t:s0:c119,c593 12 ? 00:00:00 ps
```

The mounted volume has `s0:c100` (as we created), but our container process has `s0:c119,c593`. That does not match well.

### --security-opt

The `--security-opt` switch offers a `label:level` mode where we're able to specify the level and category our container
should have:

```bash
# docker run -ti --security-opt label:level:s0:c100 -v /container-data-customera:/mnt fedora /bin/bash

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c100 1 ?  00:00:00 bash
system_u:system_r:svirt_lxc_net_t:s0:c100 14 ? 00:00:00 ps

bash-4.3# cd /mnt
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c100 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c100 ..

bash-4.3# touch x
bash-4.3# ls -alZ x
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c100 x
```

Now that works! Our container process is now labeled `system_u:system_r:svirt_lxc_net_t:s0:c100`, and we can enter /mnt and
put files there. So our container is a "CustomerA" container.

Lets see what happens if we start a "CustomerB" container with level s0:c110 and access "CustomerA" data:

```bash
# docker run -ti --security-opt label:level:s0:c110 -v /container-data-customera:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash: cd: /mnt: Permission denied
```

Bäm, doesn't work. However, using Category `s0:c110` on `/container-data-customerb` is fine:

```bash
# docker run -ti --security-opt label:level:s0:c110 -v /container-data-customerb:/mnt fedora /bin/bash
bash-4.3# cd /mnt
bash-4.3# touch y
bash-4.3# ls -alZ
drwxr-xr-x. root root unconfined_u:object_r:svirt_sandbox_file_t:s0:c110 .
drwxr-xr-x. root root system_u:object_r:svirt_sandbox_file_t:s0:c110 ..
-rw-r--r--. root root system_u:object_r:svirt_sandbox_file_t:s0:c110 y
```

This could also be done by defining regular linux users and assigning access to the directories. A drawback of doing so is
that the container would need to be run as a particular user (--user). So that user would have to be defined
inside the container (useradd ...) and the application needs to support this. But mostly applications define
their own system-like users (httpd, tomcat, ...), which breaks with a one-distinct-user-per-tenant approach, or
at least make it more complicated.

Selinux categories can be applied without defining something in the container, and be combined with linux users
inside:

```bash
# docker run -ti --user 1494 --security-opt label:level:s0:c110 -v /container-data-customerb:/mnt fedora /bin/bash

bash-4.3$ id
uid=1494 gid=0(root)

bash-4.3$ ps -efZ
LABEL                           UID        PID  PPID  C STIME TTY          TIME CMD
system_u:system_r:svirt_lxc_net_t:s0:c110 1494 1   0  0 06:57 ?        00:00:00 /bin/bash
system_u:system_r:svirt_lxc_net_t:s0:c110 1494 11  1  0 06:57 ?        00:00:00 ps -efZ
```

UID=1494, Category=s0:c110. What happens if we access our mounted volume?

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

Maybe our selinux categories are fine, but on a standard linux DAC level, this directory is
accessible to all, but writeable to root only. So we'd have to assign the regular
linux access rights accordingly, i.e. by making it group-writable to root group (or some other
  group defined inside the container).

```bash
# chmod -R g+w /container-data-customerb
# docker run -ti --user 1494 --security-opt label:level:s0:c110 -v /container-data-customerb:/mnt fedora /bin/bash
bash-4.3$ touch /mnt/v
bash-4.3$ ls -alZ /mnt/v
-rw-r--r--. 1494 root system_u:object_r:svirt_sandbox_file_t:s0:c110 /mnt/v
```

On the host level however, all of this does not buy us much:

```bash
# su - vagrant
$ cat /container-data-customera/x
```

Gives no error. `id -Z` shows that the vagrant user is "unconfined" and its level/category is "SystemLow-SystemHigh",
which is s0-s0:c0.c1023 and "beats" s0:c100. We're left with standard linux access rights here unless we define additional selinux users etc. 

But for a container-only scenario this should be fine. Confined containers can be launched for individual customers,
with selinux making sure that even in case of a mistake (i.e. mounting the wrong volume) data is isolated per customer.

Seems like this is a valid use case for `--security-opt label:level`.
