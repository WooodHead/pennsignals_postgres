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
"primaryScaleSetName": "uphs_{{with secret "kv/data/azure/credentials"}}{{.Data.data.ENV}}{{end}}_minion_vmss"
}
EOH
      }

      env {
        AZURE_CREDENTIAL_FILE = "/etc/kubernetes/azure.json"
      }

      config {
        image   = "[[ .services.csi.image.registry ]]/[[ .services.csi.image.name ]]:[[ .services.csi.image.tag ]]"

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
        id        = "[[ .services.csi.plugin.id ]]"
        type      = "controller"
        mount_dir = "[[ .services.csi.plugin.mount_dir ]]"
      }

      resources {
        memory  = "[[ .services.csi.resources.memory ]]"
      }

      # ensuring the plugin has time to shut down gracefully
      kill_timeout = "2m"
    }
  }
}