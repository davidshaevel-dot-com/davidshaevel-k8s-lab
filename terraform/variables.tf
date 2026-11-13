variable "subscription_id" {
  description = "Azure subscription to create the lab in. Set it in terraform.tfvars (gitignored)."
  type        = string
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the AKS API server: your own public IP as a /32 (curl -s https://ifconfig.me)."
  type        = list(string)
  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([for c in var.api_server_authorized_ip_ranges : can(cidrhost(c, 0))])
    error_message = "Give at least one CIDR, for example [\"203.0.113.7/32\"]."
  }
}

variable "prefix" {
  description = "Name prefix for every lab resource."
  type        = string
  default     = "k8s-lab"
}

variable "location" {
  description = "Region for the resource group, VNet, AKS cluster, registry and private endpoint."
  type        = string
  default     = "eastus"
}

variable "postgres_location" {
  description = "Region for the PostgreSQL server. Not eastus: Flexible Server provisioning is restricted there for this subscription (also eastus2, westus2, southcentralus). The private endpoint stays in the lab VNet."
  type        = string
  default     = "centralus"
}

variable "kubernetes_version" {
  description = "Pinned one minor version behind the newest AKS offers in East US, so scenario 1 has an upgrade to do. Read on 2026-11-12: newest 1.37.1, so 1.36.5 (newest 1.36 patch). Check: az aks get-versions --location eastus -o table"
  type        = string
  default     = "1.36.5"
}

# Address ranges. None of them overlaps the others or the platform cluster's
# (VNet 10.224.0.0/12, pods 10.244.0.0/16, services 10.0.0.0/16), so the two
# VNets can be peered later.
variable "vnet_cidr" {
  type    = string
  default = "10.100.0.0/16"
}

variable "nodes_subnet_cidr" {
  type    = string
  default = "10.100.0.0/22"
}

variable "private_endpoint_subnet_cidr" {
  type    = string
  default = "10.100.8.0/24"
}

variable "pod_cidr" {
  description = "Azure CNI Overlay pod range (not routable in the VNet)."
  type        = string
  default     = "10.120.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.130.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "10.130.0.10"
}

# Node sizes, chosen against the East US quota read on 2026-11-12: 20 regional
# vCPUs, 4 used by the platform cluster, so 16 free; DSv5 family 0 of 20 used.
# Peak here: 2 (system) + 3 x 2 (user, autoscaled) = 8 vCPUs, 12 during an
# upgrade with one surge node per pool.
variable "system_node_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "system_node_count" {
  type    = number
  default = 1
}

variable "user_node_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "user_node_min" {
  type    = number
  default = 1
}

variable "user_node_max" {
  type    = number
  default = 3
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "postgres_version" {
  type    = string
  default = "17"
}

variable "tags" {
  type    = map(string)
  default = { purpose = "k8s-lab", lifetime = "throwaway" }
}
