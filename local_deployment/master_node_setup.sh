#!/bin/bash
set -u

export DOCKER_IMAGE=kaldi-speechlab
export KUBE_NAME=kaldi-feature-test

cat <<EOF

KALDI SPEECH RECOGNITION SYSTEM deployed on Kubernetes
###################################################################
Setting up the master node for deployment
###################################################################

EOF

echo -e '\033[0;32mUpdating system software...\n\033[m'
sleep 1

sudo apt update && sudo apt upgrade -y

echo -e '\033[0;32mInstalling Docker...\n\033[m'

sudo apt install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io -y

# sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker

echo -e '\033[0;32mInstalling Kubernetes...\n\033[m'

sudo apt install -y kubelet kubeadm kubectl -y

echo -e '\033[0;32mInitializing Kubernetes Cluster...\n\033[m'
echo 'this process may take a while, please wait patiently \n'
sleep 1

sudo kubeadm init --pod-network-cidr=10.244.0.0/16 > kube_details.txt
echo 'Kubernetes cluster is successfully set up. \n'

echo -e '\033[0;32mConfiguring Kubernetes Cluster...\n\033[m'
sleep 1

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# install flannel CNI
# Flannel is used as the network overlay, for nodes in the cluster to communicate with each other
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

echo -e '\033[0;31mBuilding custom SpeechLab Docker image...\n\033[m'
sleep 1

CURRENT_DIRECTORY=$(pwd)

sudo cp ~/.kube/config ../docker/secret/
sleep 1
docker build -t $DOCKER_IMAGE ../docker/

echo -e '\033[0;31mSetting up local Docker container registry on current node...\n\033[m'
echo 'All containers in the cluster will pull the Docker image from the current container registry. \n'
sleep 1

# Local Docker registry is hosted on this machine at port 5000
docker run -d -p 5000:5000 --name registry registry:2

# Tag custom Docker image to push to local registry
docker image tag $DOCKER_IMAGE localhost:5000/$DOCKER_IMAGE

# Push custom Docker image to this registry
docker push localhost:5000/$DOCKER_IMAGE

echo -e '\033[0;31mInitialising Kaldi Speech Recognition System...\n\033[m'
sudo ./local_deploy.sh

# installing tiller, part of helm installation
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller

kubectl apply -f secret/run_kubernetes_secret.yaml

helm install --name $KUBE_NAME --namespace $NAMESPACE ../docker/helm/kaldi-feature-test/
echo -e '\033[0;31mCongratulations, the Kubernetes cluster is set up now!\n\033[m'
echo -e 'you may now join other nodes to this Kubernetes cluster by running this command - \033[0;32msudo kubeadm join [your unique string from the kubeadm init command]\033[m \n'
echo 'you can find the unique string from \033[0;32mkube_details.txt\033[m \n'

exit 0