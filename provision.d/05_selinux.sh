
yum install -y \
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

setenforce 1

systemctl enable mcstransd
systemctl start mcstransd

#
cd /root
git clone git://git.fedorahosted.org/selinux-policy.git
