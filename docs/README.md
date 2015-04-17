
# docker-selinux-playground Documentation

An selinux playground for docker containers and the `--security-opt` switch.

Docker has the ability to run on selinux-enabled systems within its own domain,
and furthermore run containers with configurable selinux users, roles, types etc.

This documentation aims to introduce to at least some of the selinux capabilities that
docker offers and how to use them in scenarios. It is in no way a complete description
of what's possible, but at least it might get you acquainted with some concepts.

It is divided in three parts:

* [Moving around the Playgrounds' virtual machine](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/01_virtual_machine_playground.md)
* [Setting MCS categories to isolate containers with mounted volumes](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/02_categories.md)
* [Creating custom selinux types for containers](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/03_custom_domain_types.md)
* [Combining selinux and seccomp on lxc-driver](https://github.com/aschmidt75/docker-selinux-playground/blob/master/docs/04_seccomp.md)

This documentation is NOT intended as an introduction to selinux. Please take
a look at other sources, such as the great [SELinux Coloring Book](https://people.redhat.com/duffy/selinux/selinux-coloring-book_A4-Stapled.pdf)
for a introduction into type enforcment and labelling, and other books on this topic. The [Gentoo Wiki on SELinux](http://wiki.gentoo.org/wiki/SELinux) is a good read, too.
