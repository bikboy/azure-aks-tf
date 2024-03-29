variable "kubetnetes_version" {
  type        = "string"
  description = "The k8s version to deploy eg: '1.8.5', '1.10.5' etc"
  default     = "1.10.5"
}

variable "vm_size" {
  description = "The VM_SKU to use for the agents in the cluster"
  default     = "Standard_DS2_v2"
}

variable "node_count" {
  description = "The number of agents nodes to provision in the cluster"
  default     = "3"
}

variable "resource_group_name" {
  type        = "string"
  description = "Name of the azure resource group."
  default     = "akc-rg"
}

variable "resource_group_location" {
  type        = "string"
  description = "Location of the azure resource group."
  default     = "eastus"
}

variable "linux_admin_username" {
  type        = "string"
  description = "User name for authentication to the Kubernetes linux agent virtual machines in the cluster."
  default     = "terraform"
}

variable "linux_admin_ssh_publickey" {
  type        = "string"
  description = "Configure all the linux virtual machines in the cluster with the SSH RSA public key string. The key should include three parts, for example 'ssh-rsa AAAAB...snip...UcyupgH azureuser@linuxvm'"
}

variable "sp_least_privilidge" {
  default     = false
  description = "[Alpha] This feature creates a limited role for use by the K8s Service principal which limits access to only those resources needed for k8s operation"
}
variable "docker_login" {
  type = "string"
  description = "login to docker hub registry"
}
variable "docker_password" {
  type = "string"
  description = "password to docker hub registry"
}
variable "docker_email" {
  type = "string"
  description = "email to docker hub registry"
}