tflint {
  required_version = ">= 0.50"
}

config {
  format = "junit"
  plugin_dir = "~/.tflint.d/plugins"

  call_module_type = "local"
  force = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
    enabled = true
    version = "0.27.0"
    source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
