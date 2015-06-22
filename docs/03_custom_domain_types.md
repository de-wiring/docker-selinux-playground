# Part 3: Creating custom selinux types for containers

Docker's documentation pages and blog posts state that selinux domain types can easily be set
using `label:type` as `--security-opt`. Examples of such types could be i.e. an `apache_t` for
running a web server or a `svirt_lxc_nonet_t`, just like the known `svirt_lxc_net_t` but without
networking. But of course policy modules for these types are not shipped, so they need to be written. 
Time to give it a try!

SELinux documentation says that it is not a good practise to copy module source code from an existing domain, because one might copy
privileges that are never needed by the new domain and thus might end up with an insecure system. The regular
way books and how-tos describe is to put a system into permissive mode, run the application, use
tools such as audit2allow to extract permission from the audit log and construct a policy this way.

But as i have no experiences with writing custom policy code and at the same time just wanted to test
wether i can swap one domain type by another, i chose to go with duplication as a first try.

My first goal was to have a custom domain type for running docker containers that is as close as
possible to the existing `svirt_lxc_net_t`. At a later stage i hope to just eliminate elements from
the module so that the new domain has less privileges, not more.

Needless to say all of this is just for learning purposes and not ending up with a super hardened
production-ready policy module.

I started at the cloned git repo in `/root/selinux-policy`. Fedora puts code in branches for each release,
so:

```bash
# cd /root/selinux-policy
# git checkout rawhide-contrib
# grep -l svirt_lxc_net_t *
virt.te
# ls -al virt*
-rw-r--r--. 1 root root  5798 23. Mär 14:57 virt.fc
-rw-r--r--. 1 root root 27906 23. Mär 14:57 virt.if
-rw-r--r--. 1 root root 51458 23. Mär 14:57 virt.te
```

`virt.fc` defines file contexts to automatically put labels on files with defined patterns.
`virt.if` contains interface definitons, and `virt.te` is the module for type enforcement.

Looking at the `virt.te` file, we can find occurrences of `svirt_lxc_net_t`, i.e.

```bash
(...)
optional_policy(`
        docker_manage_lib_files(svirt_lxc_net_t)
        docker_manage_lib_dirs(svirt_lxc_net_t)
        docker_read_share_files(svirt_sandbox_domain)
        docker_exec_lib(svirt_sandbox_domain)
        docker_lib_filetrans(svirt_sandbox_domain,svirt_sandbox_file_t, sock_file)
        docker_use_ptys(svirt_sandbox_domain)
')
(...)
```

So that docker (running confined as `docker_t`) is able to transition to i.e. some
sandboxed domains and when dealing with files, do this using the `svirt_sandbox_file_t` type.

Later parts:

```bash
########################################
#
# svirt_lxc_net_t local policy
#
(...)
```

This seems to be the block where `svirt_lxc_net_t` is defined, looks like a good candidate.
I created a temporary directory to put the new module into:

```bash
# cd /vagrant
# mkdir custom_type
# cd custom_type
# vi container.te
```

The policy module start with a policy_module definition, i just name it after the file:

```bash
policy_module(container, 1.0);
```

Then follows the code from `virt.te`, but changing the identifier `svirt_lxc_net_t` to, lets say, `mycontainer_t`. I know this name says next to nothing, but for a first test it should
be ok.

Since the module uses other types and attributes, i declared them at the beginning:

```bash
policy_module(container, 1.0);

gen_require(`
  type svirt_sandbox_file_t;
  type virt_lxc_var_run_t;
  attribute sandbox_net_domain;
')

########################################
#
# mycontainer_t local policy
#
virt_sandbox_domain_template(mycontainer)
typeattribute mycontainer_t sandbox_net_domain;
(...)
```

.fc and .if files are optional, so let's compile it. The policy code of package `selinux-policy-devel` includes a Makefile:

```bash
# make -f /usr/share/selinux/devel/Makefile
Compiling targeted container module
/usr/bin/checkmodule:  loading policy configuration from tmp/container.tmp
/usr/bin/checkmodule:  policy configuration loaded
/usr/bin/checkmodule:  writing binary representation (version 17) to tmp/container.mod
Creating targeted container.pp policy package
rm tmp/container.mod tmp/container.mod.fc

# ls -al
insgesamt 80
drwxr-xr-x. 1 vagrant vagrant   238 23. Mär 15:33 .
drwxr-xr-x. 1 vagrant vagrant   408 23. Mär 15:14 ..
-rw-r--r--. 1 vagrant vagrant     0 23. Mär 15:26 container.fc
-rw-r--r--. 1 vagrant vagrant    23 23. Mär 15:26 container.if
-rw-r--r--. 1 vagrant vagrant 71056 23. Mär 15:33 container.pp
-rw-r--r--. 1 vagrant vagrant  1862 23. Mär 15:33 container.te
drwxr-xr-x. 1 vagrant vagrant   170 23. Mär 15:33 tmp
```

Some empty and temporary files have been created, and a `container.pp`. This .pp file
can be loaded by selinux as a module

```bash
# semodule -v -i container.pp
Attempting to install module 'container.pp':
Ok: return value of 0.
Committing changes:
Ok: transaction number 0.
```

That took a couple of seconds, but is has been installed:

```bash
# semodule -l | grep container
container	1.0
# seinfo -tmycontainer_t
   mycontainer_t
```

Lets try and start a container with this type:

```bash
# docker run -ti --security-opt label:type:mycontainer_t fedora:21 /bin/bash

bash-4.3# ps -Z
LABEL                             PID TTY          TIME CMD
system_u:system_r:mycontainer_t:s0:c534,c957 1 ? 00:00:00 bash
system_u:system_r:mycontainer_t:s0:c534,c957 10 ? 00:00:00 ps
```

That worked. Our container is confined in a new domain `mycontainer_t`, and thats different
from other containers, they're running in `svirt_lxc_net_t`. Actually, it does not
make any difference because i plain copied the code, but it may serve as a base for
developing own types.

Let's try to tweak the policy a bit. I copy mycontainer.te to a new directory and rename it
to nonet.te. This is going to be a policy for a container which shall not be able to doing any
networking at all.

Editing the .te policy file, i search/replace all `mycontainer` with `mycontainer_nonet`, and
name the policy module `nonet_container`. The original policy contained a line

`typeattribute mycontainer_nonet_t sandbox_net_domain;`

and that sandbox_net_domain did allow (probably among other things..) network-actions to the domain.
We comment that out, so the start of our .te files looks like:

```bash
policy_module(nonent_container, 1.0);

(...)

virt_sandbox_domain_template(mycontainer_nonet)

#typeattribute mycontainer_nonet_t sandbox_net_domain;

allow mycontainer_nonet_t self:capability { kill setuid setgid
(...)
```

and so on. Compiling and installing the policy:


```bash
# make -f /usr/share/selinux/devel/Makefile
Compiling targeted nonet module
/usr/bin/checkmodule:  loading policy configuration from tmp/nonet.tmp
/usr/bin/checkmodule:  policy configuration loaded
/usr/bin/checkmodule:  writing binary representation (version 17) to tmp/nonet.mod
Creating targeted nonet.pp policy package
rm tmp/nonet.mod tmp/nonet.mod.fc

# semodule -i nonet.pp
```

A plain fedora:21 image does not contain all network-related tools, so we install 
them (before disabling the network :)

```bash
# docker run -ti fedora:21 /bin/bash
# yum install net-tools nc6 iputils
# <CTRL-P> + <CTRL-Q>
# docker commit 4edbb116d7bb fedora-nettest
```

Now lets start a `fedora-nettest` image with our `mycontainer_nonet_t` type:

```bash
# docker run -ti --security-opt label:type:mycontainer_nonet_t fedora-nettest /bin/bash

bash-4.3# curl google.de
curl: (7) Couldn't connect to server

bash-4.3# ifconfig -a
Warning: cannot open /proc/net/dev (Permission denied). Limited output.
Warning: cannot open /proc/net/dev (Permission denied). Limited output.
eth0: flags=67<UP,BROADCAST,RUNNING>  mtu 1500
        inet 172.17.0.8  netmask 255.255.0.0  broadcast 0.0.0.0
        ether 02:42:ac:11:00:08  txqueuelen 0  (Ethernet)

Warning: cannot open /proc/net/dev (Permission denied). Limited output.
lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        loop  txqueuelen 0  (Local Loopback)

# nc6 -4 -l -s 127.0.0.1 -p 8080
nc6: bind to source 127.0.0.1 8080 failed: Permission denied
nc6: failed to bind to any local addr/port
```

This is fairly limited, even loopback is disabled. Comparing this to the `mycontainer_t` type:

```bash
# docker run -ti --security-opt label:type:mycontainer_t fedora-nettest /bin/bash

bash-4.3# curl google.de
<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
<TITLE>301 Moved</TITLE></HEAD><BODY>
<H1>301 Moved</H1>
The document has moved
<A HREF="http://www.google.de/">here</A>.
</BODY></HTML>

bash-4.3# ifconfig -a
eth0: flags=67<UP,BROADCAST,RUNNING>  mtu 1500
        inet 172.17.0.9  netmask 255.255.0.0  broadcast 0.0.0.0
        inet6 fe80::42:acff:fe11:9  prefixlen 64  scopeid 0x20<link>
        ether 02:42:ac:11:00:09  txqueuelen 0  (Ethernet)
        RX packets 19  bytes 1943 (1.8 KiB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 20  bytes 1425 (1.3 KiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        inet6 ::1  prefixlen 128  scopeid 0x10<host>
        loop  txqueuelen 0  (Local Loopback)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

bash-4.3# nc6 -4 -l -s 127.0.0.1 -p 8080

^C
```

Here we don't have any networking problems. For now we have an selinux domain type for non-network related computing, i.e.
batch processing from volumes or similar.

## Summary

These first steps look easy but it definitely took me some time to dive into the structure of policy modules.
Writing a custom policy from scratch is probably not that easy, but i hope that some more policy examples for docker will be
available in the future. 

If you have the option to run docker containers in an selinux-confined way, give it a try. This should really
improve the security of your system. Even if a container-application is hacked and an attacker is able to fallback into a shell,
this shell process will be confined in the container's domain type.








