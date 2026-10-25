# 01 - Kubernetes Fundamentals

> **Goal of this module:** understand what Kubernetes is, how a cluster is built, and run your first Pod on a local cluster.

**Estimated time:** 2 to 3 hours · **Level:** beginner (Docker knowledge required)

---

## 1. Why Kubernetes?

With Docker, you can run a container on one machine. In production, this quickly raises questions:

- What happens if the container crashes at 3 AM?
- How do I run 5 copies of my API and spread the traffic between them?
- How do I deploy a new version without downtime?
- How do I run containers across several servers?

**Kubernetes (K8s)** is a container orchestrator. You describe the state you want ("I want 3 copies of this app running"), and Kubernetes works continuously to make reality match that description.

| Problem | What Kubernetes gives you |
|---------|---------------------------|
| Crashes | **Self-healing**: failed containers are restarted or rescheduled |
| Traffic growth | **Scaling**: add or remove replicas manually or automatically |
| New versions | **Rolling updates** and **rollbacks** with no downtime |
| Many services | **Service discovery** and built-in load balancing |
| Config and passwords | **ConfigMaps** and **Secrets** |
| Many servers | **Scheduling**: containers are placed on the best available node |

> **Key idea: declarative model.** You don't tell Kubernetes *how* to do things step by step. You declare the **desired state**, and Kubernetes keeps comparing it with the **actual state** and fixes any difference.

---

## 2. Cluster architecture

A Kubernetes **cluster** is a set of machines split into two roles.

```
┌───────────────────────── CLUSTER ─────────────────────────┐
│                                                           │
│  ┌──────────── CONTROL PLANE (the brain) ─────────────┐   │
│  │  kube-apiserver   etcd   scheduler   controller-mgr│   │
│  └─────────────────────────┬──────────────────────────┘   │
│                            │                              │
│        ┌───────────────────┼───────────────────┐          │
│        ▼                   ▼                   ▼          │
│  ┌──── NODE 1 ───┐  ┌──── NODE 2 ───┐  ┌──── NODE 3 ───┐  │
│  │ kubelet       │  │ kubelet       │  │ kubelet       │  │
│  │ kube-proxy    │  │ kube-proxy    │  │ kube-proxy    │  │
│  │ runtime       │  │ runtime       │  │ runtime       │  │
│  │ [Pod] [Pod]   │  │ [Pod]         │  │ [Pod] [Pod]   │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### Control plane components (the brain)

| Component | Role |
|-----------|------|
| **kube-apiserver** | The front door. Every command (`kubectl`, other components) goes through its REST API. |
| **etcd** | Key-value database storing the whole state of the cluster. |
| **kube-scheduler** | Decides **which node** a new Pod should run on. |
| **kube-controller-manager** | Runs controllers that watch the cluster and fix differences between desired and actual state. |

### Node components (the workers)

| Component | Role |
|-----------|------|
| **kubelet** | Agent on each node. Makes sure the containers described for that node are running and healthy. |
| **kube-proxy** | Handles networking rules so Pods and Services can communicate. |
| **Container runtime** | Actually runs the containers (containerd, CRI-O). Docker images work fine. |

### What happens when you run `kubectl apply`?

1. `kubectl` sends your YAML to the **API server**.
2. The API server validates it and stores it in **etcd**.
3. The **scheduler** notices a Pod with no node and picks one.
4. The **kubelet** on that node pulls the image and starts the container.
5. Controllers keep watching to make sure it stays that way.

---

## 3. Core concepts

### Pod
The **smallest deployable unit** in Kubernetes. A Pod wraps one (sometimes more) containers that share the same network (one IP address) and storage.

- Most Pods contain **one container**.
- Pods are **ephemeral**: if one dies, it is not automatically replaced (unless a controller manages it, see module 02).
- Each Pod gets its own IP, which changes if the Pod is recreated.

### Node
A machine (physical or virtual) in the cluster. With Minikube, your local cluster has a single node that acts as both control plane and worker.

### Namespace
A virtual partition inside a cluster to organize resources (for example `dev`, `staging`, `prod`). Default namespaces:

| Namespace | Purpose |
|-----------|---------|
| `default` | Where your resources go if you don't specify one |
| `kube-system` | Kubernetes system components |
| `kube-public` | Publicly readable data |
| `kube-node-lease` | Node heartbeats |

### Labels
Key-value tags attached to resources (for example `app: nginx`). Kubernetes uses labels to **select and group** resources. They become essential from module 02.

### Manifest (YAML)
A file describing a resource. Every manifest has four main parts:

```yaml
apiVersion: v1          # API version of the resource
kind: Pod               # Type of resource
metadata:               # Name, labels, namespace
  name: nginx-pod
spec:                   # Desired state (the content depends on the kind)
  containers:
    - name: nginx
      image: nginx:1.27
```

### Imperative vs declarative

| Approach | Example | When to use |
|----------|---------|-------------|
| **Imperative** | `kubectl run nginx --image=nginx` | Quick tests and learning |
| **Declarative** | `kubectl apply -f pod.yaml` | Real projects (versioned in Git) |

---

## 4. kubectl basics

`kubectl` is the command-line tool to talk to the API server. The general pattern:

```
kubectl <verb> <resource> [name] [flags]
```

| Command | What it does |
|---------|--------------|
| `kubectl get pods` | List Pods |
| `kubectl get pods -o wide` | List with extra info (node, IP) |
| `kubectl describe pod <name>` | Detailed info and **events** (first stop for debugging) |
| `kubectl logs <name>` | Show container logs |
| `kubectl exec -it <name> -- sh` | Open a shell inside the container |
| `kubectl apply -f <file>` | Create or update from a manifest |
| `kubectl delete pod <name>` | Delete a Pod |
| `kubectl get pod <name> -o yaml` | Show the full YAML stored in the cluster |
| `kubectl explain pod.spec` | Built-in documentation of any field |
| `kubectl api-resources` | List all resource types |

> 💡 `kubectl explain` is a hidden gem: for example `kubectl explain pod.spec.containers` documents every field without leaving the terminal.

---

## 5. Pod lifecycle and common statuses

| Status | Meaning |
|--------|---------|
| `Pending` | Accepted by the cluster, waiting to be scheduled or for the image to be pulled |
| `ContainerCreating` | Image is being pulled, container is being created |
| `Running` | At least one container is running |
| `Succeeded` | All containers finished successfully (jobs) |
| `Failed` | A container ended with an error |
| `CrashLoopBackOff` | The container keeps crashing and Kubernetes keeps restarting it with growing delays |
| `ImagePullBackOff` / `ErrImagePull` | The image cannot be pulled (wrong name, tag or registry access) |

### Debugging checklist

1. `kubectl get pods`: what is the status?
2. `kubectl describe pod <name>`: read the **Events** section at the bottom.
3. `kubectl logs <name>`: what does the application say? (`--previous` for a crashed container)
4. `kubectl exec -it <name> -- sh`: look inside if it is running.

---

## 6. Hands-on: your first cluster and Pod

### Step 1: Start the cluster

```bash
minikube start
```

### Step 2: Verify it works

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

You should see one node in `Ready` status and the system Pods in `kube-system`.

### Step 3: Run a Pod imperatively

```bash
kubectl run nginx-test --image=nginx:1.27
kubectl get pods
kubectl describe pod nginx-test
```

### Step 4: Run a Pod declaratively

Use the manifest in [`manifests/pod.yaml`](./manifests/pod.yaml):

```bash
kubectl apply -f manifests/pod.yaml
kubectl get pods -o wide
```

### Step 5: Access the Pod

Pods have internal IPs only. For testing, forward a local port to the Pod:

```bash
kubectl port-forward pod/nginx-pod 8080:80
```

Open http://localhost:8080 in your browser. Stop with `Ctrl+C`.

### Step 6: Inspect it from the inside

```bash
kubectl logs nginx-pod
kubectl exec -it nginx-pod -- sh
# inside the container:
ls /usr/share/nginx/html
exit
```

### Step 7: Clean up

```bash
kubectl delete -f manifests/pod.yaml
kubectl delete pod nginx-test
```

> ⚠️ Delete a Pod and it stays deleted. Nothing recreates it. This is exactly the limitation that **Deployments** solve in module 02.

---

## 7. Key takeaways

- Kubernetes keeps the **actual state** equal to the **desired state** you declare.
- The **control plane** decides and stores; the **nodes** run the containers.
- A **Pod** is the smallest unit and is **ephemeral**.
- Prefer **declarative YAML** files versioned in Git.
- When something fails: `get` → `describe` → `logs`.

## ✅ Checklist

- [ok] I can explain what Kubernetes solves compared to plain Docker
- [ok] I can name the control plane and node components and their roles
- [ok] I can write a basic Pod manifest from memory
- [ok] I can start Minikube and run `kubectl get nodes`
- [ok] I can debug a Pod with `describe` and `logs`

**Next:** [02 - Workloads](../02-workloads/README.md) (Deployments, ReplicaSets, rolling updates)