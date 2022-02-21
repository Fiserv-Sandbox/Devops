variable "rgname" {
  description = "Resource Group Name"
  default     = "github-action1"
  type        = string
}
variable "location" {
  description = "Azure location"
  default     = "East US"
  type        = string
}
variable "sname" {
  description = "Azure Storage Account"
  type        = string
}
variable "pe" {
  description = "Azure Private End Point account"
  type        = string
}

