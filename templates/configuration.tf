listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/vault.crt.pem"
  tls_key_file  = "/opt/vault/tls/vault.key.pem"
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
