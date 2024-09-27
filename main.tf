provider "null" {}

provider "template" {}

resource "null_resource" "install_k3s_master" {
  connection {
    type     = "ssh"
    host     = "192.168.0.121"
    user     = "master"
    password = "raspberry"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo curl -sfL https://get.k3s.io | sh -",
      "sudo chmod 644 /etc/rancher/k3s/k3s.yaml",
      "sudo systemctl restart k3s"
    ]
  }
}

resource "null_resource" "get_k3s_token" {
  depends_on = [null_resource.install_k3s_master]

  connection {
    type     = "ssh"
    host     = "192.168.0.121"
    user     = "master"
    password = "raspberry"
  }

  provisioner "local-exec" {
    command = "sshpass -p 'raspberry' ssh -o StrictHostKeyChecking=no master@192.168.0.121 'sudo cat /var/lib/rancher/k3s/server/node-token' > k3s_token.txt"
  }
}

resource "null_resource" "install_k3s_worker" {
  depends_on = [null_resource.get_k3s_token]

  connection {
    type     = "ssh"
    host     = "192.168.0.120"
    user     = "worker"
    password = "raspberry"
  }

  provisioner "file" {
    source      = "k3s_token.txt"
    destination = "/tmp/k3s_token.txt"
  }

  provisioner "remote-exec" {
    inline = [
      "K3S_TOKEN=$(cat /tmp/k3s_token.txt)",
      "sudo curl -sfL https://get.k3s.io | K3S_URL=https://192.168.0.121:6443 K3S_TOKEN=$K3S_TOKEN sh -",
      "sudo systemctl restart k3s-agent"
    ]
  }
}

resource "null_resource" "install_helm" {
  depends_on = [null_resource.install_k3s_master]

  connection {
    type     = "ssh"
    host     = "192.168.0.121"
    user     = "master"
    password = "raspberry"
  }

  provisioner "remote-exec" {
    inline = [
      "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",
      "helm repo add grafana https://grafana.github.io/helm-charts",
      "helm repo update"
    ]
  }
}

resource "null_resource" "install_prometheus" {
  depends_on = [null_resource.install_helm]

  connection {
    type     = "ssh"
    host     = "192.168.0.121"
    user     = "master"
    password = "raspberry"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 644 /etc/rancher/k3s/k3s.yaml",
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      "helm install prometheus prometheus-community/prometheus --set server.service.type=NodePort --set alertmanager.service.type=NodePort --set pushgateway.service.type=NodePort"
    ]
  }
}

resource "null_resource" "install_grafana" {
  depends_on = [null_resource.install_helm]

  connection {
    type     = "ssh"
    host     = "192.168.0.121"
    user     = "master"
    password = "raspberry"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 777 /etc/rancher/k3s/k3s.yaml",
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      "helm install grafana grafana/grafana --set service.type=NodePort"
    ]
  }
}

resource "null_resource" "verify_k3s_cluster" {
  depends_on = [null_resource.install_k3s_worker, null_resource.install_prometheus, null_resource.install_grafana]

  provisioner "local-exec" {
    command = "sshpass -p 'raspberry' ssh -o StrictHostKeyChecking=no master@192.168.0.121 'sudo kubectl get nodes'"
  }
}
