#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2023-07-26 00:38:43 +0100 (Wed, 26 Jul 2023)
#
#  https://github.com/HariSekhon/DevOps-Bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
. "$srcdir/lib/utils.sh"

# shellcheck disable=SC1090,SC1091
. "$srcdir/lib/kubernetes.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Creates a Kubernetes external secret yaml from a given secret in the current or given namespace

- generates external secret yaml - if GENERATE_YAML_ONLY env var is set to any value, then stops here
- checks the GCP Secret Manager secret exists
  - if it doesn't, creates it
  - if it does, validates that its content matches the existing secret in Kubernetes
  - if there is a difference and OVERWRITE_GCP_SECRET env var is set to any value, creates a new version and uses that - XXX: use this carefully
- creates external secret in the same namespace

Useful to migrate existing secrets to external secrets referencing GCP Secret Manager

See kubernetes_secrets_to_external_secrets_gcp.sh to quickly migrate all your secrets to external secrets

Use kubectl_secrets_download.sh to take a backup of existing kubernetes secrets first

XXX: you should probably omit committing secrets generated by Cert Manager (eg. *-tls)


Requires kubectl and GCloud SDK to both be in the \$PATH and configured
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="<secret_name> [<namespace> <context>]"

help_usage "$@"

min_args 1 "$@"

check_bin kubectl
check_bin gcloud

secret="$1"
namespace="${2:-}"
context="${3:-}"

kube_config_isolate

if [ -n "$context" ]; then
    kube_context "$context"
fi
if [ -n "$namespace" ]; then
    kube_namespace "$namespace"
fi

if [ -z "${namespace:-}" ]; then
    namespace="$(kube_current_namespace)"
fi

yaml_file="external-secret-$secret.yaml"

timestamp "Generating external secret for secret '$secret'"

# if the secret has a dash in it, then you need to quote it whether .data."$secret" or .data["$secret"]
k8s_secret_value="$(kubectl get secret "$secret" -o json | jq -r ".data[\"$secret\"]" | base64 --decode)"

if [ -z "$k8s_secret_value" ]; then
    timestamp "ERROR: failed to get Kubernetes secret value for '$secret' key '$secret'"
    exit 1
fi

# https://github.com/HariSekhon/Kubernetes-configs/blob/master/external-secret.yaml
yaml="---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: $secret
  namespace: $namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    #kind: SecretStore
    kind: ClusterSecretStore
  target:
    name: $secret
    creationPolicy: Merge
  data:
    - secretKey: $secret  # key within k8s secret
      remoteRef:
        key: $secret  # GCP Secret Manager secret
"

# remove the sed line if you want to leave the comments in the generated files
echo "$yaml" \
    | sed 's/#.*$//; s/[[:space:]]*$//; /^[[:space:]]*$/d' \
    > "$yaml_file"

if [ -n "${GENERATE_YAML_ONLY:-}" ]; then
    exit 0
fi

timestamp "Generated external-secret yaml file:  $yaml_file"

timestamp "Checking GCP Secret Manager for secret '$secret'"

if gcloud secrets list --format='value(name)' | grep -Fxq "$secret"; then
    timestamp "GCP secret '$secret' already exists"
    timestamp "Checking Kubernetes secret '$secret' content matches GCP secret '$secret' content"
    timestamp "Getting GCP secret '$secret' value"
    gcp_secret_value="$("$srcdir/../gcp/gcp_secret_get.sh" "$secret")"
    # if it's GCP service account key
    if grep -Fq '"type": "service_account"' <<< "$gcp_secret_value"; then
        # doesn't work
        #if [ "$(jq -Mr <<< "$gcp_secret_value")" = "$(jq -Mr <<< "$k8s_secret_value")" ]; then
        # if there are no whitespace differences between the service account keys then accept
        if [ -n "$(diff -w <(echo "$gcp_secret_value") <(echo "$k8s_secret_value") )" ]; then
            timestamp "ERROR: GCP secret service account json does not match existing Kubernetes secret service account json"
            exit 1
        fi
    elif [ "$gcp_secret_value" = "$k8s_secret_value" ]; then
        timestamp "GCP and Kubernetes secret values match"
    elif [ "${OVERWRITE_GCP_SECRET:-}" ]; then
        timestamp "UPDATING GCP secret '$secret' value"
        gcloud secrets versions add "$secret" --data-file=- <<< "$k8s_secret_value"
    else
        timestamp "ERROR: GCP secret value does not match existing Kubernetes secret value - careful manual reconciliation required"
        exit 1
    fi
else
    timestamp "GCP secret '$secret' doesn't exist"
    timestamp "CREATING GCP secret '$secret' from the content of the Kubernetes secret '$secret'"
    "$srcdir/../gcp/gcp_secret_add.sh" "$secret" "$k8s_secret_value"
    timestamp "GCP secret '$secret' created"
fi

timestamp "Applying external secret '$secret'"

kubectl apply -f "$yaml_file"
