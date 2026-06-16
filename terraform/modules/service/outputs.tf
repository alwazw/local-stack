output "container_id" {
  description = "Container ID"
  value       = docker_container.this.id
}

output "container_name" {
  description = "Container name"
  value       = docker_container.this.name
}
