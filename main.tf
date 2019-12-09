terraform {
  backend "azurerm" {
    storage_account_name  = "buildserverjenkins"
    container_name        = "tstate"
    key                   = "terraform.tfstate"
  }
}

locals {
  cluster_name               = "aks-${random_integer.random_int.result}"
  agents_resource_group_name = "MC_${var.resource_group_name}_${local.cluster_name}_${azurerm_resource_group.cluster.location}"
}

resource "azurerm_resource_group" "cluster" {
  name     = "${var.resource_group_name}"
  location = "${var.resource_group_location}"
}

# Create a SP for use in the cluster
module "service_principal" {
  source = "service_principal"

  sp_least_privilidge = "${var.sp_least_privilidge}"
  sp_name             = "${local.cluster_name}"
}

# Keep the AKS name (and dns label) somewhat unique
resource "random_integer" "random_int" {
  min = 100
  max = 999
}

resource "azurerm_kubernetes_cluster" "aks" {
  name       = "${local.cluster_name}"
  location   = "${azurerm_resource_group.cluster.location}"
  dns_prefix = "${local.cluster_name}"

  resource_group_name = "${azurerm_resource_group.cluster.name}"
  kubernetes_version  = "1.11.5"

  linux_profile {
    admin_username = "${var.linux_admin_username}"

    ssh_key {
      // If the user hasn't set a key the default will be "user_users_ssh_key", here we check for that and 
      // load the ssh from file if this is the case. 
      key_data = "${var.linux_admin_ssh_publickey}"
    }
  }

  agent_pool_profile {
    name    = "agentpool"
    count   = "${var.node_count}"
    vm_size = "${var.vm_size}"
    os_type = "Linux"
  }

  service_principal {
    client_id     = "${module.service_principal.client_id}"
    client_secret = "${module.service_principal.client_secret}"
  }
}

data "azurerm_resource_group" "agents" {
  name = "${local.agents_resource_group_name}"

  depends_on = [
    "azurerm_kubernetes_cluster.aks",
  ]
}

resource "azurerm_role_assignment" "aks_service_principal_role_agents" {
  count                = "${var.sp_least_privilidge}"
  scope                = "${data.azurerm_resource_group.agents.id}"
  role_definition_name = "${module.service_principal.aks_role_name}"
  principal_id         = "${module.service_principal.sp_id}"

  depends_on = [
    "module.service_principal",
  ]
}

#AKS init for kubernetes resources creation
provider "kubernetes" {
  host = "${azurerm_kubernetes_cluster.aks.kube_config.0.host}"

  client_certificate     = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
}
#Namespaces
resource "kubernetes_namespace" "staging" {
  metadata {
    annotations {
      name = "staging"
    }

    labels {
      mylabel = "staging"
    }

    name = "staging"
  }
}
resource "kubernetes_namespace" "production" {
  metadata {
    annotations {
      name = "production"
    }

    labels {
      mylabel = "production"
    }

    name = "production"
  }
}
resource "kubernetes_namespace" "util" {
  metadata {
    annotations {
      name = "util"
    }

    labels {
      mylabel = "util"
    }

    name = "util"
  }
}
resource "kubernetes_namespace" "releasecandidate" {
  metadata {
    annotations {
      name = "releasecandidate"
    }

    labels {
      mylabel = "releasecandidate"
    }

    name = "releasecandidate"
  }
}
resource "kubernetes_namespace" "newproduction" {
  metadata {
    annotations {
      name = "newproduction"
    }

    labels {
      mylabel = "newproduction"
    }

    name = "newproduction"
  }
}
resource "kubernetes_namespace" "newstaging" {
  metadata {
    annotations {
      name = "newstaging"
    }

    labels {
      mylabel = "newstaging"
    }

    name = "newstaging"
  }
}
#Secrets creation
resource "kubernetes_secret" "docker-hub-registry-key-newstaging" {
  metadata {
    name = "docker-hub-registry-key"
    #namespace = "newstaging"
  }

  data {
    docker-username = "${var.docker_login}"
    docker-password = "${var.docker_password}"
    docker-email = "${var.docker_email}"
  }

  type = "kubernetes.io/docker-registry"
}

provider "k8s" {
  kubeconfig_content = "${azurerm_kubernetes_cluster.aks.kube_config_raw}"
}
## KUBE SYSTEM RESOURCES
resource "k8s_manifest" "Grafana" {
  content = "${file("../../kube-system/influxdb/Grafana.yml")}"
}
resource "k8s_manifest" "GrafanaService" {
  content = "${file("../../kube-system/influxdb/GrafanaService.yml")}"
}
resource "k8s_manifest" "HeapsterDeployment" {
  content = "${file("../../kube-system/influxdb/HeapsterDeployment.yml")}"
}
resource "k8s_manifest" "HeapsterService" {
  content = "${file("../../kube-system/influxdb/HeapsterService.yml")}"
}
resource "k8s_manifest" "HeapsterCRB" {
  content = "${file("../../kube-system/influxdb/HeapsterCRB.yml")}"
}
resource "k8s_manifest" "HeapsterRole" {
  content = "${file("../../kube-system/influxdb/HeapsterRole.yml")}"
}
resource "k8s_manifest" "HeapsterRB" {
  content = "${file("../../kube-system/influxdb/HeapsterRB.yml")}"
}
resource "k8s_manifest" "InfluxDB" {
  content = "${file("../../kube-system/influxdb/InfluxDB.yml")}"
}
resource "k8s_manifest" "InfluxDBService" {
  content = "${file("../../kube-system/influxdb/InfluxDBService.yml")}"
}
resource "k8s_manifest" "GrafanaIngress" {
  content = "${file("../../kube-system/influxdb/Ingress.yml")}"
}
resource "k8s_manifest" "NFSDeployment" {
  content = "${file("../../kube-system/nfs_provisioner/NFSDeployment.yml")}"
}
resource "k8s_manifest" "NFSService" {
  content = "${file("../../kube-system/nfs_provisioner/NFSService.yml")}"
}
resource "k8s_manifest" "NFSStorageClass" {
  content = "${file("../../kube-system/nfs_provisioner/StorageClass.yml")}"
}
resource "k8s_manifest" "NFSClusterRole" {
  content = "${file("../../kube-system/nfs_provisioner/auth/ClusterRole.yml")}"
}
resource "k8s_manifest" "NFSClusterRoleBinding" {
  content = "${file("../../kube-system/nfs_provisioner/auth/ClusterRoleBinding.yml")}"
}
resource "k8s_manifest" "NFSServiceAccount" {
  content = "${file("../../kube-system/nfs_provisioner/auth/ServiceAccount.yml")}"
}

## UTIL resources
# externalDNS
resource "k8s_manifest" "externalDNSClusterRole" {
  content = "${file("../../util/external-dns/externalDNSClusterRole.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "externalDNSCRB" {
  content = "${file("../../util/external-dns/externalDNSCRB.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "externalDNSDeployment" {
  content = "${file("../../util/external-dns/externalDNSDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# hairpin fix
resource "k8s_manifest" "hairpin-fix" {
  content = "${file("../../util/hairpin-fix/hairpin-fix.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# nginx ingress
resource "k8s_manifest" "nginxAuthServiceAccount" {
  content = "${file("../../util/nginx-ingress/AuthServiceAccount.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxAuthClusterRole" {
  content = "${file("../../util/nginx-ingress/AuthClusterRole.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxAuthRole" {
  content = "${file("../../util/nginx-ingress/AuthRole.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxAuthRoleBinding" {
  content = "${file("../../util/nginx-ingress/AuthRoleBinding.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxAuthCRB" {
  content = "${file("../../util/nginx-ingress/AuthCRB.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxConfigMap" {
  content = "${file("../../util/nginx-ingress/ConfigMap.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxDefaultDeployment" {
  content = "${file("../../util/nginx-ingress/DefaultDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxDeployment" {
  content = "${file("../../util/nginx-ingress/Deployment.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxDefaultService" {
  content = "${file("../../util/nginx-ingress/DefaultService.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "nginxService" {
  content = "${file("../../util/nginx-ingress/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# GlusterFS
resource "k8s_manifest" "HeketiServiceAccount" {
  content = "${file("../../util/glusterfs/HeketiServiceAccount.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "HeketiRoleMapping" {
  content = "${file("../../util/glusterfs/HeketiRoleMapping.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "HeketiSecret" {
  content = "${file("../../util/glusterfs/HeketiSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "StorageClass" {
  content = "${file("../../util/glusterfs/StorageClass.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "HeketiDeployment" {
  content = "${file("../../util/glusterfs/HeketiDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "HeketiService" {
  content = "${file("../../util/glusterfs/HeketiService.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "GlusterDaemonSet" {
  content = "${file("../../util/glusterfs/GlusterDaemonSet.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# kube-lego
resource "k8s_manifest" "legoAuthClusterRole" {
  content = "${file("../../util/kube-lego/AuthClusterRole.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "legoAuthCRB" {
  content = "${file("../../util/kube-lego/AuthCRB.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "legoAuthServiceAccount" {
  content = "${file("../../util/kube-lego/AuthServiceAccount.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "legoConfig" {
  content = "${file("../../util/kube-lego/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "legoDeployment" {
  content = "${file("../../util/kube-lego/Deployment.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# UpdateInstructor
resource "k8s_manifest" "UpdateInstructorSecret" {
  content = "${file("../../util/update-instructor/SignatureSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructorConfig" {
  content = "${file("../../util/update-instructor/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructorConfig2" {
  content = "${file("../../util/update-instructor/UpdateInstructorConfig.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructorService" {
  content = "${file("../../util/update-instructor/UpdateInstructorService.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructorService2" {
  content = "${file("../../util/update-instructor/UpdateInstructorService2.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructor" {
  content = "${file("../../util/update-instructor/UpdateInstructor.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateInstructorbe" {
  content = "${file("../../util/update-instructor/UpdateInstructorbe.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# Update Manager
resource "k8s_manifest" "UpdateManagerSSLSecret" {
  content = "${file("../../util/update-manager/SSLSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManagerSecret" {
  content = "${file("../../util/update-manager/Secret.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManagerService" {
  content = "${file("../../util/update-manager/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManagerIngress" {
  content = "${file("../../util/update-manager/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManagerServiceAccount" {
  content = "${file("../../util/update-manager/UpdateManagerServiceAccount.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManagerCRB" {
  content = "${file("../../util/update-manager/UpdateManagerCRB.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "UpdateManager" {
  content = "${file("../../util/update-manager/UpdateManager.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
# Zipkin
resource "k8s_manifest" "ZipkinSSLSecret" {
  content = "${file("../../util/zipkin/ZipkinSSLSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinConfig" {
  content = "${file("../../util/zipkin/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinCuratorConfig" {
  content = "${file("../../util/zipkin/CuratorConfig.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinCuratorJob" {
  content = "${file("../../util/zipkin/CuratorJob.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinElasticsearch" {
  content = "${file("../../util/zipkin/Elasticsearch.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinElasticsearchPVC" {
  content = "${file("../../util/zipkin/ElasticsearchPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinElasticsearchService" {
  content = "${file("../../util/zipkin/ElasticsearchService.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinIngress" {
  content = "${file("../../util/zipkin/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinDependencies" {
  content = "${file("../../util/zipkin/ZipkinDependencies.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinApp" {
  content = "${file("../../util/zipkin/ZipkinApp.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}
resource "k8s_manifest" "ZipkinService" {
  content = "${file("../../util/zipkin/ZipkinService.yml")}"
  depends_on = [
    "kubernetes_namespace.util", ]
}

### STAGING
## Backend
# Secrets
resource "k8s_manifest" "stagingAdminSecret" {
  content = "${file("../../staging/wastecycle-be/AdminSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingHubspotSecret" {
  content = "${file("../../staging/wastecycle-be/HubspotSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingInquiriesSecret" {
  content = "${file("../../staging/wastecycle-be/InquiriesSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingSentrySecret" {
  content = "${file("../../staging/wastecycle-be/SentrySecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingsignatureSecret" {
  content = "${file("../../staging/wastecycle-be/signature_secret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingdatabaseSecret" {
  content = "${file("../../staging/wastecycle-be/database/Secret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Config
resource "k8s_manifest" "stagingConfig" {
  content = "${file("../../staging/wastecycle-be/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Redis
resource "k8s_manifest" "stagingRedis" {
  content = "${file("../../staging/wastecycle-be/Redis.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingRedisPV" {
  content = "${file("../../staging/wastecycle-be/RedisPV.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingRedisService" {
  content = "${file("../../staging/wastecycle-be/RedisService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Postgres
resource "k8s_manifest" "stagingDatabase" {
  content = "${file("../../staging/wastecycle-be/database/Database.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingDatabasePVC" {
  content = "${file("../../staging/wastecycle-be/database/DatabasePVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingDatabaseService" {
  content = "${file("../../staging/wastecycle-be/database/DatabaseService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Kafka Zookeeper
resource "k8s_manifest" "stagingZookeeper" {
  content = "${file("../../staging/wastecycle-be/kafka/Zookeeper.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingZookeeperPVC" {
  content = "${file("../../staging/wastecycle-be/kafka/ZookeeperPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingZookeeperService" {
  content = "${file("../../staging/wastecycle-be/kafka/ZookeeperService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Kafka
resource "k8s_manifest" "stagingKafka" {
  content = "${file("../../staging/wastecycle-be/kafka/Kafka.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingKafkaPVC" {
  content = "${file("../../staging/wastecycle-be/kafka/KafkaPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging",  ]
}
resource "k8s_manifest" "stagingKafkaService" {
  content = "${file("../../staging/wastecycle-be/kafka/KafkaService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingKafkatail" {
  content = "${file("../../staging/wastecycle-be/kafka-tail/Deployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingKafkatailIngress" {
  content = "${file("../../staging/wastecycle-be/kafka-tail/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingKafkatailService" {
  content = "${file("../../staging/wastecycle-be/kafka-tail/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Accounts
resource "k8s_manifest" "stagingAccounts" {
  content = "${file("../../staging/wastecycle-be/AccountsDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingAccountsNumberSagaHandler" {
  content = "${file("../../staging/wastecycle-be/AccountsNumberSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingAccountsVerificationSagaHandler" {
  content = "${file("../../staging/wastecycle-be/AccountsVerificationSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingAccountsService" {
  content = "${file("../../staging/wastecycle-be/AccountsService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Calculator
resource "k8s_manifest" "stagingCalculator" {
  content = "${file("../../staging/wastecycle-be/Calculator.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingCalculatorService" {
  content = "${file("../../staging/wastecycle-be/CalculatorService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Containers
resource "k8s_manifest" "stagingContainers" {
  content = "${file("../../staging/wastecycle-be/Containers.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingContainersService" {
  content = "${file("../../staging/wastecycle-be/ContainersService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
# Gateway
resource "k8s_manifest" "stagingGateway" {
  content = "${file("../../staging/wastecycle-be/Gateway.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingGatewayService" {
  content = "${file("../../staging/wastecycle-be/GatewayService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingGatewayIngress" {
  content = "${file("../../staging/wastecycle-be/GatewayIngress.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingHubspot" {
  content = "${file("../../staging/wastecycle-be/Hubspot.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingIdentityDeployment" {
  content = "${file("../../staging/wastecycle-be/IdentityDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingIdentityService" {
  content = "${file("../../staging/wastecycle-be/IdentityService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingInquiries" {
  content = "${file("../../staging/wastecycle-be/Inquiries.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingInquiriesService" {
  content = "${file("../../staging/wastecycle-be/InquiriesService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingMailCatcher" {
  content = "${file("../../staging/wastecycle-be/MailCatcher.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingMailCatcherIngress" {
  content = "${file("../../staging/wastecycle-be/MailCatcherIngress.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingMailCatcherService" {
  content = "${file("../../staging/wastecycle-be/MailCatcherService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingMailSender" {
  content = "${file("../../staging/wastecycle-be/MailSender.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingMailSenderService" {
  content = "${file("../../staging/wastecycle-be/MailSenderService.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingSagaHandler" {
  content = "${file("../../staging/wastecycle-be/SagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
## FRONTEND
resource "k8s_manifest" "stagingFrontendSecret" {
  content = "${file("../../staging/wastecycle-fe/SSLSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingFrontend" {
  content = "${file("../../staging/wastecycle-fe/wastecycle-fe.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingFrontendService" {
  content = "${file("../../staging/wastecycle-fe/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}
resource "k8s_manifest" "stagingFrontendIngress" {
  content = "${file("../../staging/wastecycle-fe/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.newstaging", ]
}

### RELEASECANDIDATE
## Backend
# Secrets
resource "k8s_manifest" "releasecandidateAdminSecret" {
  content = "${file("../../releasecandidate/wastecycle-be/AdminSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateHubspotSecret" {
  content = "${file("../../releasecandidate/wastecycle-be/HubspotSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateInquiriesSecret" {
  content = "${file("../../releasecandidate/wastecycle-be/InquiriesSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateSentrySecret" {
  content = "${file("../../releasecandidate/wastecycle-be/SentrySecret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidatesignatureSecret" {
  content = "${file("../../releasecandidate/wastecycle-be/signature_secret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidatedatabaseSecret" {
  content = "${file("../../releasecandidate/wastecycle-be/database/Secret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Config
resource "k8s_manifest" "releasecandidateConfig" {
  content = "${file("../../releasecandidate/wastecycle-be/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Redis
resource "k8s_manifest" "releasecandidateRedis" {
  content = "${file("../../releasecandidate/wastecycle-be/Redis.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateRedisPV" {
  content = "${file("../../releasecandidate/wastecycle-be/RedisPV.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateRedisService" {
  content = "${file("../../releasecandidate/wastecycle-be/RedisService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Postgres
resource "k8s_manifest" "releasecandidateDatabase" {
  content = "${file("../../releasecandidate/wastecycle-be/database/Database.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateDatabasePVC" {
  content = "${file("../../releasecandidate/wastecycle-be/database/DatabasePVC.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateDatabaseService" {
  content = "${file("../../releasecandidate/wastecycle-be/database/DatabaseService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Kafka Zookeeper
resource "k8s_manifest" "releasecandidateZookeeper" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/Zookeeper.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateZookeeperPVC" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/ZookeeperPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateZookeeperService" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/ZookeeperService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Kafka
resource "k8s_manifest" "releasecandidateKafka" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/Kafka.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateKafkaPVC" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/KafkaPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate",  ]
}
resource "k8s_manifest" "releasecandidateKafkaService" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka/KafkaService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateKafkatail" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka-tail/Deployment.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateKafkatailIngress" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka-tail/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateKafkatailService" {
  content = "${file("../../releasecandidate/wastecycle-be/kafka-tail/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Accounts
resource "k8s_manifest" "releasecandidateAccounts" {
  content = "${file("../../releasecandidate/wastecycle-be/AccountsDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateAccountsNumberSagaHandler" {
  content = "${file("../../releasecandidate/wastecycle-be/AccountsNumberSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateAccountsVerificationSagaHandler" {
  content = "${file("../../releasecandidate/wastecycle-be/AccountsVerificationSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateAccountsService" {
  content = "${file("../../releasecandidate/wastecycle-be/AccountsService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Calculator
resource "k8s_manifest" "releasecandidateCalculator" {
  content = "${file("../../releasecandidate/wastecycle-be/Calculator.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateCalculatorService" {
  content = "${file("../../releasecandidate/wastecycle-be/CalculatorService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Containers
resource "k8s_manifest" "releasecandidateContainers" {
  content = "${file("../../releasecandidate/wastecycle-be/Containers.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateContainersService" {
  content = "${file("../../releasecandidate/wastecycle-be/ContainersService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
# Gateway
resource "k8s_manifest" "releasecandidateGateway" {
  content = "${file("../../releasecandidate/wastecycle-be/Gateway.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateGatewayService" {
  content = "${file("../../releasecandidate/wastecycle-be/GatewayService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateGatewayIngress" {
  content = "${file("../../releasecandidate/wastecycle-be/GatewayIngress.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateHubspot" {
  content = "${file("../../releasecandidate/wastecycle-be/Hubspot.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateIdentityDeployment" {
  content = "${file("../../releasecandidate/wastecycle-be/IdentityDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateIdentityService" {
  content = "${file("../../releasecandidate/wastecycle-be/IdentityService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateInquiries" {
  content = "${file("../../releasecandidate/wastecycle-be/Inquiries.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateInquiriesService" {
  content = "${file("../../releasecandidate/wastecycle-be/InquiriesService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateMailCatcher" {
  content = "${file("../../releasecandidate/wastecycle-be/MailCatcher.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateMailCatcherIngress" {
  content = "${file("../../releasecandidate/wastecycle-be/MailCatcherIngress.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateMailCatcherService" {
  content = "${file("../../releasecandidate/wastecycle-be/MailCatcherService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateMailSender" {
  content = "${file("../../releasecandidate/wastecycle-be/MailSender.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateMailSenderService" {
  content = "${file("../../releasecandidate/wastecycle-be/MailSenderService.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateSagaHandler" {
  content = "${file("../../releasecandidate/wastecycle-be/SagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
## FRONTEND
resource "k8s_manifest" "releasecandidateFrontendSecret" {
  content = "${file("../../releasecandidate/wastecycle-fe/SSLSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateFrontend" {
  content = "${file("../../releasecandidate/wastecycle-fe/wastecycle-fe.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateFrontendService" {
  content = "${file("../../releasecandidate/wastecycle-fe/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}
resource "k8s_manifest" "releasecandidateFrontendIngress" {
  content = "${file("../../releasecandidate/wastecycle-fe/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.releasecandidate", ]
}

### PRODUCTION
## Backend
# Secrets
resource "k8s_manifest" "productionAdminSecret" {
  content = "${file("../../production/wastecycle-be/AdminSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionHubspotSecret" {
  content = "${file("../../production/wastecycle-be/HubspotSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionInquiriesSecret" {
  content = "${file("../../production/wastecycle-be/InquiriesSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionSentrySecret" {
  content = "${file("../../production/wastecycle-be/SentrySecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionsignatureSecret" {
  content = "${file("../../production/wastecycle-be/signature_secret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productiondatabaseSecret" {
  content = "${file("../../production/wastecycle-be/database/Secret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Config
resource "k8s_manifest" "productionConfig" {
  content = "${file("../../production/wastecycle-be/Config.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}

# Postgres
resource "k8s_manifest" "productionDatabase" {
  content = "${file("../../production/wastecycle-be/database/Database.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionDatabasePVC" {
  content = "${file("../../production/wastecycle-be/database/DatabasePVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionDatabaseService" {
  content = "${file("../../production/wastecycle-be/database/DatabaseService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Kafka Zookeeper
resource "k8s_manifest" "productionZookeeper" {
  content = "${file("../../production/wastecycle-be/kafka/Zookeeper.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionZookeeperPVC" {
  content = "${file("../../production/wastecycle-be/kafka/ZookeeperPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionZookeeperService" {
  content = "${file("../../production/wastecycle-be/kafka/ZookeeperService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Kafka
resource "k8s_manifest" "productionKafka" {
  content = "${file("../../production/wastecycle-be/kafka/Kafka.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionKafkaPVC" {
  content = "${file("../../production/wastecycle-be/kafka/KafkaPVC.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction",  ]
}
resource "k8s_manifest" "productionKafkaService" {
  content = "${file("../../production/wastecycle-be/kafka/KafkaService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionKafkatail" {
  content = "${file("../../production/wastecycle-be/kafka-tail/Deployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionKafkatailIngress" {
  content = "${file("../../production/wastecycle-be/kafka-tail/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionKafkatailService" {
  content = "${file("../../production/wastecycle-be/kafka-tail/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Accounts
resource "k8s_manifest" "productionAccounts" {
  content = "${file("../../production/wastecycle-be/AccountsDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionAccountsNumberSagaHandler" {
  content = "${file("../../production/wastecycle-be/AccountsNumberSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionAccountsVerificationSagaHandler" {
  content = "${file("../../production/wastecycle-be/AccountsVerificationSagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionAccountsService" {
  content = "${file("../../production/wastecycle-be/AccountsService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Calculator
resource "k8s_manifest" "productionCalculator" {
  content = "${file("../../production/wastecycle-be/Calculator.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionCalculatorService" {
  content = "${file("../../production/wastecycle-be/CalculatorService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Containers
resource "k8s_manifest" "productionContainers" {
  content = "${file("../../production/wastecycle-be/Containers.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionContainersService" {
  content = "${file("../../production/wastecycle-be/ContainersService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
# Gateway
resource "k8s_manifest" "productionGateway" {
  content = "${file("../../production/wastecycle-be/Gateway.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionGatewayService" {
  content = "${file("../../production/wastecycle-be/GatewayService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionGatewayIngress" {
  content = "${file("../../production/wastecycle-be/GatewayIngress.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionHubspot" {
  content = "${file("../../production/wastecycle-be/Hubspot.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionIdentityDeployment" {
  content = "${file("../../production/wastecycle-be/IdentityDeployment.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionIdentityService" {
  content = "${file("../../production/wastecycle-be/IdentityService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionInquiries" {
  content = "${file("../../production/wastecycle-be/Inquiries.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionInquiriesService" {
  content = "${file("../../production/wastecycle-be/InquiriesService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}

resource "k8s_manifest" "productionMailSender" {
  content = "${file("../../production/wastecycle-be/MailSender.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionMailSenderService" {
  content = "${file("../../production/wastecycle-be/MailSenderService.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionSagaHandler" {
  content = "${file("../../production/wastecycle-be/SagaHandler.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
## FRONTEND
resource "k8s_manifest" "productionFrontendSecret" {
  content = "${file("../../production/wastecycle-fe/SSLSecret.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionFrontend" {
  content = "${file("../../production/wastecycle-fe/wastecycle-fe.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionFrontendService" {
  content = "${file("../../production/wastecycle-fe/Service.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}
resource "k8s_manifest" "productionFrontendIngress" {
  content = "${file("../../production/wastecycle-fe/Ingress.yml")}"
  depends_on = [
    "kubernetes_namespace.newproduction", ]
}