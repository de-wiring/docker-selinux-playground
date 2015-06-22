
sudo yum install -y \
	docker-io \
	docker-io-vim 

sudo systemctl enable docker || chkconfig -add docker
sudo systemctl start docker || chkconfig -add docker

sudo docker pull busybox:latest
sudo docker pull fedora:21

