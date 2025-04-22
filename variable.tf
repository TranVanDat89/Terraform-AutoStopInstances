variable "region" {
  type = string
  default = "ap-southeast-2"
}

variable "sns_email" {
  description = "The email address to subscribe to the SNS topic"
  type        = string
  default = "tranvandatdh012@gmail.com"
}