output "engine_public_ip" {
  value = aws_instance.engine.public_ip
}

output "engine_private_ip" {
  value = aws_instance.engine.private_ip
}

output "inference_worker_private_ip" {
  value = aws_instance.inference.private_ip
}

output "caller_worker_private_ip" {
  value = aws_instance.caller.private_ip
}

output "ssh_command_engine" {
  value = "ssh -i iii-key.pem ubuntu@${aws_instance.engine.public_ip}"
}

# Proxy SSH command to jump through Engine Gateway (Bastion) to access the private Inference Worker
output "ssh_command_inference" {
  value = "ssh -i iii-key.pem -o ProxyCommand=\"ssh -i iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %%h:%%p ubuntu@${aws_instance.engine.public_ip}\" ubuntu@${aws_instance.inference.private_ip}"
}

# Proxy SSH command to jump through Engine Gateway (Bastion) to access the private Caller Worker
output "ssh_command_caller" {
  value = "ssh -i iii-key.pem -o ProxyCommand=\"ssh -i iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %%h:%%p ubuntu@${aws_instance.engine.public_ip}\" ubuntu@${aws_instance.caller.private_ip}"
}
