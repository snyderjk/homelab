#### Create temp pod to initialize hermes and store data in pvc

kubectl run hermes-setup -it --rm -n hermes \
  --image=nousresearch/hermes-agent:latest \
  --overrides='
{
  "spec": {
    "securityContext": {
      "fsGroup": 10000
    },
    "containers": [
      {
        "name": "hermes",
        "image": "nousresearch/hermes-agent:latest",
        "stdin": true,
        "tty": true,
        "envFrom": [
          {
            "secretRef": {
              "name": "hermes-secrets"
            }
          }
        ],
        "volumeMounts": [
          {
            "name": "data-storage",
            "mountPath": "/opt/data"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "data-storage",
        "persistentVolumeClaim": {
          "claimName": "hermes-data-pvc"
        }
      }
    ]
  }
}
' -- /bin/sh -c "/opt/hermes/docker/entrypoint.sh setup"
