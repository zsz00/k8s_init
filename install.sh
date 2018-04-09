#!/bin/bash

# KUBE_REPO_PREFIX=registry.cn-hangzhou.aliyuncs.com/google-containers
# KUBE_HYPERKUBE_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/hyperkube-amd64:v1.7.0
# KUBE_DISCOVERY_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/kube-discovery-amd64:1.0
# KUBE_ETCD_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/etcd-amd64:3.0.17

# KUBE_REPO_PREFIX=$KUBE_REPO_PREFIX KUBE_HYPERKUBE_IMAGE=$KUBE_HYPERKUBE_IMAGE KUBE_DISCOVERY_IMAGE=$KUBE_DISCOVERY_IMAGE kubeadm init --ignore-preflight-errors=all --pod-network-cidr="10.244.0.0/16"

set -x

USER=k1 # 用户
GROUP=k1 # 组
FLANELADDR=kube-flannel.yml
KUBECONF=kubeadm.conf # 文件地址, 改成你需要的路径
REGMIRROR=https://5ik0xf97.mirror.aliyuncs.com # docker registry mirror 地址

# you can get the following values from `kubeadm init` output
# these are needed when creating node
MASTERTOKEN=04a31b.8981c3561ffb414f
MASTERIP=192.168.20.25
MASTERPORT=6443 
MASTERHASH=a8bbfb41efc3fafb9bb04658f351f4f7281b5c2941f6861ed870fa75cb5c9452

install_docker() {
  mkdir /etc/docker
  mkdir -p /data/docker
  cat << EOF > /tmp/daemon.json
{
  "registry-mirrors": ["$REGMIRROR"],
  "graph": "/data/docker"
}
EOF

  echo "deb [arch=amd64] https://mirrors.ustc.edu.cn/kubernetes/apt kubernetes-$(lsb_release -cs) main" >> /etc/apt/sources.list
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  #curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  cat docker.gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/$(. /etc/os-release; echo "$ID") \
    $(lsb_release -cs) \
    stable"
  apt-get update && apt-get install -y docker-ce=$(apt-cache madison docker-ce | grep 17.03 | head -1 | awk '{print $3}')
}

add_user_to_docker_group() {
  groupadd docker
#  gpasswd -a $USER docker # ubuntu is the user name
  usermod -aG docker $USER
}

install_kube_commands() {
  cat kube_apt_key.gpg | apt-key add -
  echo "deb [arch=amd64] https://mirrors.ustc.edu.cn/kubernetes/apt kubernetes-$(lsb_release -cs) main" >> /etc/apt/sources.list
  apt-get update && apt-get install -y kubelet=1.9.0-00 kubeadm=1.9.0-00 kubectl=1.9.0-00 --allow-downgrades
}

restart_kubelet() {
  sed -i "s,ExecStart=$,Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.1\"\nExecStart=,g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl restart kubelet
}

enable_kubectl() {
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

# for now, better to download from original registry
apply_flannel() {
  sudo kubectl apply -f $FLANELADDR
}

case "$1" in
  "pre")
    install_docker
    add_user_to_docker_group
    install_kube_commands
    ;;
  "kubernetes-master")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    kubeadm init --config $KUBECONF
    ;;
  "kubernetes-node")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    kubeadm join --token $MASTERTOKEN $MASTERIP:$MASTERPORT --discovery-token-ca-cert-hash sha256:$MASTERHASH
    ;;
  "post")
    if [[ $EUID -ne 0 ]]; then
      echo "do not run as root"
      exit
    fi
    enable_kubectl
    apply_flannel
    ;;
  *)
    echo "huh ????"
    ;;
esac
