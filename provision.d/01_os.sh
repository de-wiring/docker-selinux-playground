
sudo su - -c "echo 'LANG=en_US.UTF-8
LC_MESSAGES=C' >/etc/locale.conf"

sudo localectl set-locale LANG=en_US.UTF-8

sudo yum update -y
sudo yum install -y git net-tools


