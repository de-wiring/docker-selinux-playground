
sudo yum install -y \
	attr \
	libselinux-python \
	mcstrans \
	policycoreutils \
	policycoreutils-python \
	policycoreutils-newrole \
	selinux-policy-devel \
	selinux-policy-targeted \
	selinux-policy-sandbox \
	setroubleshoot \
	setroubleshoot-server \
	setools-console

sudo setenforce 1

sudo systemctl enable mcstransd
sudo systemctl start mcstransd

# get us the policy source code
cd /root
sudo git clone git://git.fedorahosted.org/selinux-policy.git

# make ssh/pam more verbose when logging in
sudo sed -i 's/^\(session.*required.*pam_selinux.so.*\)$/\1 verbose debug/g' /etc/pam.d/sshd

