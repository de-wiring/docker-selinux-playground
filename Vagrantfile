# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = 'TFDuesing/Fedora-21'
  config.vm.box_check_update = false
  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.customize ["modifyvm", :id, "--memory", "384"]
  end

  config.vm.network "forwarded_port", guest: 9090, host: 46100
  config.vm.network "forwarded_port", guest: 2375, host: 46101

  # master
  config.vm.define 'fedoraselinux', primary: true do |m|
	  m.vm.provision 'shell', path: 'provision.d/01_os.sh'
	  m.vm.provision 'shell', path: 'provision.d/05_selinux.sh'
	  m.vm.provision 'shell', path: 'provision.d/10_docker.sh'
  end

end

