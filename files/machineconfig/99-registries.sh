cat << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    node-role.kubernetes.io/worker:
#    machineconfiguration.openshift.io/role: master
  name: 99-registries
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - mode: 420
        overwrite: true
        path: /etc/containers/registries.d/99-registries.conf
        contents:
          source: data:text/plain;charset=utf-8;base64,dW5xdWFsaWZpZWQtc2VhcmNoLXJlZ2lzdHJpZXMgPSBbJ3JlZ2lzdHJ5LmFjY2Vzcy5yZWRoYXQuY29tJywgJ2RvY2tlci5pbycsICdxdWF5LmlvJywgJ2RvY2tlci5zaWxpY29tLmRrOjUwMDAnXQoKW1tyZWdpc3RyeV1dCnByZWZpeD0icXVheS5pby9yeWFuX3JhYXNjaCIKbG9jYXRpb249ImRvY2tlci5zaWxpY29tLmRrOjUwMDAvcnlhbl9yYWFzY2giCgpbW3JlZ2lzdHJ5XV0KcHJlZml4PSJyeWFuX3JhYXNjaCIKbG9jYXRpb249ImRvY2tlci5zaWxpY29tLmRrOjUwMDAvcnlhbl9yYWFzY2giCgo=
      - mode: 420
        overwrite: true
        path: /usr/share/rhel/secrets/etc-pki-entitlement/entitlement.pem
        contents:
          source: data:text/plain;charset=utf-8;base64,$(cat pki.key | base64)
      - mode: 420
        overwrite: true
        path: /usr/share/rhel/secrets/etc-pki-entitlement/entitlement-key.pem
        contents:
          source: data:text/plain;charset=utf-8;base64,$(cat pki.key | base64)
#cat << EOF | base64
# unqualified-search-registries = ['registry.access.redhat.com', 'docker.io', 'quay.io', 'docker.silicom.dk:5000']
#[[registry]]
#prefix="quay.io/ryan_raasch"
#location="docker.silicom.dk:5000/ryan_raasch"

#[[registry]]
#prefix="ryan_raasch"
#location="docker.silicom.dk:5000/ryan_raasch"
EOF
