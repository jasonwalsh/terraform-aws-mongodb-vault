listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/vault.crt"
  tls_key_file  = "/etc/vault.d/vault.key"
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
