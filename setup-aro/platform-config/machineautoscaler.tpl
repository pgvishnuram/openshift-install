apiVersion: "autoscaling.openshift.io/v1beta1"
kind: "MachineAutoscaler"
metadata:
  name: ${WORKER_NAMES}
  namespace: "openshift-machine-api"
spec:
  minReplicas: 2
  maxReplicas: ${WORKER_AUTOSCALE_COUNT}
  scaleTargetRef:
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet
    name: ${WORKER_NAMES}
