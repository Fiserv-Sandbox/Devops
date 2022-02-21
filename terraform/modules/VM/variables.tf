variable "rgname" {
  type        = string
  description = "RG name in Azure"
}

variable "vmadminpassword" {
  type        = string
  description = "VM password in Azure"
  sensitive   = true
}

variable "location" {
  type = string
}

variable "nicname" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "computer_name" {
  type = string
}

variable "vmadmin_name" {
  type = string
}

variable "osdiskname" {
  type = string
}
variable "node_resource_group" {
  type = string
}
