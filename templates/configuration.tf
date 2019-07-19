listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

seal "awskms" {
  kms_key_id = "${kms_key_id}"
  region     = "${region}"
}

storage "dynamodb" {
  ha_enabled = "true"
  region     = "${region}"
}

ui = true
