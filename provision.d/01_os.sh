

echo 'LANG=en_US.UTF-8
LC_MESSAGES=C' >/etc/locale.conf

localectl set-locale LANG=en_US.UTF-8

yum update -y

yum install -y cockpit git 


