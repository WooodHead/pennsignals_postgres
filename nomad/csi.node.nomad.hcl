job "plugin-azure-disk-nodes" {
  datacenters = ["dc1"]

  vault {
    policies = ["csi"]
  }

  # you can run node plugins as service jobs as well, but this ensures
  # that all nodes in the DC have a copy.
  type = "system"

  group "nodes" {
    task "node" {
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
          "--nodeid=${node.unique.name}",
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "-v=6",
        ]

        # node plugins must run as privileged jobs because they
        # mount disks to the host
        privileged = true
      }

      csi_plugin {
        id        = "azure-disk1"
        type      = "node"
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