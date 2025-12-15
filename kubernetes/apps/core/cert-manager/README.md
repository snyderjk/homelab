TODO: Add automated cert updates

# Get the certificate and key for pfsense
kubectl get secret pfsense-tls -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > firewall.crt
kubectl get secret pfsense-tls -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 -d > firewall.key

# Get the certificate and key for Synology
kubectl get secret nas-tls -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > nas.crt
kubectl get secret nas-tls -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 -d > nas.key


