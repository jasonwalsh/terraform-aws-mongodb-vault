listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/pki/tls/certs/vault.csr"
  tls_key_file  = "/etc/pki/tls/private/vault.pem"
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
