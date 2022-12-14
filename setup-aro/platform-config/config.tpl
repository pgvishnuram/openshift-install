######################################
## Astronomer global configuration  ##
######################################
alertmanager:
  disableClustering: true
global:
  # Base domain for all subdomains exposed through ingresscd
  baseDomain: ${BASE_DOMAIN}
  postgresqlEnabled: false
  #clusterRoles: true
  # Name of secret containing TLS certificate
  tlsSecret: astronomer-tls
  helmRepo: "https://internal-helm.astronomer.io"
  sccEnabled: true
  nodeExporterEnabled: true
  ssl:
    enabled: true
    mode: "prefer"
#################################
### Nginx configuration
#################################
nginx:
  # IP address the nginx ingress should bind to
  loadBalancerIP: ~
astronomer:
  commander:
    replicas: 2
    env:
      - name: "COMMANDER_MANUAL_NAMESPACE_NAMES"
        value: false
  houston:
    config:
      allowedSystemLevelDomains:
        - astronomer.io
      publicSignups: true # Users need to be invited to have access to Astronomer. Set to true otherwise
      emailConfirmation: true # Users get an email verification before accessing Astronomer
      deployments:
        triggererEnabled: true
        sysAdminScalabilityImprovementsEnabled: true
        manualReleaseNames: true
        hardDeleteDeployment: true
        logHelmValues: true
        serviceAccountAnnotationKey: eks.amazonaws.com/role-arn # Flag to enable using IAM roles (don't enter a specific role)
        helm:
          airflow:
            defaultAirflowRepository: quay.io/astronomer/ap-airflow-dev
            images:
              airflow:
                repository: quay.io/astronomer/ap-airflow-dev
                pullPolicy: Always
              flower:
                repository: quay.io/astronomer/ap-airflow-dev
                pullPolicy: Always
      email:
        enabled: true
        smtpUrl: smtps://postmaster%40mg.astronomer.io:daf255573ca4f22c699c6c0c4ab2dfb0@smtp.mailgun.org/?pool=true
        reply: "himabindu@astronomer.io" # Emails will be sent from this address
      auth:
        # Local database (user/pass) configuration.
        github:
          enabled: true # Lets users authenticate with Github
        local:
          enabled: true # Disables logging in with just a username and password
        openidConnect:
          google:
            enabled: true # Lets users authenticate with Google

prometheus:
  # Configure resources
  resources:
    requests:
      cpu: "2000m"
      memory: "4Gi"
    limits:
      cpu: "3000m"
      memory: "12Gi"
