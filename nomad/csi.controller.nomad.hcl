job "plugin-azure-disk-controller" {
  datacenters = ["dc1"]
  type = "service"

  vault {
    policies = ["csi"]
  }

  group "controller" {
    count = 1

    # disable deployments
    update {
      max_parallel = 0
    }
    task "controller" {
      driver = "docker"

      template {
        change_mode = "noop"
        destination = "local/azure.json"
        data = <<EOH
{
"cloud":"AzurePublicCloud",
"tenantId": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.TENANT_ID}}{{end}}",
"subscriptionId": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.SUBSCRIPTION_ID}}{{end}}",
"aadClientId": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.CLIENT_ID}}{{end}}",
"aadClientSecret": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.CLIENT_SECRET}}{{end}}",
"resourceGroup": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.RESOURCE_GROUP}}{{end}}",
"location": "{{with secret "kv/data/azure/credentials"}}{{.Data.data.LOCATION}}{{end}}",
"useInstanceMetadata": true,
"vmType": "vmss",
"primaryScaleSetName": "uphs_{{with secret "kv/data/azure/credentials"}}{{.Data.data.LOCATION}}{{end}}_minion_vmss"
}
EOH
      }

      env {
        AZURE_CREDENTIAL_FILE = "/etc/kubernetes/azure.json"
      }

      config {
        image = "mcr.microsoft.com/k8s/csi/azuredisk-csi:v0.9.0"

        volumes = [
          "local/azure.json:/etc/kubernetes/azure.json"
        ]

        args = [
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--v=5",
        ]
      }

      csi_plugin {
        id        = "azure-disk1"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        memory = 256
      }

      # ensuring the plugin has time to shut down gracefully
      kill_timeout = "2m"
    }
  }
}