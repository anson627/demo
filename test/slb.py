from kubernetes import client, config
import numpy as np
import time

NAMESPACE="slb-test"

def create_deployment(api, name):
    container = client.V1Container(
        name="nginx",
        image="nginx:1.15.4",
        ports=[client.V1ContainerPort(container_port=80)],
        resources=client.V1ResourceRequirements(
            requests={"cpu": "100m", "memory": "200Mi"},
            limits={"cpu": "500m", "memory": "500Mi"},
        ),
    )

    template = client.V1PodTemplateSpec(
        metadata=client.V1ObjectMeta(labels={"app": "nginx"}),
        spec=client.V1PodSpec(containers=[container]),
    )

    spec = client.V1DeploymentSpec(
        replicas=100, template=template, selector={
            "matchLabels":
            {"app": "nginx"}})

    deployment = client.V1Deployment(
        api_version="apps/v1",
        kind="Deployment",
        metadata=client.V1ObjectMeta(name=name),
        spec=spec,
    )

    resp = api.create_namespaced_deployment(
        body=deployment,
        namespace=NAMESPACE
    )

    print("\n[INFO] deployment created.\n")

def delete_deployment(api, name):
    resp = api.delete_namespaced_deployment(
        name=name,
        namespace=NAMESPACE,
        body=client.V1DeleteOptions(
            propagation_policy="Foreground", grace_period_seconds=5
        ),
    )
    print("\n[INFO] deployment deleted.")


def create_service(api, name):
    service = client.V1Service(
        api_version="v1",
        kind="Service",
        metadata=client.V1ObjectMeta(
            name=name
        ),
        spec=client.V1ServiceSpec(
            selector={"app": "nginx"},
            type="LoadBalancer",
            ports=[client.V1ServicePort(
                port=80,
                target_port=80
            )]
        )
    )

    resp = api.create_namespaced_service(
        body=service,
        namespace=NAMESPACE
    )

    print("\n[INFO] service created.\n")


def delete_service(api, name):
    resp = api.delete_namespaced_service(
        name=name,
        namespace=NAMESPACE,
        body=client.V1DeleteOptions(
            propagation_policy="Foreground", grace_period_seconds=5
        ),
    )
    print("\n[INFO] service deleted.")


def get_latencies(api):
    service_list = api.list_namespaced_service(namespace=NAMESPACE)

    latencies = []
    for service in service_list.items:
        metadata = service.metadata
        creation_timestamp = metadata.creation_timestamp
        for field in metadata.managed_fields:
            if field.manager == 'cloud-controller-manager':
                update_timestamp = field.time
                latencies.append(update_timestamp - creation_timestamp)

    return latencies


def main():
    config.load_kube_config()
    apps_v1 = client.AppsV1Api()
    core_v1 = client.CoreV1Api()
    total = 2
    # for i in range(0, total):
    #     name = "slb-test-{0}".format(i)
    #     create_deployment(apps_v1, name)
    #     create_service(core_v1, name)
    #     time.sleep(1)

    latencies = get_latencies(core_v1)

    p50 = np.percentile(latencies, 50)
    p90 = np.percentile(latencies, 90)
    p99 = np.percentile(latencies, 99)
    result = [
        {
            "metric": "LoadBalancerProvisionLatency_create_to_ready_Perc50",
            "value": p50,
            "labels": {
                "group": "public-load-balancer"
            },
        },
        {
            "metric": "LoadBalancerProvisionLatency_create_to_ready_Perc90",
            "value": p90,
            "labels": {
                "group": "public-load-balancer"
            },
        },
                {
            "metric": "LoadBalancerProvisionLatency_create_to_ready_Perc99",
            "value": p99,
            "labels": {
                "group": "public-load-balancer"
            },
        },
    ]
    print("\n[INFO] latency ready.", p50, p90, p99)

if __name__ == "__main__":
    main()