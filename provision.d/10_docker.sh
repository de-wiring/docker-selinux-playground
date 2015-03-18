
yum install -y \
	docker-io \
	docker-io-vim 

systemctl enable docker || chkconfig -add docker
systemctl start docker || chkconfig -add docker

docker pull busybox:latest
docker pull fedora:latest

