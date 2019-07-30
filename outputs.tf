output "dns_name" {
  description = "The DNS name of the load balancer"
  value       = module.alb.dns_name
}

output "dashboard" {
  description = "URL to launch the CloudWatch dashboard for monitoring"
  value = format(
    "https://console.aws.amazon.com/cloudwatch/home?region=%s#dashboards:name=%s",
    data.aws_region.region.name,
    aws_cloudwatch_dashboard.cloudwatch_dashboard.dashboard_name
  )
}
