output "web_ip" {
  description = "IP da VM web"
  value       = local.vms["web"].ip
}

output "api_db_ip" {
  description = "IP da VM API + MySQL"
  value       = local.vms["db"].ip
}